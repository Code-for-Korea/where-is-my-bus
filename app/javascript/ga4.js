export function ga4Event(name, params = {}) {
  if (typeof gtag !== "undefined") gtag("event", name, params)
}
