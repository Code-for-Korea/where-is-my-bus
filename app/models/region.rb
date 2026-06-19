class Region < ApplicationRecord
  has_many :areas, dependent: :destroy
  has_many :buses, through: :areas

  validates :name, presence: true, uniqueness: true
  validates :slug, uniqueness: true, allow_nil: true,
                   format: { with: /\A[a-z0-9\-]+\z/ }, if: -> { slug.present? }

  default_scope { order(:position, :name) }

  def display_name
    I18n.locale == :ko ? name : (name_en.presence || name)
  end

  def first_active_stop
    buses.where(status: "active").order(:id).each do |bus|
      stop = bus.routes.order(:id).first&.stops&.first
      return stop if stop
    end
    nil
  end
end
