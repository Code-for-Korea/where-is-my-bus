require "test_helper"

class DbSeedsTest < ActiveSupport::TestCase
  test "운영 환경에서는 시드가 데모 계정과 데이터를 만들지 않는다" do
    before = [ User.count, Stop.count, Route.count, Bus.count ]

    # minitest 6에는 minitest/mock이 없어서 production?만 잠깐 덮어쓴다.
    Rails.env.define_singleton_method(:production?) { true }
    original_allow = ENV.delete("ALLOW_PRODUCTION_SEED")
    begin
      # 문구를 다듬어도 깨지지 않도록 앞부분만 보고, 해제 방법(ALLOW_PRODUCTION_SEED=1)을 안내하는지는 확인한다.
      assert_output(/운영 환경에서는 시드를 실행하지 않.*ALLOW_PRODUCTION_SEED=1/) { load Rails.root.join("db/seeds.rb") }
    ensure
      Rails.env.singleton_class.send(:remove_method, :production?)
      ENV["ALLOW_PRODUCTION_SEED"] = original_allow if original_allow
    end

    assert_equal before, [ User.count, Stop.count, Route.count, Bus.count ]
  end
end
