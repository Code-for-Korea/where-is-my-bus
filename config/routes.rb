Rails.application.routes.draw do
  # 인증
  resource  :session
  resource  :registration, only: %i[new create]
  resources :passwords, param: :token

  get "up" => "rails/health#show", as: :rails_health_check

  # Traccar 위치 포워딩 수신 (머신 간)
  namespace :integrations do
    post "traccar/register",    to: "traccar#register"
    get  "traccar/routes",      to: "traccar#routes"
    post "traccar/events",      to: "traccar_events#create"
    post "traccar/trips/start", to: "trips#start"
    post "traccar/trips/end",   to: "trips#finish"
  end

  # 관리자
  namespace :admin do
    root "dashboard#index"

    resources :routes do
      member { post :sync_group }
      resources :route_stops, only: %i[create destroy]
    end
    resources :stops do
      member { post :sync_geofence }
    end
    resources :buses do
      member { post :regenerate_pin }
      member { post :sync_device }
    end
    get "guides/bus_registration", to: "guides#bus_registration", as: :bus_registration_guide
  end

  # 승객 웹: 정류장 → (노선 선택) → 그 노선 버스의 위치
  root "pages#index"
  resources :stops, only: :show
  get "stops/:stop_id/routes/:route_id",       to: "arrivals#show",  as: :stop_route_arrivals
  get "stops/:stop_id/routes/:route_id/buses", to: "arrivals#buses", as: :stop_route_buses
end
