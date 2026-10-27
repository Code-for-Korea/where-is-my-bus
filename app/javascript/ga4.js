export function ga4Event(name, params = {}) {
  if (typeof gtag !== "undefined") gtag("event", name, params)
}

// Turbo Drive 이동은 전체 로드가 아니라서 head 스크립트가 다시 실행되지 않는다.
// 첫 로드와 이동 모두 turbo:load로 페이지뷰를 보낸다. 가상 경로는 body의 data-ga4-page-path.
document.addEventListener("turbo:load", () => {
  ga4Event("page_view", {
    page_path:     document.body.dataset.ga4PagePath || location.pathname,
    page_location: location.href,
    page_title:    document.title
  })
})
