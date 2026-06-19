class Trip < ApplicationRecord
  belongs_to :bus
  has_many :gps_logs, dependent: :destroy

  validates :started_at, presence: true

  def active?
    ended_at.nil?
  end

  def latest_gps
    gps_logs.order(recorded_at: :desc).first
  end
end
