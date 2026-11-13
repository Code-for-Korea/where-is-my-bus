import { Controller } from "@hotwired/stimulus"

// 지역 연쇄 선택(정류장 폼, 지역 목록 필터). 서버가 레벨마다 <select> 한 칸씩 그려 두고,
// 선택이 바뀌면 그보다 깊은 칸을 비운 뒤 하위 지역이 있으면 그 칸들을 불러와 채운다.
// 선택 결과는 hidden 입력칸에 쓰고, region-select:changed 이벤트로 알린다.
export default class extends Controller {
  static targets = ["container", "input", "status"]
  static values = {
    url: String  // 하위 지역 JSON 엔드포인트
  }

  connect() {
    this.requestId = 0
  }

  disconnect() {
    this.requestId++ // 늦게 도착한 응답은 버린다.
  }

  // 칸은 레벨마다 하나씩 항상 있다(data-level). 고른 칸보다 깊은 칸은 비우고, 고른 지역의 하위 지역으로 다시 채운다.
  choose(event) {
    const level = Number(event.target.dataset.level)
    this.selects().filter((select) => Number(select.dataset.level) > level).forEach((select) => this.clearSelect(select))
    const requestId = ++this.requestId // 이전 요청의 응답은 무시된다.
    this.showStatus("")

    // 가장 깊게 고른 칸의 지역이 선택 결과다. "선택"(빈 값)이면 더 얕은 칸으로 돌아간다.
    const chosen = this.selects().map((select) => select.selectedOptions[0]).filter((option) => option && option.value !== "").pop()
    const regionId = chosen ? Number(chosen.value) : null

    this.inputTarget.value = regionId === null ? "" : String(regionId)
    this.dispatch("changed", { detail: { regionId, bounds: this.boundsOf(chosen) } })

    if (chosen && chosen.dataset.hasChildren === "true") {
      this.loadChildren(chosen.value, Number(chosen.dataset.level), requestId)
    }
  }

  selects() {
    return Array.from(this.containerTarget.querySelectorAll("select"))
  }

  clearSelect(select) {
    select.replaceChildren(this.blankOption())
    select.disabled = true
  }

  blankOption() {
    const blank = document.createElement("option")
    blank.value = ""
    blank.textContent = "선택"
    return blank
  }

  async loadChildren(parentId, parentLevel, requestId) {
    let regions
    try {
      const response = await fetch(`${this.urlValue}?parent_id=${encodeURIComponent(parentId)}`, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      regions = await response.json()
    } catch (error) {
      if (requestId !== this.requestId) return
      console.error("하위 지역을 불러오지 못했습니다", error)
      this.showStatus("하위 지역을 불러오지 못했습니다. 지금 고른 지역으로 저장할 수 있습니다.")
      return
    }
    if (requestId !== this.requestId) return // 불러오는 사이 선택이 바뀌었다.
    if (!Array.isArray(regions)) return

    // 하위 지역을 레벨별로 나눠 해당 칸에 채운다. 세종처럼 레벨이 건너뛰면 건너뛴 칸은 비활성으로 남는다.
    this.selects()
      .filter((select) => Number(select.dataset.level) > parentLevel)
      .forEach((select) => {
        const level = Number(select.dataset.level)
        this.fillSelect(select, regions.filter((region) => region.level === level))
      })
  }

  fillSelect(select, regions) {
    select.replaceChildren(this.blankOption())
    regions.forEach((region) => {
      const option = document.createElement("option")
      option.value = String(region.id)
      option.textContent = region.name
      option.dataset.level = String(region.level)
      option.dataset.bounds = region.bounds ? JSON.stringify(region.bounds) : ""
      option.dataset.hasChildren = region.has_children ? "true" : "false"
      select.appendChild(option)
    })
    select.disabled = regions.length === 0
  }

  boundsOf(option) {
    if (!option || !option.dataset.bounds) return null
    try {
      return JSON.parse(option.dataset.bounds)
    } catch {
      return null
    }
  }

  showStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }
}
