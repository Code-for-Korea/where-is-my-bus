# 노선 생성/수정/삭제 + Traccar 기기 그룹 동기화.
class RouteRegistration < TraccarRegistration
  manages Route, with: TraccarGroupSync
end
