require "test_helper"

class Demo::SeedTest < ActiveSupport::TestCase
  test "db/seeds.rb는 아무것도 만들지 않는다 (운영의 db:prepare가 데이터를 만들지 않는다)" do
    before = counts

    load Rails.root.join("db/seeds.rb")

    assert_equal before, counts
  end

  test "운영 환경에서는 데모 데이터를 만들지 않고 종료한다" do
    before = counts

    # minitest 6에는 minitest/mock이 없어서 production?만 잠깐 덮어쓴다.
    Rails.env.define_singleton_method(:production?) { true }
    begin
      assert_raises(SystemExit) { capture_io { Demo::Seed.new.run } }
    ensure
      Rails.env.singleton_class.send(:remove_method, :production?)
    end

    assert_equal before, counts
  end

  private

  def counts
    [ User.count, Stop.count, Route.count, Bus.count ]
  end
end
