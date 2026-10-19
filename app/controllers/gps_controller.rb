class GpsController < ActionController::API
  # GET|POST /gps
  # OsmAnd 프로토콜 호환 엔드포인트. 운전자 앱은 GET/form-urlencoded를 별도로 전송할 수 있다.
  # traccar_client_sdk는 커스텀 헤더를 보낼 수 없으므로 토큰 인증 없이 id 파라미터로 단말을 식별한다(P0).
  # timestamp는 ISO8601만 지원한다. 숫자 epoch timestamp는 501로 거부하며(의도적 차단),
  # SDK의 epoch 초 직접 연동은 후속 작업(docs/osmand-request-samples.md §4.3 참고).
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
