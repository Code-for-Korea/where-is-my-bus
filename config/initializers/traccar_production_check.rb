# 운영 설정 오류는 부팅 실패로 드러낸다 (TraccarProductionCheck).
Rails.application.config.after_initialize do
  next unless Rails.env.production?
  next if ENV["SECRET_KEY_BASE_DUMMY"].present? # 이미지 빌드(assets:precompile)에는 운영 값이 없다

  problems = TraccarProductionCheck.problems
  raise "운영 Traccar 설정 오류: #{problems.join(', ')}" if problems.any?
end
