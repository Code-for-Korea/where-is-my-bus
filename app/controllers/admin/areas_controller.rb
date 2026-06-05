module Admin
  class AreasController < BaseController
    before_action :set_area, only: %i[show edit update destroy]

    def index
      @areas = Area.includes(:region).all
      @areas = @areas.where(region_id: params[:region_id]) if params[:region_id].present?
    end

    def show
    end

    def new
      @area = Area.new(region_id: params[:region_id])
    end

    def create
      @area = Area.new(area_params)
      if @area.save
        redirect_to admin_area_path(@area), notice: "운행지역이 등록되었습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @area.update(area_params)
        redirect_to admin_area_path(@area), notice: "운행지역이 수정되었습니다."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @area.destroy
      redirect_to admin_areas_path, notice: "운행지역이 삭제되었습니다.", status: :see_other
    end

    private

    def set_area
      @area = Area.find(params[:id])
    end

    def area_params
      params.require(:area).permit(:region_id, :name, :position)
    end
  end
end
