module Admin
  class RegionsController < BaseController
    before_action :set_region, only: %i[show edit update destroy]

    def index
      @regions = Region.all
    end

    def show
    end

    def new
      @region = Region.new
    end

    def create
      @region = Region.new(region_params)
      if @region.save
        redirect_to admin_region_path(@region), notice: "시·도가 등록되었습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @region.update(region_params)
        redirect_to admin_region_path(@region), notice: "시·도가 수정되었습니다."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @region.destroy
      redirect_to admin_regions_path, notice: "시·도가 삭제되었습니다.", status: :see_other
    end

    private

    def set_region
      @region = Region.find(params[:id])
    end

    def region_params
      params.require(:region).permit(:name, :position)
    end
  end
end
