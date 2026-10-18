class GpsController < ActionController::API
  before_action :authenticate_ingest!

  # GET|POST /gps
  # OsmAnd 프로토콜 호환 엔드포인트. 운전자 앱은 GET/form-urlencoded를 별도로 전송할 수 있다.
  def create
    return head :not_implemented if numeric_timestamp?(params[:timestamp])

    PositionIngestor.call(params.to_unsafe_h, source: :osmand)
    head :ok
  end

  private

  def numeric_timestamp?(value)
    value.to_s.match?(/\A-?\d+(\.\d+)?\z/)
  end

  def authenticate_ingest!
    provided = request.headers["X-Ingest-Token"].to_s
    expected = ingest_token
    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    head :unauthorized
  end

  def ingest_token
    Rails.application.credentials.dig(:traccar, :ingest_token) ||
      ENV["TRACCAR_INGEST_TOKEN"] ||
      (Rails.env.local? ? "dev-traccar-token" : nil)
  end
end
