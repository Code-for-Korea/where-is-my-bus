export class BaseMapProvider {
  constructor(canvas, options = {}) {
    this.canvas = canvas
    this.options = options
  }

  render(_center, _stops, _buses) {
    throw new Error("render() must be implemented by subclass")
  }

  static isAvailable() {
    return true
  }
}
