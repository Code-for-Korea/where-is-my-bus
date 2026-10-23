import { Controller } from "@hotwired/stimulus"

// 입력한 글자가 들어 있는 항목만 보여주는 목록 필터.
export default class extends Controller {
  static targets = ["item", "empty"]

  apply(event) {
    const query = event.target.value.trim().toLowerCase()
    let visible = 0

    this.itemTargets.forEach((item) => {
      const match = item.dataset.text.toLowerCase().includes(query)
      item.classList.toggle("hidden", !match)
      if (match) visible += 1
    })

    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", visible > 0)
  }
}
