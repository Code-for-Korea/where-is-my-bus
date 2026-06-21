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
    # routes/stops 를 eager-load 해 버스별 N+1 쿼리를 제거. (min_by/first 는 로드된 컬렉션에서 동작)
    buses.where(status: "active").includes(routes: :stops).order(:id).each do |bus|
      stop = bus.routes.min_by(&:id)&.stops&.first
      return stop if stop
    end
    nil
  end
end
