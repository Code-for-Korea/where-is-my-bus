import { Controller } from "@hotwired/stimulus"

// 지역(시·도) → 운행지역 → 노선 캐스케이딩 선택.
// 선택 가능한 노선이 정해지면 제출 버튼을 활성화한다.
export default class extends Controller {
  static targets = ["region", "area", "route", "submit"]
  static values = { areas: Array, routes: Array }

  connect() {
    this.updateSubmit()
  }

  regionChanged() {
    const regionId = this.regionTarget.value
    const areas = regionId
      ? this.areasValue.filter((a) => String(a.region_id) === regionId)
      : this.areasValue
    this.fill(this.areaTarget, areas, "운행지역 선택")
    this.fill(this.routeTarget, [], "노선 선택")
    this.updateSubmit()
  }

  areaChanged() {
    const areaId = this.areaTarget.value
    const routes = areaId
      ? this.routesValue.filter((r) => String(r.area_id) === areaId)
      : []
    this.fill(this.routeTarget, routes, "노선 선택")
    this.updateSubmit()
  }

  routeChanged() {
    this.updateSubmit()
  }

  fill(select, items, prompt) {
    select.innerHTML = ""
    select.appendChild(this.option("", prompt))
    items.forEach((i) => select.appendChild(this.option(i.id, i.name)))
    select.disabled = items.length === 0
  }

  option(value, text) {
    const o = document.createElement("option")
    o.value = value
    o.textContent = text
    return o
  }

  updateSubmit() {
    if (this.hasSubmitTarget) this.submitTarget.disabled = !this.routeTarget.value
  }
}
