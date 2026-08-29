const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.join(__dirname, "..")
const source = fs.readFileSync(path.join(root, "HomeZone.qml"), "utf8")
const settingsSource = fs.readFileSync(path.join(root, "SettingsOverlay.qml"), "utf8")
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))

test("settings I/O stays behind the confined config helper", () => {
  assert.doesNotMatch(source, /\bFileView\s*\{/)
  assert.doesNotMatch(source, /Quickshell\.env\("HOME"\)/)
  assert.match(source, /helpers\/home_zone_config\.py/)
  assert.match(source, /\["\/usr\/bin\/python3", root\.configHelperPath, "read"\]/)
  assert.match(source, /stdinEnabled:\s*true/)
  assert.match(source, /\["\/usr\/bin\/python3", root\.configHelperPath, "write"\]/)
  assert.match(source, /configWriteProcess\.running \|\| configReadProcess\.running/)
  assert.match(source, /if \(!root\.configWritePending[\s\S]*root\.handleConfigLoaded\(nextText\)/)
})

test("release includes whole-widget size and placement controls", () => {
  assert.match(source, /HomeZoneMath\.scaleForDisplaySize/)
  assert.match(source, /HomeZoneMath\.placementOffset/)
  assert.match(settingsSource, /value:\s*"default"/)
  assert.match(settingsSource, /value:\s*"small"/)
  assert.match(settingsSource, /value:\s*"mini"/)
  for (const placement of ["center", "top", "right", "bottom", "left"])
    assert.match(settingsSource, new RegExp(`value:\\s*"${placement}"`))
})

test("marketplace package has no install hook and advertises version 1.1.0", () => {
  assert.equal(fs.existsSync(path.join(root, "install.sh")), false)
  assert.equal(manifest.version, "1.1.0")
  assert.deepEqual(manifest.kinds, ["panel"])
  assert.equal(manifest.entryPoints.panel, "HomeZone.qml")
})
