class MapController < ApplicationController
  allow_unauthenticated_access

  def show
    @route = Route.find_by(id: params[:id])
    return head :not_found unless @route

    @selections = RouteBusSelector.call(@route, nil, context: :map)
    @provider = Setting.fetch(:map_provider) || "google"
  end
end
