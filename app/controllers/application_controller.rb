class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_locale

  private

  def no_turbo_cache
    response.set_header("Turbo-Cache-Control", "no-cache")
  end

  # 버스 선택 시트(_bus_selector_sheet)용 지역 트리. 여러 화면에서 공통 사용.
  def load_selector_regions
    @selector_regions = Region.includes(buses: { routes: :stops }).all
  end

  def set_locale
    requested = params[:locale]&.to_sym
    I18n.locale = I18n.available_locales.include?(requested) ? requested : I18n.default_locale
  end

  def default_url_options
    { locale: I18n.locale == I18n.default_locale ? nil : I18n.locale }
  end
end
