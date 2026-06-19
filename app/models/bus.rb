class Bus < ApplicationRecord
  belongs_to :area
  has_many :routes,    dependent: :destroy
  has_many :trips,     dependent: :destroy
  has_many :pin_codes, dependent: :destroy

  enum :status, { active: "active", inactive: "inactive", deleted: "deleted" }

  validates :license_plate, presence: true, uniqueness: { scope: :area_id }
  validates :pin,           presence: true, format: { with: /\A\d{4,6}\z/, message: "은 4~6자리 숫자여야 합니다" }

  default_scope { order(:license_plate) }

  def region
    area.region
  end

  def display_number
    return license_plate unless bus_number.present?
    I18n.locale == :ko ? bus_number : bus_number.gsub("번", "").strip
  end
end
