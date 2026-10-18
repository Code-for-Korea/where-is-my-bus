class MapController < ApplicationController
  allow_unauthenticated_access

  def show
    @route = Route.find_by(id: params[:id])
    return head :not_found unless @route

    @selections = RouteBusSelector.call(@route, nil, context: :map)
    @provider = ENV.fetch("MAP_PROVIDER", "google").downcase
  end
end
