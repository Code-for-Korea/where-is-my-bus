import { Controller } from "@hotwired/stimulus"

// 표의 행 어디를 눌러도 상세 화면으로 이동한다. 행 안의 링크·버튼·입력은 제 동작을 그대로 한다.
export default class extends Controller {
  static values = { url: String }

  open(event) {
    if (event.target.closest("a, button, input, select, textarea, label, form")) return
    if (window.getSelection().toString() !== "") return // 글자를 드래그해 선택한 경우는 이동하지 않는다.
    if (window.Turbo) {
      window.Turbo.visit(this.urlValue)
    } else {
      window.location.href = this.urlValue
    }
  }
}
