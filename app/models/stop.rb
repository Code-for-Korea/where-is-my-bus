class Stop < ApplicationRecord
  belongs_to :route, counter_cache: true

  validates :name, presence: true
  validates :sequence, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :lat, :lng, presence: true

  default_scope { order(:sequence) }

  def first_stop?
    sequence == 1
  end

  def display_name
    I18n.locale == :ko ? name : (name_en.presence || name)
  end

  def coordinates?
    lat.present? && lng.present?
  end
end
