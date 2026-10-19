# StopEventDetector가 arrive 이벤트를 생성한 직후 enqueue되어
# RouteSegmentStatAggregator로 구간 통계를 집계하는 비동기 잡.
# 이벤트가 보존 잡에 의해 이미 삭제됐으면 조용히 건너뛴다(집계는 이벤트 기반이므로).
class RouteSegmentStatAggregatorJob < ApplicationJob
  queue_as :default

  def perform(arrive_event_id:)
    arrive_event = StopEvent.find_by(id: arrive_event_id)
    return unless arrive_event

    RouteSegmentStatAggregator.call(arrive_event: arrive_event)
  end
end
