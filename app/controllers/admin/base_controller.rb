module Admin
  # 모든 관리자 컨트롤러의 베이스.
  # 인증(require_authentication)은 ApplicationController에서 전역 적용되고,
  # 여기서는 운영자(operator) 권한을 추가로 요구한다.
  class BaseController < ApplicationController
    layout "admin"

    before_action :require_operator

    private

    # 등록 서비스(TraccarRegistration) 실패를 폼의 오류로 보여준다.
    # 검증 오류는 레코드에 이미 담겨 있고, Traccar 실패는 base 오류로 추가한다.
    def render_failure(template, result)
      result.record.errors.add(:base, result.error) if result.record.errors.empty?
      render template, status: :unprocessable_entity
    end

    def require_operator
      return if Current.user&.operator?

      redirect_to root_path, alert: "운영자만 접근할 수 있습니다."
    end
  end
end
