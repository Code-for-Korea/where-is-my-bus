module Admin
  class DashboardController < BaseController
    def index
      @counts = { routes: Route.count, stops: Stop.count, buses: Bus.count, active_trips: Trip.active.count }
      @active_trips = Trip.active.includes(:bus, :route).order(started_at: :desc)
      @recent_visits = StopVisit.includes(:stop, trip: %i[bus route]).latest_first.limit(10)
    end
  end
end
