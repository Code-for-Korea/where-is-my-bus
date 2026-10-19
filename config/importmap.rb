# Pin npm packages by running ./bin/importmap

pin "application"
pin "ga4"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/map_providers", under: "map_providers"
pin "leaflet", to: "leaflet.esm.js" # @1.9.4 (OpenStreetMap 지도용, vendor 자체호스팅)
