class StopVisit < ApplicationRecord
  belongs_to :trip
  belongs_to :stop

  validates :entered_at, presence: true
  validates :entered_event_id, uniqueness: true, allow_nil: true
  validates :exited_event_id, uniqueness: true, allow_nil: true

  scope :open, -> { where(exited_at: nil) }
  scope :latest_first, -> { order(entered_at: :desc) }

  # exited_at이 비어 있으면 버스가 아직 그 정류장 Geofence 안에 있다.
  def open?
    exited_at.nil?
  end
end
