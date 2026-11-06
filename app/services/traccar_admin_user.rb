# Traccar 웹 화면에 로그인할 관리자 계정을 서비스 토큰으로 만든다.
# 운영은 web.registration을 꺼 두어 화면에서 가입할 수 없으므로, 서버에서 이 서비스(traccar:create_admin)로 만든다.
# Rails 동작에는 필요 없다(Rails는 서비스 토큰으로 Traccar를 부른다). 사람이 Traccar 관리 화면에 들어갈 때만 쓴다.
class TraccarAdminUser
  include TraccarApiClient

  class << self
    # 관리자 계정을 만든다. 같은 이메일이 있으면 Traccar가 거절하므로 실패로 돌아온다(덮어쓰지 않는다).
    # 먼저 있는지 알고 싶으면 exists?를 쓴다.
    def call(email:, password:, name: "admin")
      return Result.new(success: false, error: "이메일과 비밀번호가 필요합니다") if email.blank? || password.blank?

      request(:post, "/api/users", { name: name, email: email, password: password, administrator: true })
      Result.new(success: true)
    rescue *TraccarApiClient::RESCUED_ERRORS => e
      Rails.logger.error("[TraccarAdminUser] #{e.class} #{e.message}")
      Result.new(success: false, error: "Traccar 관리자 계정 생성 실패: #{e.message}")
    end

    # Traccar API에는 이메일로 찾는 방법이 없어 전체 사용자를 읽는다. 관리 화면 계정 수만큼이라 적다.
    # 연결 실패는 호출한 쪽에서 TraccarApiClient::RESCUED_ERRORS로 처리한다.
    def exists?(email)
      JSON.parse(request(:get, "/api/users").body).any? { |user| user["email"].to_s.casecmp?(email) }
    end
  end
end
