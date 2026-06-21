module Admin
  class BusesController < BaseController
    before_action :set_bus, only: %i[show edit update destroy]

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

    private

    def set_bus
      @bus = Bus.find(params[:id])
    end

    def bus_params
      params.require(:bus).permit(:area_id, :license_plate, :bus_number, :pin, :status)
    end
  end
end
