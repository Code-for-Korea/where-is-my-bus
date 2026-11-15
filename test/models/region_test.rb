require "test_helper"

class RegionTest < ActiveSupport::TestCase
  def build_region(**attrs)
    Region.new({ code: "9900000000", level: 1, kind: "시도", name: "새지역" }.merge(attrs))
  end

  test "requires code, name, kind and a positive integer level" do
    assert build_region.valid?
    %i[code name kind level].each do |attr|
      region = build_region(attr => nil)
      assert_not region.valid?, "#{attr} should be required"
      assert region.errors.of_kind?(attr, :blank) || region.errors.of_kind?(attr, :not_a_number)
    end
    assert_not build_region(level: 0).valid?
    assert_not build_region(level: 1.5).valid?
  end

  test "code must be unique" do
    region = build_region(code: regions(:goseong).code)
    assert_not region.valid?
    assert region.errors.of_kind?(:code, :taken)
  end

  test "bounding box must be all present or all blank" do
    assert build_region(south: 34, west: 128, north: 35, east: 129).valid?
    assert_not build_region(south: 34, west: 128).valid?
    assert_not build_region(south: 34, west: 128, north: 35).valid?
  end

  test "bounding box must be ordered and within coordinate ranges" do
    assert_not build_region(south: 36, west: 128, north: 35, east: 129).valid?
    assert_not build_region(south: 34, west: 130, north: 35, east: 129).valid?
    assert_not build_region(south: -91, west: 128, north: 35, east: 129).valid?
    assert_not build_region(south: 34, west: 128, north: 91, east: 129).valid?
    assert_not build_region(south: 34, west: -181, north: 35, east: 129).valid?
    assert_not build_region(south: 34, west: 128, north: 35, east: 181).valid?
  end

  test "parent level must be lower than the child level" do
    assert_not build_region(parent: regions(:goseong), level: 2).valid?
    assert_not build_region(parent: regions(:ulleung_eup), level: 2).valid?
    assert build_region(parent: regions(:goseong), level: 3).valid?
  end

  test "a child may skip levels below its parent" do
    assert regions(:bangok).valid?
    assert build_region(parent: regions(:sejong), level: 4).valid?
  end

  test "parent_code reads the parent's code" do
    assert_equal "4794000000", regions(:ulleung_eup).parent_code
    assert_nil regions(:gyeongbuk).parent_code
  end

  test "parent_code= resolves the parent by code" do
    region = build_region(level: 3)
    region.parent_code = regions(:goseong).code
    assert_equal regions(:goseong), region.parent
    assert region.valid?
    assert_equal regions(:goseong).code, region.parent_code
  end

  test "blank parent_code clears the parent" do
    region = regions(:goseong)
    region.parent_code = ""
    assert_nil region.parent
    assert region.valid?
  end

  test "unknown parent_code is a validation error" do
    region = build_region(level: 3, parent_code: "0000000000")
    assert_not region.valid?
    assert region.errors.of_kind?(:parent_code, :invalid)
    assert_match "해당하는 지역이 없습니다", region.errors[:parent_code].first
    region.parent_code = regions(:goseong).code
    assert region.valid?
  end

  test "level change must stay lower than every child's level" do
    region = regions(:sejong)
    region.level = 3
    assert_not region.valid?
    assert region.errors.of_kind?(:level, :invalid)
    region.level = 2
    assert region.valid?
    regions(:ulleung).level = 3
    assert_not regions(:ulleung).valid?
  end

  test "level guard ignores new records" do
    assert build_region(level: 5).valid?
  end

  test "a region cannot be moved under its own descendant" do
    region = regions(:gyeongbuk)
    region.parent_code = regions(:ulleung_eup).code
    assert_not region.valid?
    assert region.errors[:parent].any?
  end

  test "bounds uses own bounding box as floats" do
    assert_equal [ [ 34.8, 128.1 ], [ 35.1, 128.5 ] ], regions(:goseong).bounds
  end

  test "own_bounds ignores ancestors" do
    assert_equal [ [ 34.8, 128.1 ], [ 35.1, 128.5 ] ], regions(:goseong).own_bounds
    assert_nil regions(:ulleung_eup).own_bounds
  end

  test "bounds falls back to the nearest ancestor with a bounding box" do
    assert_equal regions(:ulleung).bounds, regions(:ulleung_eup).bounds
  end

  test "bounds is nil when no ancestor has a bounding box" do
    assert_nil regions(:gyeonggi).bounds
    assert_nil regions(:pajang).bounds
    assert_nil regions(:bangok).bounds
  end

  test "full_name joins ancestor names in order" do
    assert_equal "경상북도 울릉군 울릉읍", regions(:ulleung_eup).full_name
    assert_equal "경기도 수원시 장안구 파장동", regions(:pajang).full_name
    assert_equal "세종특별자치시", regions(:sejong).full_name
  end

  test "scopes" do
    assert_includes Region.roots, regions(:gyeongnam)
    assert_not_includes Region.roots, regions(:goseong)
    assert_includes Region.active, regions(:goseong)
    assert_not_includes Region.active, regions(:abolished)
    assert_equal [ 1, 1, 1, 1 ], Region.ordered.first(4).map(&:level)
    assert_equal %w[경기도 경상남도 경상북도 세종특별자치시], Region.ordered.first(4).map(&:name)
  end

  test "cannot be destroyed while it has children" do
    region = regions(:ulleung)
    assert_no_difference "Region.count" do
      assert_not region.destroy
    end
    assert region.errors.of_kind?(:base, :'restrict_dependent_destroy.has_many')
  end

  test "cannot be destroyed while it has stops" do
    region = regions(:ulleung_eup)
    stops(:terminal).update_columns(region_id: region.id)
    assert_no_difference "Region.count" do
      assert_not region.destroy
    end
    assert region.errors.of_kind?(:base, :'restrict_dependent_destroy.has_many')
  end

  test "a leaf region without stops can be destroyed" do
    assert_difference "Region.count", -1 do
      assert regions(:bangok).destroy
    end
  end

  test "country_bounds is the union of the active root regions' bounds" do
    regions(:gyeongnam).update!(south: 34.5, west: 127.5, north: 35.5, east: 129.0)
    regions(:gyeongbuk).update!(south: 35.5, west: 128.0, north: 38.0, east: 131.5)

    assert_equal [ [ 34.5, 127.5 ], [ 38.0, 131.5 ] ], Region.country_bounds
  end

  test "country_bounds is nil when no root region has bounds" do
    assert_nil Region.country_bounds
  end

  test "country_bounds ignores inactive roots" do
    regions(:gyeongnam).update!(south: 34.5, west: 127.5, north: 35.5, east: 129.0)
    regions(:gyeongbuk).update!(south: 35.5, west: 128.0, north: 38.0, east: 131.5, active: false)

    assert_equal [ [ 34.5, 127.5 ], [ 35.5, 129.0 ] ], Region.country_bounds
  end
end
