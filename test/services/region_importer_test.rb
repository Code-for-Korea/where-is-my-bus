require "test_helper"
require "rake"

class RegionImporterTest < ActiveSupport::TestCase
  SAMPLE = Rails.root.join("test/fixtures/files/regions_sample.csv").to_s
  SAMPLE_ROWS = 9
  HEADER = "code,parent_code,level,kind,name,south,west,north,east".freeze

  def write_csv(*lines, header: HEADER)
    file = Tempfile.new([ "regions", ".csv" ])
    file.write([ header, *lines ].compact.join("\n") + "\n")
    file.close
    (@tempfiles ||= []) << file
    file.path
  end

  def assert_rejected(path, message)
    assert_no_difference "Region.count" do
      result = RegionImporter.call(path)
      assert_not result.success?
      assert result.errors.any? { |e| e.include?(message) }, "#{message.inspect} not in #{result.errors.inspect}"
    end
  end

  test "샘플을 적재하면 자식이 부모보다 앞에 있어도 부모가 이어진다" do
    result = nil
    assert_difference "Region.count", SAMPLE_ROWS do
      result = RegionImporter.call(SAMPLE)
    end

    assert result.success?
    assert_equal SAMPLE_ROWS, result.added
    assert_equal 0, result.unchanged
    assert_empty result.differences

    eup = Region.find_by!(code: "9011025000")
    assert_equal Region.find_by!(code: "9011000000"), eup.parent
    assert_equal Region.find_by!(code: "9100000000"), eup.parent.parent
    assert_equal [ 3, "읍면동", "청운동" ], [ eup.level, eup.kind, eup.name ]
    assert_equal [ "37.58", "126.96", "37.59", "126.975" ], [ eup.south, eup.west, eup.north, eup.east ].map { |v| v.to_s("F").sub(/0+\z/, "").chomp(".") }
    assert_nil Region.find_by!(code: "9100000000").parent
    assert_nil Region.find_by!(code: "9041111000").south
  end

  test "레벨을 건너뛴 세종형 행도 적재된다" do
    RegionImporter.call(SAMPLE)
    banggok = Region.find_by!(code: "9361025000")
    assert_equal 3, banggok.level
    assert_equal 1, banggok.parent.level
  end

  test "같은 파일을 다시 적재하면 추가 없이 변경 없음만 나온다" do
    RegionImporter.call(SAMPLE)
    result = nil
    assert_no_difference "Region.count" do
      result = RegionImporter.call(SAMPLE)
    end

    assert result.success?
    assert_equal 0, result.added
    assert_equal SAMPLE_ROWS, result.unchanged
    assert_empty result.differences
  end

  test "이미 있는 코드는 수정하지 않고 다른 필드를 보고하며 새 코드는 추가한다" do
    RegionImporter.call(SAMPLE)
    path = write_csv(
      "9100000000,,1,시도,다른이름특별시,37.000000,126.000000,38.000000,127.000000",
      "9011000000,9400000000,2,시군구,종로구,37.570000,126.950000,37.620000,127.020000",
      "9999000000,,1,시도,새시도,,,,"
    )

    result = nil
    assert_difference "Region.count", 1 do
      result = RegionImporter.call(path)
    end

    assert result.success?
    assert_equal 1, result.added
    assert_equal 0, result.unchanged
    assert_equal "시험특별시", Region.find_by!(code: "9100000000").name
    assert_nil Region.find_by!(code: "9100000000").south
    assert_equal "9100000000", Region.find_by!(code: "9011000000").parent.code

    diffs = result.differences
    assert_includes diffs, { code: "9100000000", field: :name, db: "시험특별시", source: "다른이름특별시" }
    assert diffs.any? { |d| d[:code] == "9100000000" && d[:field] == :south && d[:db].nil? && d[:source] == "37.000000" }
    assert_includes diffs, { code: "9011000000", field: :parent, db: "9100000000", source: "9400000000" }
  end

  test "bbox는 소수 여섯 자리 숫자로 비교한다" do
    RegionImporter.call(SAMPLE)
    path = write_csv("9011025000,9011000000,3,읍면동,청운동,37.58,126.96,37.59,126.9750000")
    result = RegionImporter.call(path)
    assert_equal 1, result.unchanged
    assert_empty result.differences
  end

  test "레벨과 종류 차이도 보고한다" do
    RegionImporter.call(SAMPLE)
    result = RegionImporter.call(write_csv("9100000000,,2,시군구,시험특별시,,,,"))
    assert_equal %i[level kind], result.differences.map { |d| d[:field] }
  end

  test "알 수 없는 상위 코드는 줄 번호와 함께 실패하고 아무것도 저장하지 않는다" do
    path = write_csv("9100000000,,1,시도,시험특별시,,,,", "9100000001,4100000099,2,시군구,고아,,,,")
    assert_rejected path, "3행: 상위 지역 코드 4100000099를 찾을 수 없습니다"
  end

  test "파일 안에서 코드가 중복되면 실패한다" do
    path = write_csv("9100000000,,1,시도,가,,,,", "9100000000,,1,시도,나,,,,")
    assert_rejected path, "3행: 코드 9100000000이(가) 2행과 중복됩니다"
  end

  test "상위 레벨이 낮지 않으면 실패한다" do
    path = write_csv("9100000000,,2,시군구,가,,,,", "9100000001,9100000000,2,시군구,나,,,,")
    assert_rejected path, "3행: 상위 지역의 레벨"
  end

  test "DB에 있는 상위 지역의 레벨도 검사한다" do
    path = write_csv("9100000001,4800000000,1,시도,나,,,,")
    assert_rejected path, "2행: 상위 지역의 레벨"
  end

  test "DB에 있는 상위 지역에 새 행을 붙일 수 있다" do
    result = RegionImporter.call(write_csv("4882010000,4882000000,3,읍면동,고성읍,,,,"))
    assert result.success?
    assert_equal regions(:goseong), Region.find_by!(code: "4882010000").parent
  end

  test "bbox 일부만 있으면 실패한다" do
    assert_rejected write_csv("9100000000,,1,시도,가,37.0,126.0,,"), "2행: 영역(남·서·북·동)은 모두 입력하거나 모두 비워야 합니다"
  end

  test "bbox가 숫자가 아니면 실패한다" do
    assert_rejected write_csv("9100000000,,1,시도,가,abc,126.0,38.0,127.0"), "2행: 영역 값이 숫자가 아닙니다"
  end

  test "bbox 순서나 범위가 틀리면 실패한다" do
    assert_rejected write_csv("9100000000,,1,시도,가,38.0,126.0,37.0,127.0"), "2행: 남쪽이 북쪽보다 클 수 없습니다"
    assert_rejected write_csv("9100000000,,1,시도,가,37.0,128.0,38.0,127.0"), "2행: 서쪽이 동쪽보다 클 수 없습니다"
    assert_rejected write_csv("9100000000,,1,시도,가,37.0,126.0,91.0,127.0"), "2행: 위도는 -90~90"
    assert_rejected write_csv("9100000000,,1,시도,가,37.0,126.0,38.0,181.0"), "2행: 경도는 -180~180"
  end

  test "필수 값이 비었거나 레벨이 정수가 아니면 실패한다" do
    assert_rejected write_csv(",,1,시도,가,,,,"), "2행: 코드가 비어 있습니다"
    assert_rejected write_csv("9100000000,,1,,가,,,,"), "2행: 종류가 비어 있습니다"
    assert_rejected write_csv("9100000000,,1,시도,,,,,"), "2행: 이름이 비어 있습니다"
    assert_rejected write_csv("9100000000,,0,시도,가,,,,"), "2행: 레벨은 1 이상의 정수여야 합니다"
    assert_rejected write_csv("9100000000,,x,시도,가,,,,"), "2행: 레벨은 1 이상의 정수여야 합니다"
  end

  test "헤더가 다르면 실패한다" do
    assert_rejected write_csv("9100000000,,1,시도,가,,,,", header: "code,name"), "헤더가 올바르지 않습니다"
  end

  test "파일이 없으면 실패한다" do
    assert_rejected "/nonexistent/regions.csv", "파일을 읽을 수 없습니다"
  end

  test "오류 목록은 100건으로 줄이고 나머지 건수를 알려 준다" do
    lines = (1..120).map { |i| "9#{format('%09d', i)},,x,시도,가,,,," }
    result = RegionImporter.call(write_csv(*lines))
    assert_equal 101, result.errors.size
    assert_equal "…외 20건", result.errors.last
  end

  test "UTF-8 BOM이 있어도 읽는다" do
    path = write_csv("9100000000,,1,시도,시험특별시,,,,", header: "﻿#{HEADER}")
    assert RegionImporter.call(path).success?
  end

  test "삽입된 행에는 시각이 채워지고 active는 true다" do
    before = Time.current.change(usec: 0)
    RegionImporter.call(SAMPLE)
    region = Region.find_by!(code: "9100000000")
    assert_operator region.created_at, :>=, before
    assert_operator region.updated_at, :>=, before
    assert_operator region.created_at, :<=, Time.current
    assert region.active
  end

  test "수천 행도 부모를 올바르게 이어 적재한다" do
    lines = [ "9900000000,,1,시도,큰시도,,,," ]
    sigungu = (1..60).map { |i| format("99%03d00000", i) }
    sigungu.each { |c| lines << "#{c},9900000000,2,시군구,시군구#{c},,,," }
    sigungu.each { |c| (1..99).each { |j| lines << "#{c[0, 5]}#{format('%03d', j)}00,#{c},3,읍면동,읍면동#{j},37.0,126.0,38.0,127.0" } }
    path = write_csv(*lines.shuffle)

    result = nil
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = RegionImporter.call(path)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    puts "\n[성능] #{lines.size}행 적재 #{elapsed.round(2)}초"

    assert result.success?, result.errors.first(3).inspect
    assert_equal lines.size, result.added
    assert_equal lines.size, Region.where("code LIKE '99%'").count
    assert_equal 0, Region.where("code LIKE '99%' AND level > 1 AND parent_id IS NULL").count
    assert_equal 60, Region.find_by!(code: "9900000000").children.count
    assert_equal 99, Region.find_by!(code: sigungu.first).children.count
  end
end

class RegionsImportTaskTest < ActiveSupport::TestCase
  SAMPLE = Rails.root.join("test/fixtures/files/regions_sample.csv").to_s

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("regions:import")
    Rake::Task["regions:import"].reenable
  end

  def run_task(*args)
    out, = capture_io { Rake::Task["regions:import"].invoke(*args) }
    out
  end

  test "요약을 출력한다" do
    assert_match "추가 9 / 변경 없음 0 / 원본과 다름 0", run_task(SAMPLE)
  end

  test "다시 실행하면 변경 없음으로 출력한다" do
    run_task(SAMPLE)
    Rake::Task["regions:import"].reenable
    assert_match "추가 0 / 변경 없음 9 / 원본과 다름 0", run_task(SAMPLE)
  end

  test "다른 값은 코드 필드 DB값 원본값 형식으로 출력한다" do
    run_task(SAMPLE)
    Rake::Task["regions:import"].reenable
    file = Tempfile.new([ "regions", ".csv" ])
    file.write("code,parent_code,level,kind,name,south,west,north,east\n9100000000,,1,시도,바뀐이름,,,,\n")
    file.close
    out = run_task(file.path)
    assert_match "원본과 다름 1", out
    assert_match "9100000000 name: 시험특별시 ↔ 바뀐이름", out
  end

  test "경로가 없으면 사용법을 알리고 종료한다" do
    err = capture_io { assert_raises(SystemExit) { Rake::Task["regions:import"].invoke } }.last
    assert_match "사용법", err
  end

  test "실패하면 오류를 출력하고 비정상 종료한다" do
    err = capture_io do
      error = assert_raises(SystemExit) { Rake::Task["regions:import"].invoke("/nonexistent.csv") }
      assert_not error.success?
    end.last
    assert_match "파일을 읽을 수 없습니다", err
  end
end
