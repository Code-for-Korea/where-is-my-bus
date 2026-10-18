class RetentionJob < ApplicationJob
  BATCH_SIZE = 1_000

  def perform
    purge_position_history!
    purge_gps_logs!
    purge_stop_events!
    purge_route_segment_stats!
  end

  private

  def purge_position_history!
    cutoff = Rails.configuration.x.datalogger.position_history_retention.ago
    delete_in_batches(PositionHistory.where("recorded_at < ?", cutoff))
  end

  def purge_gps_logs!
    cutoff = Rails.configuration.x.datalogger.gps_log_retention.ago
    delete_in_batches(GpsLog.where("recorded_at < ?", cutoff))
  end

  def purge_stop_events!
    cutoff = Rails.configuration.x.datalogger.stop_event_retention.ago
    delete_in_batches(StopEvent.where("occurred_at < ?", cutoff))
  end

  def purge_route_segment_stats!
    cutoff = Rails.configuration.x.datalogger.route_segment_stat_retention.ago
    delete_in_batches(RouteSegmentStat.where("date < ?", cutoff.to_date))
  end

  def delete_in_batches(relation)
    loop do
      deleted = relation.limit(BATCH_SIZE).delete_all
      break if deleted.zero?
    end
  end
end
