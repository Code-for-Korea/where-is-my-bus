# frozen_string_literal: true

# Datalogger P0 설정 상수 — 관련 잡(Todo 7/8)과 중앙 관리.
#
# TRIP_AUTO_TERMINATE_AFTER: 마지막 GPS 수신 후 이 시간이 경과한 활성 trip을
# TripAutoTerminatorJob이 자동 종료한다. (docs/traccar-integration.md 로드맵 3단계)
TRIP_AUTO_TERMINATE_AFTER = 10.minutes
