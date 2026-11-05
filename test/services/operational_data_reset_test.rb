require "test_helper"

class OperationalDataResetTest < ActiveSupport::TestCase
  setup do
    OperationalDataReset.stub_credentials(base_url: "http://traccar.test", token: "t")
  end

  teardown do
    OperationalDataReset.instance_variable_set(:@stubbed, nil)
  end

  def stub_all_deletes(status: 204)
    stub_request(:delete, %r{http://traccar.test/api/(devices|geofences|groups)/\d+}).to_return(status: status)
  end

  test "keeps users and sessions and removes operational data" do
    stub_all_deletes
    users_before = User.count

    outcome = OperationalDataReset.call

    assert outcome.success?
    assert_equal users_before, User.count
    [ StopVisit, Trip, RouteStop, Bus, Stop, Route ].each { |model| assert_equal 0, model.count, model.name }
  end

  test "deletes the traccar resources Rails knows about" do
    stub_all_deletes
    device_ids = Bus.pluck(:traccar_device_id).compact
    refute_empty device_ids

    OperationalDataReset.call

    device_ids.each { |id| assert_requested :delete, "http://traccar.test/api/devices/#{id}" }
  end

  test "treats already-missing traccar resources as deleted" do
    stub_all_deletes(status: 404)

    assert OperationalDataReset.call.success?
    assert_equal 0, Route.count
  end

  test "leaves rails data untouched when a traccar delete fails" do
    stub_all_deletes(status: 500)
    buses = Bus.count

    outcome = OperationalDataReset.call

    refute outcome.success?
    assert_equal buses, Bus.count
    assert_operator Route.count, :>, 0
  end
end
