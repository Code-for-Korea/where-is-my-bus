import { Controller } from "@hotwired/stimulus"
import { ga4Event } from "ga4"

// 5초마다 현재 상태(JSON)를 받아 문구와 노선 진행 바의 버스 아이콘을 갱신한다.
// 서버가 만든 문구는 textContent/DOM 노드로만 넣는다 (정류장 이름 등 입력값이 섞여 있다).
export default class extends Controller {
  static targets = ["small", "big", "others", "busMarker"]
  static values  = {
    url: String, interval: { type: Number, default: 5000 }, glide: Object,
    stopName: String, routeName: String, status: String
  }

  connect() {
    // 화면을 열 때의 상태(arriving/approaching/passed/unknown/no_bus)를 한 번만 보낸다. 5초 폴링마다 보내지 않는다.
    ga4Event("arrival_status", { status: this.statusValue, stop_name: this.stopNameValue, bus_number: this.routeNameValue })
    if (this.hasGlideValue) this.glideMarker(this.glideValue)
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
      this.busMarkerTarget.classList.toggle("opacity-40", data.dim)
      if (data.glide) this.glideMarker(data.glide)
      else this.stepMarker(data.barPct)
    }
  }

  // 평소: 서버가 준 단계 위치로 0.5초 이동(클래스의 transition).
  stepMarker(pct) {
    const marker = this.busMarkerTarget
    marker.style.transition = ""
    marker.style.left = `${pct}%`
  }

  // 마지막 구간: 지금 위치에서 목표(to)까지 남은 ETA 동안 일정한 속도로 이동. 폴링마다 남은 시간으로 다시 맞춘다.
  glideMarker({ seconds, to }) {
    const marker = this.busMarkerTarget
    const current = (marker.offsetLeft / marker.offsetParent.offsetWidth) * 100 // 이동 중이면 지금 위치
    marker.style.transition = "none"
    marker.style.left = `${Math.min(current, to)}%`
    marker.getBoundingClientRect() // 위 값을 먼저 적용해 이동을 새로 시작한다
    marker.style.transition = `left ${Math.max(seconds, 1)}s linear`
    marker.style.left = `${to}%`
  }
}
