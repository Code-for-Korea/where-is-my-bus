import { Controller } from "@hotwired/stimulus"

// 필터 폼에서 값이 바뀌면 바로 제출한다.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
