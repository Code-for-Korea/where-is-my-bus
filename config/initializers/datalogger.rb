# frozen_string_literal: true

# Datalogger P0 설정 상수 — 관련 잡(Todo 7/8)과 중앙 관리.
#
# TRIP_AUTO_TERMINATE_AFTER: 마지막 GPS 수신 후 이 시간이 경과한 활성 trip을
# TripAutoTerminatorJob이 자동 종료한다. (docs/traccar-integration.md 로드맵 3단계)
TRIP_AUTO_TERMINATE_AFTER = ENV.fetch("TRIP_AUTO_TERMINATE_AFTER", 10.minutes.to_i).to_i.seconds

POSITION_HISTORY_RETENTION     = ENV.fetch("POSITION_HISTORY_RETENTION", 24.hours.to_i).to_i.seconds
GPS_LOG_RETENTION              = ENV.fetch("GPS_LOG_RETENTION", 24.hours.to_i).to_i.seconds
STOP_EVENT_RETENTION           = ENV.fetch("STOP_EVENT_RETENTION", 7.days.to_i).to_i.seconds
ROUTE_SEGMENT_STAT_RETENTION   = ENV.fetch("ROUTE_SEGMENT_STAT_RETENTION", 90.days.to_i).to_i.seconds

Rails.configuration.x.datalogger ||= ActiveSupport::OrderedOptions.new
Rails.configuration.x.datalogger.trip_auto_terminate_after   = TRIP_AUTO_TERMINATE_AFTER
Rails.configuration.x.datalogger.position_history_retention  = POSITION_HISTORY_RETENTION
Rails.configuration.x.datalogger.gps_log_retention           = GPS_LOG_RETENTION
Rails.configuration.x.datalogger.stop_event_retention        = STOP_EVENT_RETENTION
Rails.configuration.x.datalogger.route_segment_stat_retention = ROUTE_SEGMENT_STAT_RETENTION
