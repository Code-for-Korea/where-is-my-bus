Rails.application.routes.draw do
  # 인증
  resource  :session
  resource  :registration, only: %i[new create]
  resources :passwords, param: :token

  get "up" => "rails/health#show", as: :rails_health_check

  # Traccar 위치 포워딩 수신 (머신 간)
  namespace :integrations do
    post "traccar/register",  to: "traccar#register"
    post "traccar/positions", to: "traccar#positions"
    get  "traccar/routes",    to: "traccar#routes"
  end

  # 관리자
  namespace :admin do
    root "dashboard#index"

    resources :regions
    resources :areas
    resources :routes do
      member { post :sync_group }
      resources :route_buses, only: %i[create destroy], controller: "route_buses"
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

  # 승객 웹 (i18n 지원)
  scope "(:locale)", locale: /ko|en/ do
    root "pages#index"
    get "/about", to: "pages#about"

    get "/r/:region_slug/:stop_id",         to: "stops#show",    as: :stop_arrival
    get "/r/:region_slug/:stop_id/detail",  to: "stops#detail",  as: :stop_detail
    get "/r/:region_slug/:stop_id/arrival", to: "stops#arrival", as: :stop_arrival_json
    post "/r/:region_slug/:stop_id/like",   to: "stops#like",    as: :stop_like

    if Rails.env.development?
      post "/r/:region_slug/:stop_id/debug_bus", to: "stops#debug_bus", as: :stop_debug_bus
    end
  end
end
