module Admin
  class BusesController < BaseController
    before_action :set_bus, only: %i[show edit update destroy regenerate_pin]

    def index
      @buses = Bus.includes(area: :region).all
      @buses = @buses.where(area_id: params[:area_id]) if params[:area_id].present?
    end

    def show
    end

    def new
      @bus = Bus.new(area_id: params[:area_id])
    end

    def create
      @bus = Bus.new(bus_params)
      if @bus.save
        redirect_to admin_bus_path(@bus), notice: "차량이 등록되었습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @bus.update(bus_params)
        redirect_to admin_bus_path(@bus), notice: "차량이 수정되었습니다."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @bus.destroy
      redirect_to admin_buses_path, notice: "차량이 삭제되었습니다.", status: :see_other
    end

    # PIN 유출 등으로 운영자가 즉시 무효화하고 싶을 때 — 재발급하면 옛 PIN으로는 register API가 더 이상 안 먹힘.
    def regenerate_pin
      @bus.regenerate_pin!
      redirect_to admin_bus_path(@bus), notice: "PIN이 재발급되었습니다. 운전자에게 새 PIN을 전달해주세요."
    end

    private

    def set_bus
      @bus = Bus.find(params[:id])
    end

    def bus_params
      params.require(:bus).permit(:area_id, :license_plate, :bus_number, :status)
    end
  end
end
