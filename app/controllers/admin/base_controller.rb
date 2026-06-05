module Admin
  # 모든 관리자 컨트롤러의 베이스.
  # 인증(require_authentication)은 ApplicationController에서 전역 적용되고,
  # 여기서는 운영자(operator) 권한을 추가로 요구한다.
  class BaseController < ApplicationController
    layout "admin"

    before_action :require_operator

    private

    def require_operator
      return if Current.user&.operator?

      redirect_to root_path, alert: "운영자만 접근할 수 있습니다."
    end
  end
end
