namespace :ops do
  desc "로그인 계정(User, Session)만 남기고 운영 데이터를 모두 지운다(방문·운행·차량·정류장·노선 + Traccar 자원). 확인 없이는 지울 건수만 보여 준다. 실행: OPS_RESET_CONFIRM=reset bin/rails ops:reset_data"
  task reset_data: :environment do
    puts "지울 데이터 (남기는 것: User #{User.count}명, Session #{Session.count}개)"
    OperationalDataReset.counts.each { |name, count| puts "  #{name}: #{count}" }
    puts "대상 Traccar: #{ENV["TRACCAR_API_BASE_URL"].presence || "(credentials)"}"

    unless ENV["OPS_RESET_CONFIRM"] == "reset"
      abort "\n지우지 않았습니다. 백업을 확인한 뒤 OPS_RESET_CONFIRM=reset 을 붙여 다시 실행하세요(docs/deployment.md \"운영 데이터 초기화\")."
    end

    if Trip.where(ended_at: nil).exists?
      abort "\n진행 중인 운행이 있습니다. 운전자가 종료하거나 정리한 뒤 다시 실행하세요."
    end

    outcome = OperationalDataReset.call(logger: ->(line) { puts line })
    unless outcome.success?
      puts "\n실패 #{outcome.errors.size}건 (Rails 데이터는 지우지 않았습니다. 다시 실행해도 안전합니다):"
      outcome.errors.each { |line| puts "  - #{line}" }
      abort
    end
    puts "완료. User #{User.count}명, Session #{Session.count}개는 그대로입니다."
  end
end
