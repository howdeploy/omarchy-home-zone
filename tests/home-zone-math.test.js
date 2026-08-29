const test = require("node:test")
const assert = require("node:assert/strict")
const HomeZoneMath = require("../HomeZoneMath.js")

test("display-size presets preserve the established default geometry", () => {
  assert.equal(HomeZoneMath.normalizeDisplaySize("default"), "default")
  assert.equal(HomeZoneMath.normalizeDisplaySize("SMALL"), "small")
  assert.equal(HomeZoneMath.normalizeDisplaySize("mini"), "mini")
  assert.equal(HomeZoneMath.normalizeDisplaySize("unexpected"), "default")

  assert.equal(HomeZoneMath.scaleForDisplaySize("default"), 1)
  assert.equal(HomeZoneMath.scaleForDisplaySize("small"), 0.8)
  assert.equal(HomeZoneMath.scaleForDisplaySize("mini"), 0.6)
})

test("edge placements keep a bounded margin and center the other axis", () => {
  const available = 1600
  const scaledSize = 842
  const room = available - scaledSize
  const center = room / 2

  assert.equal(HomeZoneMath.placementOffset(available, scaledSize, "x", "left", 48), 48)
  assert.equal(HomeZoneMath.placementOffset(available, scaledSize, "x", "right", 48), room - 48)
  assert.equal(HomeZoneMath.placementOffset(available, scaledSize, "x", "top", 48), center)
  assert.equal(HomeZoneMath.placementOffset(available, scaledSize, "x", "bottom", 48), center)
  assert.equal(HomeZoneMath.placementOffset(available, scaledSize, "x", "center", 48), center)
})

test("placement margins collapse safely on screens smaller than Home Zone", () => {
  assert.equal(HomeZoneMath.placementOffset(600, 842, "x", "left", 48), 0)
  assert.equal(HomeZoneMath.placementOffset(600, 842, "x", "right", 48), 0)
  assert.equal(HomeZoneMath.placementOffset(900, 842, "x", "left", 48), 29)
  assert.equal(HomeZoneMath.placementOffset(900, 842, "x", "right", 48), 29)
})

test("all five placement names normalize explicitly", () => {
  for (const placement of ["center", "top", "right", "bottom", "left"])
    assert.equal(HomeZoneMath.normalizeDisplayPlacement(placement), placement)

  assert.equal(HomeZoneMath.normalizeDisplayPlacement("RIGHT"), "right")
  assert.equal(HomeZoneMath.normalizeDisplayPlacement("elsewhere"), "center")
})
