module Admin
  class BusesController < BaseController
    before_action :set_bus, only: %i[show edit update destroy regenerate_pin sync_device]

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
      success = false

      ActiveRecord::Base.transaction do
        raise ActiveRecord::Rollback unless @bus.save

        result = TraccarDeviceSync.call(@bus)
        if result.failure?
          @traccar_error = result.error
          raise ActiveRecord::Rollback
        end

        success = true
      end

      if success
        redirect_to admin_bus_path(@bus), notice: "차량이 등록되었습니다."
      else
        # @bus.save가 트랜잭션 내부에서 성공했다가 Traccar 실패로 롤백된 경우, DB는
        # 되돌아가도 @bus 객체의 persisted?/id는 그대로 남아 폼이 PATCH로 잘못
        # 렌더링된다 — 새 인스턴스로 교체해 "생성 폼" 상태를 복원한다.
        if @traccar_error
          @bus = Bus.new(bus_params)
          @bus.errors.add(:base, "Traccar 연동 실패: #{@traccar_error}")
        end
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      success = false

      ActiveRecord::Base.transaction do
        raise ActiveRecord::Rollback unless @bus.update(bus_params)

        result = TraccarDeviceSync.call(@bus)
        if result.failure?
          @traccar_error = result.error
          raise ActiveRecord::Rollback
        end

        success = true
      end

      if success
        redirect_to admin_bus_path(@bus), notice: "차량이 수정되었습니다."
      else
        @bus.errors.add(:base, "Traccar 연동 실패: #{@traccar_error}") if @traccar_error
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      # 정합성 정책: Traccar device 삭제가 성공해야만 Bus를 삭제한다.
      result = TraccarDeviceSync.destroy(@bus)
      if result.failure?
        redirect_to admin_bus_path(@bus), alert: "Traccar 연동 실패로 삭제할 수 없습니다: #{result.error}"
        return
      end

      @bus.destroy
      redirect_to admin_buses_path, notice: "차량이 삭제되었습니다.", status: :see_other
    end

    # PIN 유출 등으로 운영자가 즉시 무효화하고 싶을 때 — 재발급하면 옛 PIN으로는 register API가 더 이상 안 먹힘.
    def regenerate_pin
      @bus.regenerate_pin!
      redirect_to admin_bus_path(@bus), notice: "PIN이 재발급되었습니다. 운전자에게 새 PIN을 전달해주세요."
    end

    # 완전 롤백 정책 하에서는 동기화 실패한 채로 저장된 Bus가 생기지 않으므로, 이 액션은
    # "실패 재시도"가 아니라 Traccar 콘솔에서 수동으로 device를 지우는 등의 드리프트가 생겼을 때
    # 다시 맞추는 "재동기화" 용도로 남겨둔다.
    def sync_device
      result = TraccarDeviceSync.call(@bus)
      if result.failure?
        flash[:alert] = result.error
      else
        flash[:notice] = "device 동기화에 성공했습니다."
      end
      redirect_to admin_bus_path(@bus)
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
