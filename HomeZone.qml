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
    grid: { columns: 6, cellWidth: 170, cellHeight: 130, gap: 14 },
    card: { visible: true, backgroundAlpha: 0.75, radius: 18, padding: 18 },
    colors: {},
    tiles: [
      { widget: "clock", col: 0, row: 0, colspan: 2, rowspan: 1,
        settings: { format: "HH:mm", dateFormat: "dddd d MMMM" } },
      { widget: "launcher", col: 2, row: 0, colspan: 4, rowspan: 2,
        settings: { maxApps: 12, columns: 4 } },
      { widget: "settings", col: 0, row: 1, colspan: 2, rowspan: 1,
        settings: { action: "omarchy-shell shell summon omarchy.menu '{}'", label: "Настройки" } }
    ]
  })

  property var cfg: defaultCfg
  property var tiles: []

  // Цвета: из темы omarchy (Color.*), оверрайды — из конфига colors.*
  property color tileBg: parseColor(cfg.colors.tileBackground, Util.alpha(Color.bar.background, 0.85))
  property color tileText: parseColor(cfg.colors.text, Color.bar.text)
  property color cardBg: parseColor(cfg.colors.cardBackground, Util.alpha(Color.background, cfg.card.backgroundAlpha))

  property int columns: cfg.grid ? cfg.grid.columns : 6
  property int cellW: cfg.grid ? cfg.grid.cellWidth : 170
  property int cellH: cfg.grid ? cfg.grid.cellHeight : 130
  property int gap: cfg.grid ? cfg.grid.gap : 14
  property int pad: cfg.card ? cfg.card.padding : 18

  readonly property real stageWidth: columns * cellW + (columns - 1) * gap
  property real stageHeight: gridHeight()

  function parseColor(value, fallback) {
    return (typeof value === "string" && value.length > 0) ? value : fallback
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

  function loadConfig(raw) {
    var user = {}
    try { user = JSON.parse(raw || "{}") } catch (e) { console.warn("home-zone: конфиг не распарсился:", String(e)) }
    cfg = mergeDeep(defaultCfg, user)
    tiles = Array.isArray(cfg.tiles) ? cfg.tiles : []
    tileBg = parseColor(cfg.colors.tileBackground, Util.alpha(Color.bar.background, 0.85))
    tileText = parseColor(cfg.colors.text, Color.bar.text)
    cardBg = parseColor(cfg.colors.cardBackground, Util.alpha(Color.background, cfg.card.backgroundAlpha))
    columns = cfg.grid ? cfg.grid.columns : 6
    cellW = cfg.grid ? cfg.grid.cellWidth : 170
    cellH = cfg.grid ? cfg.grid.cellHeight : 130
    gap = cfg.grid ? cfg.grid.gap : 14
    pad = cfg.card ? cfg.card.padding : 18
    stageHeight = gridHeight()
  }

  // Горячая перезагрузка конфига (паттерн из Color.qml userShellFile)
  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadConfig(text())
    onLoadFailed: root.loadConfig("")
  }

  Component.onCompleted: root.loadConfig("")

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
    // Клики принимает только карточка; остальная область — сквозная
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
      required property var modelData
      property var tile: modelData

      x: (tile.col || 0) * (root.cellW + root.gap)
      y: (tile.row || 0) * (root.cellH + root.gap)
      width: (tile.colspan || 1) * root.cellW + ((tile.colspan || 1) - 1) * root.gap
      height: (tile.rowspan || 1) * root.cellH + ((tile.rowspan || 1) - 1) * root.gap

      BorderSurface {
        anchors.fill: parent
        color: root.tileBg
        borderSpec: Border.flat(Util.alpha(root.tileText, 0.3), 1)
        radius: Math.min(Style.cornerRadius, 12)
      }

      Loader {
        id: tileLoader
        anchors.fill: parent
        anchors.margins: Math.max(6, root.gap / 2)
        source: "widgets/" + tile.widget + ".qml"

        onLoaded: {
          if (!item) return
          var it = item
          if ("shell" in it) it.shell = root.shell
          if ("appLibrary" in it) it.appLibrary = root.shell ? root.shell.appLibrary : null
          if ("tileConfig" in it) it.tileConfig = tile.settings || {}
          if ("tileColors" in it) it.tileColors = ({ background: root.tileBg, text: root.tileText })
        }
      }
    }
  }
}
