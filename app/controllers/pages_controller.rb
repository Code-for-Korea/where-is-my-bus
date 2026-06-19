class PagesController < ApplicationController
  allow_unauthenticated_access

  def index
    @region           = Region.order(:id).first
    @first_stop       = @region&.first_active_stop
    @selector_regions = Region.includes(buses: { routes: :stops }).all
  end

  def about
    @selector_regions = Region.includes(buses: { routes: :stops }).all
    @regions          = Region.includes(:areas, buses: { routes: :stops }).all
  end
end
