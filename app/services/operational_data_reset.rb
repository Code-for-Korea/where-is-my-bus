# 로그인 계정(User, Session)만 남기고 운영 데이터(방문·운행·노선 정류장·차량·정류장·노선)를 지우고,
# Rails가 알고 있는 Traccar 자원(device/geofence/group)도 함께 지운다(ops:reset_data가 호출한다).
#
# Traccar 호출은 롤백되지 않으므로 Traccar를 먼저 지우고, 하나라도 실패하면 Rails는 건드리지 않고 중단한다.
# 이미 없는 자원(404)은 지운 것으로 보므로 실패 뒤 다시 실행해도 안전하다.
# Rails가 ID를 모르는 Traccar 자원(수동으로 만든 것 등)과 Traccar 사용자 계정은 건드리지 않는다.
class OperationalDataReset
  include TraccarApiClient

  Outcome = Struct.new(:ok, :errors, keyword_init: true) do
    def success? = ok
  end

  RAILS_MODELS = [ StopVisit, Trip, RouteStop, Bus, Stop, Route ].freeze

  # [Traccar 경로, 모델, ID 컬럼] — device를 먼저 지우고, 그다음 geofence, group 순서.
  TRACCAR_RESOURCES = [
    [ "devices", Bus, :traccar_device_id ],
    [ "geofences", Stop, :traccar_geofence_id ],
    [ "groups", Route, :traccar_group_id ]
  ].freeze

  class << self
    def counts
      RAILS_MODELS.to_h { |model| [ model.name, model.count ] }.merge(
        "Traccar devices" => ids_for(Bus, :traccar_device_id).size,
        "Traccar geofences" => ids_for(Stop, :traccar_geofence_id).size,
        "Traccar groups" => ids_for(Route, :traccar_group_id).size
      )
    end

    def call(logger: ->(_) { })
      errors = delete_traccar_resources(logger)
      return Outcome.new(ok: false, errors: errors) if errors.any?

      ActiveRecord::Base.transaction do
        RAILS_MODELS.each do |model|
          count = model.delete_all
          logger.call("#{model.name}: #{count}건 삭제")
        end
      end
      Outcome.new(ok: true, errors: [])
    end

    private

    def ids_for(model, column)
      model.where.not(column => nil).pluck(column)
    end

    def delete_traccar_resources(logger)
      errors = []
      TRACCAR_RESOURCES.each do |path, model, column|
        ids = ids_for(model, column)
        deleted = 0
        ids.each do |id|
          request(:delete, "/api/#{path}/#{id}")
          deleted += 1
        rescue RuntimeError => e
          if e.message.end_with?("→ 404")
            deleted += 1 # 이미 없다
          else
            errors << "Traccar #{path}/#{id}: #{e.message}"
          end
        rescue *TraccarApiClient::RESCUED_ERRORS => e
          errors << "Traccar #{path}/#{id}: #{e.message}"
        end
        logger.call("Traccar #{path}: #{deleted}/#{ids.size}건 삭제")
      end
      errors
    end
  end
end
