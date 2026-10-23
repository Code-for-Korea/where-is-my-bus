import { Controller } from "@hotwired/stimulus"

// 5초마다 현재 상태(JSON)를 받아 문구와 노선 진행 바의 버스 아이콘을 갱신한다.
// 서버가 만든 문구는 textContent/DOM 노드로만 넣는다 (정류장 이름 등 입력값이 섞여 있다).
export default class extends Controller {
  static targets = ["small", "big", "others", "busMarker"]
  static values  = { url: String, interval: { type: Number, default: 5000 } }

  connect() {
    this.timer = setInterval(() => {
      if (!document.hidden) this.poll()
    }, this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async poll() {
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (!response.ok) return
      this.render(await response.json())
    } catch {
      // 네트워크가 잠깐 끊겨도 현재 표시를 유지하고 다음 주기에 다시 시도한다.
    }
  }

  render(data) {
    if (this.hasSmallTarget) this.smallTarget.textContent = data.small

    if (this.hasBigTarget) {
      const nodes = []
      data.big.forEach((line, index) => {
        if (index > 0) nodes.push(document.createElement("br"))
        nodes.push(document.createTextNode(line))
      })
      this.bigTarget.replaceChildren(...nodes)
    }

    if (this.hasOthersTarget) {
      this.othersTarget.replaceChildren(...data.others.map((text) => {
        const item = document.createElement("li")
        item.textContent = text
        return item
      }))
    }

    if (this.hasBusMarkerTarget) {
      this.busMarkerTarget.style.left = `${data.barPct}%`
      this.busMarkerTarget.classList.toggle("opacity-40", data.dim)
    }
  }
}
