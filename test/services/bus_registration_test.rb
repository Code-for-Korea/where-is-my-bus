require "test_helper"

class BusRegistrationTest < ActiveSupport::TestCase
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup do
    TraccarDeviceSync.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
  end

  test "create saves the bus and creates its Traccar device with the generated unique id" do
    create = stub_request(:post, "http://traccar.test/api/devices")
      .with { |req| JSON.parse(req.body).values_at("name") == [ "경남70가0001" ] && JSON.parse(req.body)["uniqueId"].match?(/\A\h{12}\z/) }
      .to_return(status: 200, body: { id: 66 }.to_json, headers: JSON_HEADERS)

    result = BusRegistration.create(license_plate: "경남70가0001")

    assert result.success?
    assert_equal 66, result.record.reload.traccar_device_id
    assert_requested create
  end

  test "create rolls back the bus when Traccar fails" do
    stub_request(:post, "http://traccar.test/api/devices").to_return(status: 500, body: "boom")

    assert_no_difference -> { Bus.count } do
      result = BusRegistration.create(license_plate: "경남70가0001")

      assert result.failure?
      assert result.record.new_record?
    end
  end

  test "create rejects a duplicate license plate without calling Traccar" do
    result = BusRegistration.create(license_plate: buses(:one).license_plate)

    assert result.failure?
    assert_not_requested :post, "http://traccar.test/api/devices"
  end

  test "destroy leaves the Traccar device alone when the bus has trips" do
    result = BusRegistration.destroy(buses(:one))

    assert result.failure?
    assert Bus.exists?(buses(:one).id)
    assert_not_requested :delete, %r{traccar.test/api/devices}
  end

  test "destroy removes a bus without trips and deletes its Traccar device" do
    bus = Bus.create!(license_plate: "경남70가0002", traccar_device_id: 777)
    delete = stub_request(:delete, "http://traccar.test/api/devices/777").to_return(status: 204, body: "")

    result = BusRegistration.destroy(bus)

    assert result.success?
    assert_not Bus.exists?(bus.id)
    assert_requested delete
  end
end
