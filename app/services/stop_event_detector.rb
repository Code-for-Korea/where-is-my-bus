class StopEventDetector
  APPROACH_RADIUS = 200.0
  ARRIVE_RADIUS   = 30.0
  DEPART_RADIUS   = 100.0
  DEDUP_WINDOW    = 1.hour

  def self.call(bus:, current_position:)
    new(bus: bus, current_position: current_position).call
  end

  def initialize(bus:, current_position:)
    @bus = bus
    @current_position = current_position
  end

  def call
    return unless @current_position

    previous = previous_position
    stops = @bus.routes.flat_map(&:stops).uniq.select(&:coordinates?)

    stops.each do |stop|
      current_distance  = haversine_distance(@current_position.lat, @current_position.lng, stop.lat, stop.lng)
      previous_distance = previous ? haversine_distance(previous.lat, previous.lng, stop.lat, stop.lng) : nil

      if current_distance <= ARRIVE_RADIUS
        create_event(stop, "arrive") unless recent_event?(stop, "arrive")
      elsif previous_distance && previous_distance <= ARRIVE_RADIUS && current_distance >= DEPART_RADIUS
        create_event(stop, "depart") unless recent_event?(stop, "depart")
      elsif current_distance <= APPROACH_RADIUS && moving_toward?(current_distance, previous_distance)
        create_event(stop, "approach") unless recent_event?(stop, "approach")
      end
    end
  end

  private

  def previous_position
    @bus.position_histories
        .where("recorded_at < ?", @current_position.recorded_at)
        .order(recorded_at: :desc)
        .first
  end

  def recent_event?(stop, event_type)
    StopEvent.where(bus: @bus, stop: stop, event_type: event_type)
             .where("occurred_at > ?", DEDUP_WINDOW.ago)
             .exists?
  end

  def create_event(stop, event_type)
    occurred_at = @current_position.recorded_at
    time_bucket = occurred_at.to_i / DEDUP_WINDOW.to_i
    dedup_key = "#{@bus.id}-#{stop.id}-#{event_type}-#{time_bucket}"

    StopEvent.create!(
      bus: @bus,
      stop: stop,
      event_type: event_type,
      occurred_at: occurred_at,
      dedup_key: dedup_key
    )
  rescue ActiveRecord::RecordNotUnique
    # 동시 처리로 인한 중복 — 무시
  end

  def moving_toward?(current_distance, previous_distance)
    previous_distance.nil? || current_distance < previous_distance
  end

  def haversine_distance(lat1, lng1, lat2, lng2)
    rad_per_deg = Math::PI / 180
    rm = 6371000.0

    dlat_rad = (lat2 - lat1) * rad_per_deg
    dlng_rad = (lng2 - lng1) * rad_per_deg

    lat1_rad = lat1 * rad_per_deg
    lat2_rad = lat2 * rad_per_deg

    a = Math.sin(dlat_rad / 2)**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlng_rad / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    rm * c
  end
end
