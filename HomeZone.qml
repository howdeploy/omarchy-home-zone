import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Home Zone — десктопные виджеты поверх обоев.
//
// Контракт panel-плагина omarchy:
//  - корневой Item БЕЗ required-свойств (хост инжектит контекст ПОСЛЕ загрузки
//    через Loader.onLoaded; required ломает инстанцирование — см. баг бара);
//  - keepLoaded: true в manifest.json — монтируется при старте шелла;
//  - слой WlrLayer.Background — поверх обоев, под окнами;
//  - mask ограничивает input-регион карточкой — остальной экран кликается насквозь.
Item {
  id: root

  // ── Контекст от хоста (обычные свойства, инжект после загрузки) ──
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/home-zone.json"

  // ── Дефолтный конфиг (пользовательский ~/.config/omarchy/home-zone.json
  //    перекрывает; массив tiles заменяется целиком) ──
  property var defaultCfg: ({
    display: { size: "default", placement: "center" },
    grid: { columns: 10, cellWidth: 68, cellHeight: 68, gap: 14 },
    card: { visible: true, backgroundAlpha: 0.75, radius: 18, padding: 18 },
    colors: {},
    tiles: [
      { widget: "clock", col: 0, row: 0, colspan: 10, rowspan: 2,
        settings: { format: "HH:mm", fontFamily: "JetBrainsMono Nerd Font", timeSize: 118, letterSpacing: -9 } },
      { widget: "launcher", col: 0, row: 2, colspan: 6, rowspan: 2,
        settings: { maxApps: 4, columns: 4 } },
      { widget: "menu", col: 6, row: 2, colspan: 2, rowspan: 2,
        settings: { label: "Menu" } },
      { widget: "settings", col: 8, row: 2, colspan: 2, rowspan: 2,
        settings: { label: "Settings" } }
    ]
  })

  // Defaults keep the panel drawable while FileView resolves the user config,
  // but they are never writable state until the load has completed.
  property var cfg: defaultCfg
  property var tiles: defaultCfg.tiles
  property bool configReady: false
  property bool configWriteBlocked: true
  property bool settingsOpenPending: false
  property int configLoadFailures: 0
  property int lastConfigLoadError: 0
  readonly property int configLoadRetryLimit: 5

  // Omarchy owns the palette. Each CanvasTTY-style surface maps to a live
  // system role; colors.* remains an optional user override layer.
  readonly property color cardBg: colorOverride(
    ["cardBackground"],
    Util.alpha(Color.background, cfg.card ? cfg.card.backgroundAlpha : 0.75))

  property int columns: cfg.grid ? cfg.grid.columns : 10
  property real cellW: cfg.grid ? cfg.grid.cellWidth : 68
  property real cellH: cfg.grid ? cfg.grid.cellHeight : 68
  property real gap: cfg.grid ? cfg.grid.gap : 14
  property int pad: cfg.card ? cfg.card.padding : 18

  readonly property real stageWidth: columns * cellW + (columns - 1) * gap
  property real stageHeight: gridHeight()
  readonly property string displaySize: normalizeDisplaySize(
    cfg.display ? cfg.display.size : "default")
  readonly property string displayPlacement: normalizeDisplayPlacement(
    cfg.display ? cfg.display.placement : "center")
  readonly property real displayScale: scaleForDisplaySize(displaySize)
  readonly property real baseCardWidth: stageWidth + pad * 2
  readonly property real baseCardHeight: stageHeight + pad * 2
  readonly property real placementMargin: 48

  function normalizeDisplaySize(value) {
    var size = String(value || "default")
    return size === "small" || size === "mini" ? size : "default"
  }

  function normalizeDisplayPlacement(value) {
    var placement = String(value || "center")
    return placement === "top" || placement === "right"
      || placement === "bottom" || placement === "left"
      ? placement
      : "center"
  }

  function scaleForDisplaySize(value) {
    if (value === "small") return 0.8
    if (value === "mini") return 0.6
    return 1
  }

  function placementOffset(available, scaledSize, axis) {
    var room = Math.max(0, available - scaledSize)
    var edgeInset = Math.min(root.placementMargin, room / 2)
    if ((axis === "x" && root.displayPlacement === "left")
        || (axis === "y" && root.displayPlacement === "top")) return edgeInset
    if ((axis === "x" && root.displayPlacement === "right")
        || (axis === "y" && root.displayPlacement === "bottom")) return room - edgeInset
    return room / 2
  }

  function colorOverride(keys, fallback) {
    var colors = cfg && cfg.colors ? cfg.colors : ({})
    for (var i = 0; i < keys.length; i++) {
      var value = colors[keys[i]]
      if (typeof value === "string" && value.length > 0) return value
    }
    return fallback
  }

  function defaultTileSurface(widget) {
    if (widget === "clock") return Color.accent
    if (widget === "launcher") return Color.bar.background
    if (widget === "menu") return Color.muted
    if (widget === "settings") return Color.urgent
    return Color.popups.background
  }

  function tileSurface(widget) {
    return colorOverride([widget + "Background", "tileBackground"], defaultTileSurface(widget))
  }

  function contrastText(surface) {
    var luminance = surface && surface.r !== undefined
      ? surface.r * 0.299 + surface.g * 0.587 + surface.b * 0.114
      : 0
    return luminance > 0.58 ? Color.background : Color.foreground
  }

  function tileForeground(widget, surface) {
    var fallback = widget === "launcher" ? Color.bar.text : contrastText(surface)
    return colorOverride([widget + "Text", "text"], fallback)
  }

  function tileBorderColor(widget, foreground) {
    return colorOverride([widget + "Border", "border"], Util.alpha(foreground, 0.3))
  }

  function launcherButtonColor(foreground) {
    return colorOverride(["launcherTile"], Util.alpha(foreground, 0.10))
  }

  function tileRadius(widget) {
    return widget === "launcher" ? 16 : 20
  }

  function tilePadding(widget) {
    return widget === "launcher" ? 8 : 0
  }

  function widgetSource(widget) {
    return widget === "menu" ? "widgets/menu-button.qml" : "widgets/" + widget + ".qml"
  }

  function gridHeight() {
    var h = 0
    var t = root.tiles
    for (var i = 0; i < t.length; i++) {
      var tl = t[i]
      var bottom = (tl.row || 0) * (cellH + gap) + (tl.rowspan || 1) * cellH + ((tl.rowspan || 1) - 1) * gap
      if (bottom > h) h = bottom
    }
    return Math.max(h, cellH)
  }

  function mergeDeep(base, extra) {
    if (extra === null || typeof extra !== "object") return base === undefined ? extra : extra === undefined ? base : extra
    if (Array.isArray(extra)) return extra
    var out = {}
    for (var k in base) out[k] = mergeDeep(base[k], extra[k])
    for (var k2 in extra) if (!(k2 in base)) out[k2] = extra[k2]
    return out
  }

  function clone(value) {
    return JSON.parse(JSON.stringify(value === undefined ? null : value))
  }

  function migrateLegacyGrid(config) {
    var grid = config && config.grid ? config.grid : ({})
    if (Number(grid.columns) !== 5
        || Number(grid.cellWidth) !== 150
        || Number(grid.cellHeight) !== 150
        || Number(grid.gap) !== 14) return config

    // Two 68px cells plus the unchanged 14px gap equal one legacy 150px
    // cell. Doubling every coordinate therefore adds resize precision without
    // moving or resizing a single pixel of the established Home Zone.
    config.grid = { columns: 10, cellWidth: 68, cellHeight: 68, gap: 14 }
    if (Array.isArray(config.tiles)) {
      config.tiles = config.tiles.map(function(tile) {
        var next = JSON.parse(JSON.stringify(tile))
        next.col = Number(next.col || 0) * 2
        next.row = Number(next.row || 0) * 2
        next.colspan = Number(next.colspan || 1) * 2
        next.rowspan = Number(next.rowspan || 1) * 2
        return next
      })
    }
    return config
  }

  function applyConfig(user) {
    cfg = migrateLegacyGrid(mergeDeep(defaultCfg, user || ({})))
    tiles = Array.isArray(cfg.tiles) ? cfg.tiles : []
    columns = cfg.grid ? cfg.grid.columns : 10
    cellW = cfg.grid ? cfg.grid.cellWidth : 68
    cellH = cfg.grid ? cfg.grid.cellHeight : 68
    gap = cfg.grid ? cfg.grid.gap : 14
    pad = cfg.card ? cfg.card.padding : 18
    stageHeight = gridHeight()
  }

  function loadConfig(raw) {
    var user
    try {
      user = JSON.parse(String(raw === undefined || raw === null ? "" : raw))
      if (!user || typeof user !== "object" || Array.isArray(user))
        throw new Error("top-level config must be an object")
    } catch (e) {
      console.warn("home-zone: config parse failed, keeping the last known config:", String(e))
      return false
    }
    root.applyConfig(user)
    return true
  }

  function openPendingSettings() {
    if (!root.settingsOpenPending || !root.configReady || root.configWriteBlocked) return
    root.settingsOpenPending = false
    Qt.callLater(function() {
      if (root.configReady && !root.configWriteBlocked)
        settingsOverlay.openForConfig(root.cfg)
    })
  }

  function handleConfigLoaded(raw) {
    if (!root.loadConfig(raw)) {
      root.configWriteBlocked = true
      root.configLoadFailures += 1
      if (root.configLoadFailures < root.configLoadRetryLimit) configReloadTimer.restart()
      return
    }
    root.configLoadFailures = 0
    root.lastConfigLoadError = 0
    root.configReady = true
    root.configWriteBlocked = false
    root.openPendingSettings()
  }

  function handleConfigLoadFailed(error) {
    root.lastConfigLoadError = Number(error)
    root.configWriteBlocked = true
    root.configLoadFailures += 1
    if (root.configLoadFailures < root.configLoadRetryLimit) {
      configReloadTimer.restart()
      return
    }

    // Error 2 is ENOENT. Only a fresh instance may adopt defaults after
    // repeated confirmation that no user config exists. A running instance
    // always keeps its last known good state instead of replacing it.
    if (!root.configReady && root.lastConfigLoadError === 2) {
      root.applyConfig({})
      root.configReady = true
      root.configWriteBlocked = false
      root.openPendingSettings()
      return
    }
    console.warn("home-zone: config load failed; writes remain blocked:", String(error))
  }

  function persistConfig(nextConfig) {
    if (!root.configReady || root.configWriteBlocked) {
      console.warn("home-zone: refusing to write before the user config is ready")
      return false
    }
    var serialized = JSON.stringify(nextConfig, null, 2)
    if (!root.loadConfig(serialized)) return false
    configFile.setText(serialized + "\n")
    return true
  }

  function persistLauncherApps(appIds) {
    if (!root.configReady || root.configWriteBlocked) return false
    var next = root.clone(root.cfg || root.defaultCfg)
    var values = Array.isArray(next.tiles) ? next.tiles : []
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].widget || "") !== "launcher") continue
      var launcher = values[i]
      launcher.settings = launcher.settings || ({})
      launcher.settings.maxApps = 4
      launcher.settings.columns = 4
      launcher.settings.appIds = Array.isArray(appIds) ? appIds.slice(0, 4) : []
      break
    }
    return root.persistConfig(next)
  }

  // Layout Save owns tile geometry and the display presets only. All other
  // settings are taken from the latest loaded config, so a stale overlay draft
  // can never replace appIds or other settings changed during a reload.
  function persistLayout(draftTiles, displaySize, displayPlacement) {
    if (!root.configReady || root.configWriteBlocked || !Array.isArray(draftTiles)) return false
    var next = root.clone(root.cfg || root.defaultCfg)
    var currentTiles = Array.isArray(next.tiles) ? next.tiles : []
    var usedDrafts = []

    for (var i = 0; i < currentTiles.length; i++) {
      var current = currentTiles[i]
      var widget = String(current.widget || "")
      var draft = null
      for (var j = 0; j < draftTiles.length; j++) {
        if (!usedDrafts[j] && String(draftTiles[j].widget || "") === widget) {
          usedDrafts[j] = true
          draft = draftTiles[j]
          break
        }
      }
      if (!draft) continue
      current.col = Number(draft.col)
      current.row = Number(draft.row)
      current.colspan = Number(draft.colspan)
      current.rowspan = Number(draft.rowspan)
    }
    next.tiles = currentTiles
    if (!next.display || typeof next.display !== "object" || Array.isArray(next.display))
      next.display = ({})
    next.display.size = root.normalizeDisplaySize(displaySize)
    next.display.placement = root.normalizeDisplayPlacement(displayPlacement)
    return root.persistConfig(next)
  }

  function launcherSettings() {
    var values = Array.isArray(root.tiles) ? root.tiles : []
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].widget || "") === "launcher") return values[i].settings || ({})
    }
    return ({})
  }

  function loadedWidgetDiagnostics(widget) {
    for (var i = 0; i < tilesRepeater.count; i++) {
      var delegate = tilesRepeater.itemAt(i)
      if (delegate && delegate.widgetId === widget
          && typeof delegate.loadedDiagnostics === "function") return delegate.loadedDiagnostics()
    }
    return null
  }

  function openSettings() {
    if (!root.configReady || root.configWriteBlocked) {
      root.settingsOpenPending = true
      root.configLoadFailures = 0
      configReloadTimer.restart()
      return
    }
    settingsOverlay.openForConfig(root.cfg)
  }

  function diagnostics(_arg) {
    return JSON.stringify({
      card: {
        width: cardPlacement.width,
        height: cardPlacement.height,
        baseWidth: root.baseCardWidth,
        baseHeight: root.baseCardHeight,
        x: cardPlacement.x,
        y: cardPlacement.y
      },
      display: {
        size: root.displaySize,
        placement: root.displayPlacement,
        scale: root.displayScale,
        edgeMargin: root.placementMargin
      },
      grid: { columns: root.columns, cellWidth: root.cellW, cellHeight: root.cellH, gap: root.gap },
      palette: {
        foreground: String(Color.foreground),
        background: String(Color.background),
        accent: String(Color.accent),
        urgent: String(Color.urgent),
        muted: String(Color.muted),
        barBackground: String(Color.bar.background),
        barText: String(Color.bar.text)
      },
      surfaces: {
        clock: String(root.tileSurface("clock")),
        launcher: String(root.tileSurface("launcher")),
        menu: String(root.tileSurface("menu")),
        settings: String(root.tileSurface("settings"))
      },
      launcherAppIds: Array.isArray(root.launcherSettings().appIds)
        ? root.launcherSettings().appIds
        : null,
      launcherRuntime: root.loadedWidgetDiagnostics("launcher"),
      configState: {
        ready: root.configReady,
        writeBlocked: root.configWriteBlocked,
        loadFailures: root.configLoadFailures,
        lastLoadError: root.lastConfigLoadError
      },
      tiles: root.tiles.map(function(tile) {
        return {
          widget: String(tile.widget || ""),
          col: Number(tile.col || 0),
          row: Number(tile.row || 0),
          colspan: Number(tile.colspan || 1),
          rowspan: Number(tile.rowspan || 1)
        }
      })
    })
  }

  // Горячая перезагрузка конфига (паттерн из Color.qml userShellFile)
  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: {
      root.configWriteBlocked = true
      root.configLoadFailures = 0
      // FileView also emits fileChanged for setText(). Reloading from inside
      // that signal races the asynchronous atomic write and can be dropped,
      // leaving writes blocked until the settings panel is reopened.
      configReloadTimer.restart()
    }
    onSaved: root.configWriteBlocked = false
    onSaveFailed: function(error) {
      console.warn("home-zone: config save failed; reloading the last persisted config:", String(error))
      root.configWriteBlocked = true
      root.configLoadFailures = 0
      configReloadTimer.restart()
    }
    onLoaded: root.handleConfigLoaded(text())
    onLoadFailed: function(error) { root.handleConfigLoadFailed(error) }
  }

  Timer {
    id: configReloadTimer
    interval: 150
    repeat: false
    onTriggered: configFile.reload()
  }

  SettingsOverlay {
    id: settingsOverlay
    appLibrary: root.shell ? root.shell.appLibrary : null
    defaultTiles: root.defaultCfg.tiles
    persistenceReady: root.configReady && !root.configWriteBlocked
    onLauncherAppsChanged: function(appIds) {
      if (!root.persistLauncherApps(appIds))
        settingsOverlay.feedback = "Configuration is reloading. Try again in a moment."
    }
    onSaveRequested: function(nextTiles, displaySize, displayPlacement) {
      if (root.persistLayout(nextTiles, displaySize, displayPlacement)) settingsOverlay.close()
      else settingsOverlay.feedback = "Configuration is reloading. Try Save again."
    }
  }

  // ── Панель поверх обоев ──
  PanelWindow {
    id: panel
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: true
    WlrLayershell.namespace: "omarchy-home-zone"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // Клики принимает только карточка; остальная область — сквозная.
    mask: Region { item: cardPlacement }

    Item {
      id: cardPlacement
      width: root.baseCardWidth * root.displayScale
      height: root.baseCardHeight * root.displayScale
      x: root.placementOffset(panel.width, width, "x")
      y: root.placementOffset(panel.height, height, "y")
      visible: root.cfg.card ? root.cfg.card.visible !== false : true

      BorderSurface {
        id: card
        width: root.baseCardWidth
        height: root.baseCardHeight
        scale: root.displayScale
        transformOrigin: Item.TopLeft
        radius: root.cfg.card ? root.cfg.card.radius : 18
        color: root.cardBg
        borderSpec: Border.none()

        Item {
          id: content
          anchors.fill: parent
          anchors.margins: root.pad

          Repeater {
            id: tilesRepeater
            model: root.tiles
            delegate: tileComponent
          }
        }
      }
    }
  }

  // ── Одна плитка: фон-«карточка» + виджет из widgets/ через Loader ──
  Component {
    id: tileComponent

    Item {
      id: tileDelegate
      required property var modelData
      property var tile: modelData
      readonly property string widgetId: String(tile.widget || "")
      readonly property color surfaceColor: root.tileSurface(widgetId)
      readonly property color foregroundColor: root.tileForeground(widgetId, surfaceColor)
      readonly property color outlineColor: root.tileBorderColor(widgetId, foregroundColor)

      function loadedDiagnostics() {
        return tileLoader.item && typeof tileLoader.item.diagnostics === "function"
          ? tileLoader.item.diagnostics()
          : null
      }

      x: (tile.col || 0) * (root.cellW + root.gap)
      y: (tile.row || 0) * (root.cellH + root.gap)
      width: (tile.colspan || 1) * root.cellW + ((tile.colspan || 1) - 1) * root.gap
      height: (tile.rowspan || 1) * root.cellH + ((tile.rowspan || 1) - 1) * root.gap

      BorderSurface {
        anchors.fill: parent
        color: parent.surfaceColor
        borderSpec: parent.tile.widget === "launcher" ? Border.none() : Border.flat(parent.outlineColor, 1)
        radius: root.tileRadius(parent.widgetId)
      }

      Loader {
        id: tileLoader
        anchors.fill: parent
        anchors.margins: root.tilePadding(String(tile.widget || ""))
        source: root.widgetSource(String(tile.widget || ""))

        onLoaded: {
          if (!item) return
          var it = item
          // Привязки, а не разовая запись: хост инжектит shell ПОСЛЕ монтирования
          // плагина, а виджеты создаются раньше — биндинг подхватит контекст.
          if ("shell" in it) it.shell = Qt.binding(function() { return root.shell })
          if ("appLibrary" in it) it.appLibrary = Qt.binding(function() { return root.shell ? root.shell.appLibrary : null })
          if ("homeZone" in it) it.homeZone = root
          if ("tileConfig" in it) it.tileConfig = Qt.binding(function() { return tileDelegate.tile.settings || {} })
          if ("tileConfigJson" in it) it.tileConfigJson = Qt.binding(function() {
            return JSON.stringify(tileDelegate.tile.settings || {})
          })
          if ("tileColors" in it) it.tileColors = Qt.binding(function() {
            return ({
              background: tileDelegate.surfaceColor,
              text: tileDelegate.foregroundColor,
              border: tileDelegate.outlineColor,
              launcherTile: root.launcherButtonColor(tileDelegate.foregroundColor),
              accent: Color.accent,
              urgent: Color.urgent
            })
          })
        }
      }
    }
  }
}
