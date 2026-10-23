module Admin
  class BusesController < BaseController
    before_action :set_bus, only: %i[show edit update destroy regenerate_pin sync_device]

    def index
      @buses = Bus.ordered.includes(active_trip: :route)
    end

    def show
    end

    def new
      @bus = Bus.new
    end

    def create
      result = BusRegistration.create(bus_params)
      return redirect_to admin_bus_path(result.record), notice: "차량이 등록되었습니다." if result.success?

      @bus = result.record
      render_failure :new, result
    end

    def edit
    end

    def update
      result = BusRegistration.update(@bus, bus_params)
      return redirect_to admin_bus_path(@bus), notice: "차량이 수정되었습니다." if result.success?

      render_failure :edit, result
    end

    def destroy
      result = BusRegistration.destroy(@bus)
      if result.success?
        redirect_to admin_buses_path, notice: "차량이 삭제되었습니다.", status: :see_other
      else
        redirect_to admin_bus_path(@bus), alert: "삭제할 수 없습니다: #{result.error}", status: :see_other
      end
    end

    # PIN 유출 등으로 운영자가 즉시 무효화하고 싶을 때 — 재발급하면 옛 PIN으로는 register API가 더 이상 안 먹힘.
    def regenerate_pin
      @bus.regenerate_pin!
      redirect_to admin_bus_path(@bus), notice: "PIN이 재발급되었습니다. 운전자에게 새 PIN을 전달해주세요."
    end

    # 드리프트(Traccar 콘솔에서 device를 수동 삭제 등) 복구용 재동기화.
    def sync_device
      result = BusRegistration.update(@bus, {})
      if result.success?
        redirect_to admin_bus_path(@bus), notice: "device 동기화에 성공했습니다."
      else
        redirect_to admin_bus_path(@bus), alert: result.error
      end
    end

    private

    def set_bus
      @bus = Bus.find(params[:id])
    end

    def bus_params
      params.require(:bus).permit(:license_plate, :bus_number)
    end
  end
end
