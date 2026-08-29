function finiteNumber(value, fallback) {
  var number = Number(value)
  return isFinite(number) ? number : fallback
}

function normalizeDisplaySize(value) {
  var size = String(value || "default").trim().toLowerCase()
  return size === "small" || size === "mini" ? size : "default"
}

function normalizeDisplayPlacement(value) {
  var placement = String(value || "center").trim().toLowerCase()
  return placement === "top" || placement === "right"
    || placement === "bottom" || placement === "left"
    ? placement
    : "center"
}

function scaleForDisplaySize(value) {
  var size = normalizeDisplaySize(value)
  if (size === "small") return 0.8
  if (size === "mini") return 0.6
  return 1
}

function placementOffset(available, scaledSize, axis, placement, margin) {
  var room = Math.max(
    0,
    finiteNumber(available, 0) - Math.max(0, finiteNumber(scaledSize, 0))
  )
  var edgeInset = Math.min(
    Math.max(0, finiteNumber(margin, 0)),
    room / 2
  )
  var normalizedAxis = String(axis || "").trim().toLowerCase()
  var normalizedPlacement = normalizeDisplayPlacement(placement)

  if ((normalizedAxis === "x" && normalizedPlacement === "left")
      || (normalizedAxis === "y" && normalizedPlacement === "top")) return edgeInset
  if ((normalizedAxis === "x" && normalizedPlacement === "right")
      || (normalizedAxis === "y" && normalizedPlacement === "bottom")) return room - edgeInset
  return room / 2
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    normalizeDisplayPlacement: normalizeDisplayPlacement,
    normalizeDisplaySize: normalizeDisplaySize,
    placementOffset: placementOffset,
    scaleForDisplaySize: scaleForDisplaySize
  }
}
