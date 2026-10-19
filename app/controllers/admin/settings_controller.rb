module Admin
  class SettingsController < BaseController
    # API 키 필드는 선택한 제공자의 키를 편집한다. osm은 키가 필요 없다.
    # provider 전환 시 기존에 저장한 다른 제공자의 키는 유지된다.
    MAP_PROVIDERS = {
      "google" => { label: "Google Maps", key_setting: :google_maps_api_key, key_label: "Google Maps API 키" },
      "kakao" => { label: "Kakao Maps", key_setting: :kakao_maps_app_key, key_label: "Kakao Maps 앱 키 (JavaScript 키)" },
      "osm" => { label: "OpenStreetMap", key_setting: nil, key_label: nil }
    }.freeze

    def edit
      @provider = current_provider
      @api_key = api_key_for(@provider)
    end

    def update
      provider = params.dig(:settings, :map_provider)

      unless MAP_PROVIDERS.key?(provider)
        return redirect_to edit_admin_setting_path, alert: "알 수 없는 지도 제공자입니다."
      end

      Setting.store!(:map_provider, provider)
      key_setting = MAP_PROVIDERS[provider][:key_setting]
      Setting.store!(key_setting, params.dig(:settings, :api_key).presence) if key_setting

      redirect_to edit_admin_setting_path, notice: "설정을 저장했습니다."
    end

    private

    def current_provider
      Setting.fetch(:map_provider).then { |p| MAP_PROVIDERS.key?(p) ? p : "google" }
    end

    def api_key_for(provider)
      key_setting = MAP_PROVIDERS[provider][:key_setting]
      key_setting ? Setting.fetch(key_setting) : nil
    end
  end
end
