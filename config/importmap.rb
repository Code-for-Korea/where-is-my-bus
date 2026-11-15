# Pin npm packages by running ./bin/importmap

pin "application"
pin "ga4"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# 관리자 정류장 폼의 좌표 선택 지도. stop_map_controller가 필요할 때 동적으로 불러온다.
pin "leaflet", to: "https://cdn.jsdelivr.net/npm/leaflet@1.9.4/+esm"
