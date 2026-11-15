module Admin
  # 지역 목록(전체 지역 한 표 + 지역 필터·상태 필터·정류장 필터·검색·페이지)과 생성·수정·삭제. Traccar와 무관한 순수 DB 작업이다.
  class RegionsController < BaseController
    PER_PAGE = 50
    STATUSES = %w[active inactive].freeze

    def index
      @query = params[:q].to_s.strip
      @filter_region = Region.find_by(id: params[:region_id]) if params[:region_id].present?
      @with_stops = params[:with_stops] == "1"
      @status = params[:status] if STATUSES.include?(params[:status])

      scope = filtered_regions
      @total_count = scope.count
      @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
      @page = params[:page].to_i.clamp(1, @total_pages)
      @regions = scope.order(:level, :code).includes(parent: { parent: { parent: :parent } })
                      .offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
      load_row_stats
    end

    # 정류장 폼의 단계별 선택용. 상위 지역이 없으면 최상위 지역을 돌려준다.
    def children
      Region.find(params[:parent_id]) if params[:parent_id].present?
      regions = Region.active.where(parent_id: params[:parent_id].presence).ordered
                      .includes(parent: { parent: { parent: :parent } }).to_a
      with_children = Region.active.where(parent_id: regions.map(&:id)).distinct.pluck(:parent_id).to_set

      render json: regions.map { |region|
        region.slice(:id, :name, :level, :kind).merge(bounds: region.bounds, has_children: with_children.include?(region.id))
      }
    end

    def show
      @region = Region.find(params[:id])
      @child_count = @region.children.count
      @stop_count = @region.stops.count
    end

    def new
      parent = Region.find(params[:parent_id]) if params[:parent_id].present?
      @region = Region.new(parent: parent)
    end

    def create
      @region = Region.new(region_params)
      if @region.save
        redirect_to admin_region_path(@region), notice: "지역이 등록되었습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @region = Region.find(params[:id])
    end

    def update
      @region = Region.find(params[:id])
      if @region.update(region_params)
        redirect_to admin_region_path(@region), notice: "지역이 수정되었습니다."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      region = Region.find(params[:id])
      if region.destroy
        redirect_to admin_regions_path(region_id: region.parent_id), notice: "지역이 삭제되었습니다.", status: :see_other
      else
        alert = "삭제할 수 없습니다: #{region.errors.full_messages.to_sentence} 폐지된 지역은 삭제하지 않고 비활성으로 바꾸세요."
        redirect_to admin_region_path(region), alert: alert, status: :see_other
      end
    end

    private

    def region_params
      params.require(:region).permit(:code, :name, :level, :kind, :active, :parent_code, *Region::BOUNDS_ATTRIBUTES)
    end

    def filtered_regions
      scope = Region.all
      scope = scope.within(@filter_region) if @filter_region
      scope = scope.with_stops if @with_stops
      scope = scope.where(active: @status == "active") if @status
      if @query.present?
        scope = scope.where("name LIKE ?", "%#{Region.sanitize_sql_like(@query)}%")
      end
      scope
    end

    # 행마다 쿼리하지 않도록 정류장 수를 묶어서 센다.
    def load_row_stats
      ids = @regions.map(&:id)
      @stop_counts = Stop.where(region_id: ids).group(:region_id).count
    end
  end
end
