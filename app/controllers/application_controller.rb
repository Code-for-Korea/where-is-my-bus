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

  def set_locale
    requested = params[:locale]&.to_sym
    I18n.locale = I18n.available_locales.include?(requested) ? requested : I18n.default_locale
  end

  def default_url_options
    { locale: I18n.locale == I18n.default_locale ? nil : I18n.locale }
  end
end
