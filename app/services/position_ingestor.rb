# frozen_string_literal: true

class PositionIngestor
  Result = Struct.new(
    :success, :skipped, :updated,
    :bus, :trip, :gps_log, :current_position, :position_history,
    :error, :message,
    keyword_init: true
  ) do
    def success?
      success
    end

    def skipped?
      skipped
    end

    def failure?
      !success
    end
  end

  MAX_EPOCH_SECONDS = 2_147_483_647

  def self.call(raw_position, source: :traccar)
    new(raw_position, source).call
  end

  def initialize(raw_position, source)
    @raw = normalize_raw(raw_position)
    @source = source
  end

  def call
    bus = find_bus
    return skipped(:unknown_device) unless bus

    lat = to_decimal(extract(:lat))
    lng = to_decimal(extract(:lng))
    return skipped(:missing_coordinates) if lat.nil? || lng.nil?

    recorded_at = parse_timestamp(extract(:timestamp))

    ActiveRecord::Base.transaction do
      trip = find_or_create_active_trip(bus, recorded_at)
      gps_log = create_gps_log(trip, lat, lng, recorded_at)
      position_history = create_position_history(bus, lat, lng, recorded_at)
      current_position, updated = upsert_current_position(bus, lat, lng, recorded_at)

      # 오래된 GPS(CurrentPosition 미갱신)로는 이벤트를 판정하지 않는다 —
      # 히스토리에 기록된 과거 점이 previous로 잡혀 가짜 도착·출발 이벤트가 생긴다.
      StopEventDetector.call(bus: bus, current_position: current_position) if updated

      Result.new(
        success: true,
        skipped: false,
        updated: updated,
        bus: bus,
        trip: trip,
        gps_log: gps_log,
        current_position: current_position,
        position_history: position_history
      )
    end
  rescue ActiveRecord::RecordInvalid => e
    Result.new(
      success: false,
      skipped: false,
      updated: false,
      error: :invalid_record,
      message: e.message
    )
  end

  private

  def normalize_raw(raw)
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    raw.is_a?(Hash) ? raw.deep_symbolize_keys : {}
  end

  def extract(key)
    case key
    when :unique_id
      device_field(:uniqueId) || @raw[:uniqueId] || @raw[:id]
    when :lat
      position_field(:latitude) || @raw[:lat]
    when :lng
      position_field(:longitude) || @raw[:lon]
    when :timestamp
      position_field(:fixTime) || position_field(:deviceTime) || @raw[:timestamp]
    when :speed
      position_field(:speed) || @raw[:speed]
    when :bearing
      position_field(:course) || position_field(:bearing) || @raw[:bearing]
    when :accuracy
      position_field(:accuracy) || @raw[:accuracy] || @raw[:hdop]
    when :battery
      (position_field(:attributes) || {})[:batteryLevel] || position_field(:batteryLevel) || @raw[:batt]
    end
  end

  def position_field(key)
    (@raw[:position] || {})[key]
  end

  def device_field(key)
    (@raw[:device] || {})[key]
  end

  def find_bus
    unique_id = extract(:unique_id)
    return nil if unique_id.blank?

    Bus.find_by(traccar_unique_id: unique_id.to_s)
  end

  def to_decimal(value)
    return nil if value.blank?

    Float(value, exception: false)&.to_d
  end

  def to_float(value)
    return nil if value.blank?

    Float(value, exception: false)
  end

  def to_integer(value)
    f = to_float(value)
    f&.round
  end

  def parse_timestamp(value)
    return Time.current if value.blank?

    text = value.to_s.strip

    if text.include?("T")
      Time.zone.parse(text) || Time.current
    elsif numeric?(text)
      epoch = text.to_f
      epoch < MAX_EPOCH_SECONDS ? Time.zone.at(epoch) : Time.zone.at(epoch / 1000.0)
    else
      Time.zone.parse(text) || Time.current
    end
  rescue ArgumentError, TypeError
    Time.current
  end

  def numeric?(text)
    /\A-?\d+(\.\d+)?\z/.match?(text)
  end

  def find_or_create_active_trip(bus, recorded_at)
    trip = bus.trips.where(ended_at: nil).order(started_at: :desc).first
    trip || bus.trips.create!(started_at: recorded_at)
  rescue ActiveRecord::RecordNotUnique
    # 동시 수신(포워딩 + /gps)이 열운행 Trip을 이미 생성한 경우 — 재조회해 재사용한다.
    bus.trips.where(ended_at: nil).order(started_at: :desc).first || raise
  end

  def create_gps_log(trip, lat, lng, recorded_at)
    trip.gps_logs.create!(
      lat: lat,
      lng: lng,
      recorded_at: recorded_at
    )
  end

  def create_position_history(bus, lat, lng, recorded_at)
    bus.position_histories.create!(
      lat: lat,
      lng: lng,
      recorded_at: recorded_at,
      received_at: Time.current,
      speed: to_float(extract(:speed)),
      bearing: to_float(extract(:bearing)),
      accuracy: to_float(extract(:accuracy)),
      battery: to_integer(extract(:battery))
    )
  end

  MAX_UPSERT_ATTEMPTS = 3

  def upsert_current_position(bus, lat, lng, recorded_at)
    attempts = 0
    current = CurrentPosition.find_or_initialize_by(bus_id: bus.id)

    begin
      if current.persisted? && current.recorded_at > recorded_at
        return [ current, false ]
      end

      current.assign_attributes(
        lat: lat,
        lng: lng,
        recorded_at: recorded_at,
        received_at: Time.current,
        speed: to_float(extract(:speed)),
        bearing: to_float(extract(:bearing)),
        accuracy: to_float(extract(:accuracy)),
        battery: to_integer(extract(:battery))
      )
      current.save!
      [ current, true ]
    rescue ActiveRecord::RecordNotUnique
      # 동시 수신이 같은 버스의 CurrentPosition을 먼저 저장한 경우 —
      # 재조회 후 recorded_at 비교 분기로 되돌아간다.
      attempts += 1
      raise if attempts >= MAX_UPSERT_ATTEMPTS

      current = CurrentPosition.find_by!(bus_id: bus.id)
      retry
    end
  end

  def skipped(reason)
    Result.new(success: true, skipped: true, updated: false, error: reason)
  end
end
