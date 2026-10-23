import { Controller } from "@hotwired/stimulus"

// 일정 주기마다 서버가 렌더링한 HTML 조각을 받아와 이 요소의 내용을 교체한다.
// 폴링 주기는 5초 — 지금은 Cable 같은 푸시 없이 단순 폴링을 쓴다.
export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 5000 } }

  connect() {
    this.timer = setInterval(() => this.refresh(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async refresh() {
    if (document.hidden) return

    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "text/html" } })
      if (response.ok) this.element.innerHTML = await response.text()
    } catch (_error) {
      // 네트워크가 잠깐 끊겨도 다음 주기에 다시 시도한다.
    }
  }
}
