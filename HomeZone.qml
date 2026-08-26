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

  property var cfg: defaultCfg
  property var tiles: []

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

  function loadConfig(raw) {
    var user = {}
    try { user = JSON.parse(raw || "{}") } catch (e) { console.warn("home-zone: конфиг не распарсился:", String(e)) }
    cfg = migrateLegacyGrid(mergeDeep(defaultCfg, user))
    tiles = Array.isArray(cfg.tiles) ? cfg.tiles : []
    columns = cfg.grid ? cfg.grid.columns : 10
    cellW = cfg.grid ? cfg.grid.cellWidth : 68
    cellH = cfg.grid ? cfg.grid.cellHeight : 68
    gap = cfg.grid ? cfg.grid.gap : 14
    pad = cfg.card ? cfg.card.padding : 18
    stageHeight = gridHeight()
  }

  function persistConfig(nextConfig) {
    var serialized = JSON.stringify(nextConfig, null, 2)
    root.loadConfig(serialized)
    configFile.setText(serialized + "\n")
  }

  function persistLauncherApps(appIds) {
    var next = JSON.parse(JSON.stringify(root.cfg || root.defaultCfg))
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
    root.persistConfig(next)
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
    settingsOverlay.openForConfig(root.cfg)
  }

  function diagnostics(_arg) {
    return JSON.stringify({
      card: { width: root.stageWidth + root.pad * 2, height: root.stageHeight + root.pad * 2 },
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
    onFileChanged: reload()
    onLoaded: root.loadConfig(text())
    onLoadFailed: root.loadConfig("")
  }

  Component.onCompleted: root.loadConfig("")

  SettingsOverlay {
    id: settingsOverlay
    appLibrary: root.shell ? root.shell.appLibrary : null
    defaultTiles: root.defaultCfg.tiles
    onLauncherAppsChanged: function(appIds) {
      root.persistLauncherApps(appIds)
    }
    onSaveRequested: function(nextConfig) {
      root.persistConfig(nextConfig)
      settingsOverlay.close()
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
    mask: Region { item: card }

    BorderSurface {
      id: card
      width: root.stageWidth + root.pad * 2
      height: root.stageHeight + root.pad * 2
      anchors.centerIn: parent
      radius: root.cfg.card ? root.cfg.card.radius : 18
      color: root.cardBg
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)
      visible: root.cfg.card ? root.cfg.card.visible !== false : true

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
