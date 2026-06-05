Rails.application.routes.draw do
  resource :session
  resource :registration, only: %i[new create]
  resources :passwords, param: :token
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :admin do
    root "dashboard#index"

    resources :regions
    resources :areas
    resources :routes
    resources :stops
    resources :buses
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # 시민용 서비스 (공개)
  get "service",        to: "buses#index",  as: :service
  get "service/about",  to: "buses#about",  as: :service_about
  get "service/select", to: "buses#select", as: :service_select
  get "service/go",     to: "buses#go",     as: :service_go

  resources :routes, only: :show do
    member do
      get  :stops
      post :like
    end
  end

  # Defines the root path route ("/")
  root "home#index"
end
