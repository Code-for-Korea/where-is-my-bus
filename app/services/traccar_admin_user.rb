# Traccar 웹 화면에 로그인할 관리자 계정을 서비스 토큰으로 만든다.
# 운영은 web.registration을 꺼 두어 화면에서 가입할 수 없으므로, 서버에서 이 서비스(traccar:create_admin)로 만든다.
# Rails 동작에는 필요 없다(Rails는 서비스 토큰으로 Traccar를 부른다). 사람이 Traccar 관리 화면에 들어갈 때만 쓴다.
class TraccarAdminUser
  include TraccarApiClient

  class << self
    # 같은 이메일이 이미 있으면 만들지 않고(덮어쓰지 않는다) 성공으로 알린다. created가 true일 때만 새로 만든 것이다.
    def call(email:, password:, name: "admin")
      return Result.new(success: false, error: "이메일과 비밀번호가 필요합니다") if email.blank? || password.blank?

      existing = find_by_email(email)
      return Created.new(success: true, created: false, id: existing["id"]) if existing

      res = request(:post, "/api/users", { name: name, email: email, password: password, administrator: true })
      Created.new(success: true, created: true, id: JSON.parse(res.body)["id"])
    rescue *TraccarApiClient::RESCUED_ERRORS => e
      Rails.logger.error("[TraccarAdminUser] #{e.class} #{e.message}")
      Result.new(success: false, error: "Traccar 관리자 계정 생성 실패: #{e.message}")
    end

    private

    def find_by_email(email)
      JSON.parse(request(:get, "/api/users").body).find { |user| user["email"].to_s.casecmp?(email) }
    end
  end

  Created = Struct.new(:success, :created, :id, :error, keyword_init: true) do
    def failure? = !success
  end
end
