class PagesController < ApplicationController
  allow_unauthenticated_access

  def index
    @region     = Region.order(:id).first
    @first_stop = @region&.first_active_stop
    load_selector_regions
  end

  def about
    # @regions 가 셀렉터에 필요한 buses/routes/stops 를 이미 eager-load 하므로 재사용한다.
    @regions          = Region.includes(:areas, buses: { routes: :stops }).all
    @selector_regions = @regions
  end
end
