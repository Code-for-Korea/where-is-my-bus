namespace :regions do
  desc "지역 CSV를 적재한다(새 코드만 추가, 기존 코드는 수정하지 않고 차이만 보고). 예: bin/rails 'regions:import[경로]'"
  task :import, %i[path] => :environment do |_task, args|
    abort "사용법: bin/rails 'regions:import[CSV 경로]'" if args[:path].blank?

    result = RegionImporter.call(args[:path])
    abort result.errors.join("\n") unless result.success?

    puts "추가 #{result.added} / 변경 없음 #{result.unchanged} / 원본과 다름 #{result.differences.map { |d| d[:code] }.uniq.size}"
    max_lines = 50
    result.differences.first(max_lines).each do |d|
      puts "#{d[:code]} #{d[:field]}: #{d[:db].nil? ? "(없음)" : d[:db]} ↔ #{d[:source].nil? ? "(없음)" : d[:source]}"
    end
    puts "…외 #{result.differences.size - max_lines}건" if result.differences.size > max_lines
  end
end
