class GpsController < ActionController::API
  # GET|POST /gps
  # OsmAnd 프로토콜 호환 엔드포인트. 운전자 앱은 GET/form-urlencoded를 별도로 전송할 수 있다.
  # traccar_client_sdk는 커스텀 헤더를 보낼 수 없으므로 토큰 인증 없이 id 파라미터로 단말을 식별한다(P0).
  def create
    return head :not_implemented if numeric_timestamp?(params[:timestamp])

    PositionIngestor.call(params.to_unsafe_h, source: :osmand)
    head :ok
  end

  private

  def numeric_timestamp?(value)
    value.to_s.match?(/\A-?\d+(\.\d+)?\z/)
  end
end
