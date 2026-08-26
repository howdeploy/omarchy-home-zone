import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// CanvasTTY-style settings ownership adapted to Omarchy:
// - launcher switches apply immediately;
// - tile movement and resizing live in a draft until Save;
// - the fixed 10x4 Home Zone boundary never changes;
// - Settings remains the recovery entry point.
Item {
  id: root

  property var appLibrary: null
  property var defaultTiles: []
  property bool opened: false
  property var draftConfig: ({})
  property var draftTiles: []
  property var selectedAppIds: []
  property var appRows: []
  property string searchText: ""
  property string feedback: ""
  property int resizingIndex: -1
  property string resizeDirection: ""
  property point resizeStartPoint: Qt.point(0, 0)
  property var resizeStartTile: ({})
  property var resizeCandidate: ({})
  property bool resizeCandidateValid: true

  readonly property int maxSelectedApps: 4
  readonly property int gridColumns: 10
  readonly property int gridRows: 4

  signal launcherAppsChanged(var appIds)
  signal saveRequested(var nextConfig)

  function clone(value) {
    return JSON.parse(JSON.stringify(value === undefined ? null : value))
  }

  function launcherTileIndex(tiles) {
    var values = Array.isArray(tiles) ? tiles : []
    for (var i = 0; i < values.length; i++)
      if (String(values[i].widget || "") === "launcher") return i
    return -1
  }

  function defaultAppIds() {
    var ids = []
    if (!root.appLibrary) return ids
    try {
      var rows = root.appLibrary.sortedEntries("") || []
      for (var i = 0; i < rows.length && ids.length < root.maxSelectedApps; i++) {
        var entry = rows[i] ? rows[i].entry : null
        if (entry && entry.id) ids.push(String(entry.id))
      }
    } catch (e) {
      console.warn("home-zone settings: failed to choose default apps:", String(e))
    }
    return ids
  }

  function openForConfig(config) {
    root.draftConfig = root.clone(config || ({}))
    root.draftTiles = root.clone(Array.isArray(root.draftConfig.tiles) ? root.draftConfig.tiles : root.defaultTiles)
    var launcherIndex = root.launcherTileIndex(root.draftTiles)
    var launcherSettings = launcherIndex >= 0 && root.draftTiles[launcherIndex].settings
      ? root.draftTiles[launcherIndex].settings
      : ({})
    root.selectedAppIds = Object.prototype.hasOwnProperty.call(launcherSettings, "appIds")
      && Array.isArray(launcherSettings.appIds)
      ? launcherSettings.appIds.slice(0, root.maxSelectedApps).map(function(id) { return String(id) })
      : root.defaultAppIds()
    root.searchText = ""
    root.feedback = ""
    root.cancelResize()
    root.refreshApps()
    root.opened = true
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function close() {
    root.cancelResize()
    root.opened = false
    root.feedback = ""
  }

  function refreshApps() {
    var next = []
    if (root.appLibrary) {
      try {
        var rows = root.appLibrary.sortedEntries(root.searchText) || []
        for (var i = 0; i < rows.length; i++) {
          var entry = rows[i] ? rows[i].entry : null
          if (!entry || !entry.id) continue
          next.push({
            id: String(entry.id),
            name: String(root.appLibrary.entryName(entry) || entry.id),
            iconUrl: String(root.appLibrary.iconSource(String(entry.icon || "")) || "")
          })
        }
      } catch (e) {
        console.warn("home-zone settings: failed to read applications:", String(e))
      }
    }
    root.appRows = next
  }

  function isAppSelected(id) {
    return root.selectedAppIds.indexOf(String(id)) !== -1
  }

  function toggleApp(id) {
    var value = String(id)
    var next = root.selectedAppIds.slice()
    var index = next.indexOf(value)
    if (index >= 0) {
      next.splice(index, 1)
      root.feedback = ""
    } else if (next.length < root.maxSelectedApps) {
      next.push(value)
      root.feedback = ""
    } else {
      root.feedback = "Launcher holds up to " + root.maxSelectedApps + " applications."
      return
    }
    root.selectedAppIds = next
    root.launcherAppsChanged(next.slice())
  }

  function placementsOverlap(left, right) {
    return left.col < right.col + right.colspan
      && left.col + left.colspan > right.col
      && left.row < right.row + right.rowspan
      && left.row + left.rowspan > right.row
  }

  function layoutValid(tiles) {
    var values = Array.isArray(tiles) ? tiles : []
    for (var i = 0; i < values.length; i++) {
      var tile = values[i]
      if (!Number.isInteger(tile.col) || !Number.isInteger(tile.row)
          || !Number.isInteger(tile.colspan) || !Number.isInteger(tile.rowspan)
          || tile.col < 0 || tile.row < 0 || tile.colspan < 1 || tile.rowspan < 1
          || tile.col + tile.colspan > root.gridColumns
          || tile.row + tile.rowspan > root.gridRows) return false
      for (var j = i + 1; j < values.length; j++)
        if (root.placementsOverlap(tile, values[j])) return false
    }
    return true
  }

  function placementValidAt(index, candidate, tiles) {
    if (!candidate
        || !Number.isInteger(candidate.col) || !Number.isInteger(candidate.row)
        || !Number.isInteger(candidate.colspan) || !Number.isInteger(candidate.rowspan)
        || candidate.col < 0 || candidate.row < 0
        || candidate.colspan < 1 || candidate.rowspan < 1
        || candidate.col + candidate.colspan > root.gridColumns
        || candidate.row + candidate.rowspan > root.gridRows) return false
    var values = Array.isArray(tiles) ? tiles : []
    for (var i = 0; i < values.length; i++) {
      if (i !== index && root.placementsOverlap(candidate, values[i])) return false
    }
    return true
  }

  function beginResize(index, direction, pointerX, pointerY) {
    if (index < 0 || index >= root.draftTiles.length) return
    root.resizingIndex = index
    root.resizeDirection = String(direction || "se")
    root.resizeStartPoint = Qt.point(pointerX, pointerY)
    root.resizeStartTile = root.clone(root.draftTiles[index])
    root.resizeCandidate = root.clone(root.resizeStartTile)
    root.resizeCandidateValid = true
    root.feedback = ""
  }

  // Same edge/corner geometry as CanvasTTY's resizeHomePlacement, snapped to
  // this plugin's fixed 10x4 grid. The opposite edge stays in place.
  function updateResize(pointerX, pointerY) {
    if (root.resizingIndex < 0) return
    var columnDelta = Math.round((pointerX - root.resizeStartPoint.x)
      / (layoutPreview.cellWidth + layoutPreview.gap))
    var rowDelta = Math.round((pointerY - root.resizeStartPoint.y)
      / (layoutPreview.cellHeight + layoutPreview.gap))
    var start = root.resizeStartTile
    var next = root.clone(start)
    var direction = root.resizeDirection

    if (direction.indexOf("e") !== -1)
      next.colspan = Math.max(1, Math.min(root.gridColumns - start.col, start.colspan + columnDelta))
    if (direction.indexOf("s") !== -1)
      next.rowspan = Math.max(1, Math.min(root.gridRows - start.row, start.rowspan + rowDelta))
    if (direction.indexOf("w") !== -1) {
      var east = start.col + start.colspan
      next.col = Math.max(0, Math.min(east - 1, start.col + columnDelta))
      next.colspan = east - next.col
    }
    if (direction.indexOf("n") !== -1) {
      var south = start.row + start.rowspan
      next.row = Math.max(0, Math.min(south - 1, start.row + rowDelta))
      next.rowspan = south - next.row
    }

    root.resizeCandidate = next
    root.resizeCandidateValid = root.placementValidAt(root.resizingIndex, next, root.draftTiles)
  }

  function finishResize() {
    if (root.resizingIndex < 0) return
    if (root.resizeCandidateValid) {
      var next = root.clone(root.draftTiles)
      next[root.resizingIndex] = root.clone(root.resizeCandidate)
      root.draftTiles = next
      root.feedback = ""
    } else {
      root.feedback = "Tiles cannot overlap. Shrink or move the neighbour first."
    }
    root.cancelResize()
  }

  function cancelResize() {
    root.resizingIndex = -1
    root.resizeDirection = ""
    root.resizeStartTile = ({})
    root.resizeCandidate = ({})
    root.resizeCandidateValid = true
  }

  function placementContainsPoint(tile, pointerX, pointerY) {
    var colspan = Number(tile.colspan || 1)
    var rowspan = Number(tile.rowspan || 1)
    var left = Number(tile.col || 0) * (layoutPreview.cellWidth + layoutPreview.gap)
    var top = Number(tile.row || 0) * (layoutPreview.cellHeight + layoutPreview.gap)
    var width = colspan * layoutPreview.cellWidth + (colspan - 1) * layoutPreview.gap
    var height = rowspan * layoutPreview.cellHeight + (rowspan - 1) * layoutPreview.gap
    return pointerX >= left && pointerX < left + width
      && pointerY >= top && pointerY < top + height
  }

  function releaseTargetIndex(index, pointerX, pointerY, tiles) {
    for (var i = 0; i < tiles.length; i++) {
      if (i !== index && root.placementContainsPoint(tiles[i], pointerX, pointerY)) return i
    }
    return -1
  }

  function tileInSlot(tile, slot) {
    var next = root.clone(tile)
    next.col = Number(slot.col || 0)
    next.row = Number(slot.row || 0)
    next.colspan = Number(slot.colspan || 1)
    next.rowspan = Number(slot.rowspan || 1)
    return next
  }

  // The tile under the release pointer owns the drop. Resolve it before the
  // snapped top-left: the grab offset can leave that snapped slot valid even
  // after the pointer has already crossed onto a neighbouring tile.
  function dropTile(index, targetCol, targetRow, pointerX, pointerY) {
    var current = root.clone(root.draftTiles)
    if (index < 0 || index >= current.length) return
    var moved = root.clone(current[index])
    var requestedRow = Math.max(0, Math.min(root.gridRows - moved.rowspan, Math.round(targetRow)))
    var requestedCol = Math.max(0, Math.min(root.gridColumns - moved.colspan, Math.round(targetCol)))

    var targetIndex = root.releaseTargetIndex(index, pointerX, pointerY, current)
    if (targetIndex >= 0) {
      var target = root.clone(current[targetIndex])
      current[index] = root.tileInSlot(moved, target)
      current[targetIndex] = root.tileInSlot(target, moved)
      if (!root.layoutValid(current)) {
        root.feedback = "That swap does not fit the fixed Home Zone."
        return
      }
      root.feedback = ""
      root.draftTiles = current
      return
    }

    // With no tile under the pointer, keep the tile's size and accept only a
    // normal non-overlapping move into free grid cells.
    var direct = root.clone(moved)
    direct.col = requestedCol
    direct.row = requestedRow
    if (root.placementValidAt(index, direct, current)) {
      current[index] = direct
      root.feedback = ""
      root.draftTiles = current
      return
    }

    root.feedback = "Drop onto a tile to swap, or choose an empty grid position."
  }

  function resetLayout() {
    root.draftTiles = root.clone(root.defaultTiles)
    root.feedback = ""
  }

  function buildConfig() {
    var next = root.clone(root.draftConfig)
    var tiles = root.clone(root.draftTiles)
    var launcherIndex = root.launcherTileIndex(tiles)
    if (launcherIndex >= 0) {
      var launcher = root.clone(tiles[launcherIndex])
      var settings = root.clone(launcher.settings || ({}))
      settings.maxApps = root.maxSelectedApps
      settings.columns = root.maxSelectedApps
      settings.appIds = root.selectedAppIds.slice()
      launcher.settings = settings
      tiles[launcherIndex] = launcher
    }
    next.tiles = tiles
    return next
  }

  function save() {
    if (!root.layoutValid(root.draftTiles)) {
      root.feedback = "Fix the tile layout before saving."
      return
    }
    root.saveRequested(root.buildConfig())
  }

  function previewSurface(widget) {
    if (widget === "clock") return Color.accent
    if (widget === "launcher") return Color.bar.background
    if (widget === "menu") return Color.muted
    if (widget === "settings") return Color.urgent
    return Color.popups.background
  }

  function previewForeground(widget, surface) {
    if (widget === "launcher") return Color.bar.text
    var luminance = surface && surface.r !== undefined
      ? surface.r * 0.299 + surface.g * 0.587 + surface.b * 0.114
      : 0
    return luminance > 0.58 ? Color.background : Color.foreground
  }

  onAppLibraryChanged: refreshApps()

  Connections {
    target: root.appLibrary
    function onAppsChanged() { root.refreshApps() }
  }

  Timer {
    id: searchDebounce
    interval: 120
    onTriggered: root.refreshApps()
  }

  Shortcut {
    sequence: "Escape"
    enabled: root.opened
    onActivated: root.close()
  }

  PanelWindow {
    id: overlay
    anchors { top: true; bottom: true; left: true; right: true }
    visible: root.opened
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-home-zone-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim

      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }
    }

    BorderSurface {
      id: settingsCard
      width: Math.min(842, Math.max(640, overlay.width - 48))
      height: Math.min(650, Math.max(520, overlay.height - 48))
      anchors.centerIn: parent
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)
      radius: Math.max(16, Style.cornerRadius)

      MouseArea {
        anchors.fill: parent
        onClicked: function(mouse) { mouse.accepted = true }
      }

      Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 62

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          text: "Home Zone Settings"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Button {
          width: 38
          height: 38
          anchors.right: parent.right
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          iconText: "\uf00d" // nf-fa-xmark
          foreground: Color.popups.text
          focusable: true
          tooltipText: "Close"
          onClicked: root.close()
        }
      }

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        height: 1
        color: Util.alpha(Color.popups.text, 0.16)
      }

      Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 66

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - footerButtons.width - 52
          text: root.feedback
          visible: text !== ""
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Row {
          id: footerButtons
          anchors.right: parent.right
          anchors.rightMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8

          Button {
            text: "Cancel"
            foreground: Color.popups.text
            bordered: true
            focusable: true
            onClicked: root.close()
          }

          Button {
            text: "Save"
            foreground: Color.popups.text
            accent: Color.accent
            selected: true
            focusable: true
            enabled: root.layoutValid(root.draftTiles)
            opacity: enabled ? 1 : 0.45
            onClicked: root.save()
          }
        }
      }

      Item {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: footer.top
        anchors.margins: 18

        Row {
          anchors.fill: parent
          spacing: 14

          BorderSurface {
            id: appsPanel
            width: Math.floor((body.width - parent.spacing) * 0.46)
            height: parent.height
            color: Util.alpha(Color.popups.text, 0.035)
            borderSpec: Border.flat(Util.alpha(Color.popups.text, 0.18), 1)
            radius: 14

            Text {
              id: appsTitle
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 14
              text: "Launcher apps  " + root.selectedAppIds.length + "/" + root.maxSelectedApps
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            TextField {
              id: searchField
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: appsTitle.bottom
              anchors.leftMargin: 14
              anchors.rightMargin: 14
              anchors.topMargin: 12
              placeholderText: "Search applications"
              foreground: Color.popups.text
              accent: Color.accent
              onTextChanged: {
                root.searchText = text
                searchDebounce.restart()
              }
            }

            Flickable {
              id: appList
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: searchField.bottom
              anchors.bottom: parent.bottom
              anchors.margins: 14
              anchors.topMargin: 10
              clip: true
              contentWidth: width
              contentHeight: appColumn.height
              boundsBehavior: Flickable.StopAtBounds

              QQC.ScrollBar.vertical: QQC.ScrollBar {
                id: appScrollBar
                width: 12
                policy: QQC.ScrollBar.AsNeeded
                minimumSize: 0.12
                padding: 2
                active: true
                opacity: size < 1 ? 1 : 0

                background: Rectangle {
                  radius: width / 2
                  color: Util.alpha(Color.popups.text, 0.10)
                }

                contentItem: Rectangle {
                  implicitWidth: 8
                  radius: width / 2
                  color: appScrollBar.pressed || appScrollBar.hovered
                    ? Color.accent
                    : Util.alpha(Color.popups.text, 0.72)
                }
              }

              Column {
                id: appColumn
                // Keep switches away from the overlaid scrollbar and leave a
                // visible gutter in every system palette.
                width: Math.max(0, appList.width - appScrollBar.width - 14)
                height: implicitHeight
                spacing: 4

                Repeater {
                  model: root.appRows

                  delegate: BorderSurface {
                    id: appRow
                    required property var modelData
                    width: appColumn.width
                    height: 50
                    radius: 10
                    color: appMouse.containsMouse
                      ? Style.hoverFillFor(Color.popups.text, Color.accent)
                      : "transparent"
                    borderSpec: Border.none()

                    Image {
                      width: 30
                      height: 30
                      anchors.left: parent.left
                      anchors.leftMargin: 10
                      anchors.verticalCenter: parent.verticalCenter
                      source: appRow.modelData.iconUrl
                      sourceSize.width: 60
                      sourceSize.height: 60
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                    }

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: 50
                      anchors.right: appSwitch.left
                      anchors.rightMargin: 8
                      anchors.verticalCenter: parent.verticalCenter
                      text: appRow.modelData.name
                      color: Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    ToggleSwitch {
                      id: appSwitch
                      anchors.right: parent.right
                      anchors.rightMargin: 6
                      anchors.verticalCenter: parent.verticalCenter
                      checked: root.isAppSelected(appRow.modelData.id)
                      interactive: false
                      foreground: Color.popups.text
                      accent: Color.accent
                      trackHeight: 22
                    }

                    MouseArea {
                      id: appMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleApp(appRow.modelData.id)
                    }
                  }
                }
              }
            }
          }

          BorderSurface {
            id: layoutPanel
            width: body.width - appsPanel.width - parent.spacing
            height: parent.height
            color: Util.alpha(Color.popups.text, 0.035)
            borderSpec: Border.flat(Util.alpha(Color.popups.text, 0.18), 1)
            radius: 14

            Text {
              id: layoutTitle
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.margins: 14
              text: "Tile layout"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              id: layoutHint
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: layoutTitle.bottom
              anchors.leftMargin: 14
              anchors.rightMargin: 14
              anchors.topMargin: 5
              text: "Drag the centre to move. Drop onto another tile to swap positions and sizes. Drag any edge or corner to resize."
              color: Util.alpha(Color.popups.text, 0.68)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Item {
              id: layoutPreview
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: layoutHint.bottom
              anchors.leftMargin: 14
              anchors.rightMargin: 14
              anchors.topMargin: 22
              height: Math.min(220, width * 0.43)

              readonly property real gap: 8
              readonly property real cellWidth: (width - gap * (root.gridColumns - 1)) / root.gridColumns
              readonly property real cellHeight: (height - gap * (root.gridRows - 1)) / root.gridRows

              Repeater {
                model: root.gridColumns * root.gridRows

                delegate: Rectangle {
                  required property int index
                  width: layoutPreview.cellWidth
                  height: layoutPreview.cellHeight
                  x: (index % root.gridColumns) * (layoutPreview.cellWidth + layoutPreview.gap)
                  y: Math.floor(index / root.gridColumns) * (layoutPreview.cellHeight + layoutPreview.gap)
                  radius: 9
                  color: Util.alpha(Color.popups.text, 0.025)
                  border.width: 1
                  border.color: Util.alpha(Color.popups.text, 0.16)
                }
              }

              Repeater {
                model: root.draftTiles

                delegate: Item {
                  id: previewTile
                  required property int index
                  required property var modelData
                  readonly property var tile: root.resizingIndex === previewTile.index
                    ? root.resizeCandidate
                    : modelData
                  readonly property string widgetId: String(tile.widget || "tile")
                  readonly property color surfaceColor: root.previewSurface(widgetId)
                  x: Number(tile.col || 0) * (layoutPreview.cellWidth + layoutPreview.gap)
                  y: Number(tile.row || 0) * (layoutPreview.cellHeight + layoutPreview.gap)
                  width: Number(tile.colspan || 1) * layoutPreview.cellWidth
                    + (Number(tile.colspan || 1) - 1) * layoutPreview.gap
                  height: Number(tile.rowspan || 1) * layoutPreview.cellHeight
                    + (Number(tile.rowspan || 1) - 1) * layoutPreview.gap

                  // Drag only this visual surface. The delegate itself stays
                  // bound to modelData, so MouseArea can never destroy the
                  // grid-bound x/y bindings while previewing a move.
                  Item {
                    id: dragSurface
                    width: previewTile.width
                    height: previewTile.height
                    x: 0
                    y: 0

                    BorderSurface {
                      anchors.fill: parent
                      color: previewTile.surfaceColor
                      borderSpec: Border.flat(
                        root.resizingIndex === previewTile.index && !root.resizeCandidateValid
                          ? Color.urgent
                          : Util.alpha(Color.popups.text, 0.35),
                        root.resizingIndex === previewTile.index ? 2 : 1)
                      radius: 10
                    }

                    Text {
                      anchors.centerIn: parent
                      text: previewTile.widgetId.charAt(0).toUpperCase() + previewTile.widgetId.slice(1)
                        + "\n" + Number(previewTile.tile.colspan || 1) + " × " + Number(previewTile.tile.rowspan || 1)
                      color: root.previewForeground(previewTile.widgetId, previewTile.surfaceColor)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                      horizontalAlignment: Text.AlignHCenter
                    }

                    MouseArea {
                      id: dragArea
                      z: 5
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.SizeAllCursor
                      drag.target: dragSurface
                      drag.axis: Drag.XAndYAxis
                      drag.minimumX: -previewTile.x
                      drag.maximumX: layoutPreview.width - previewTile.x - dragSurface.width
                      drag.minimumY: -previewTile.y
                      drag.maximumY: layoutPreview.height - previewTile.y - dragSurface.height
                      drag.smoothed: false
                      onReleased: function(mouse) {
                        var columnStep = layoutPreview.cellWidth + layoutPreview.gap
                        var rowStep = layoutPreview.cellHeight + layoutPreview.gap
                        var point = dragArea.mapToItem(layoutPreview, mouse.x, mouse.y)
                        var col = Math.round((previewTile.x + dragSurface.x) / columnStep)
                        var row = Math.round((previewTile.y + dragSurface.y) / rowStep)
                        dragSurface.x = 0
                        dragSurface.y = 0
                        root.dropTile(previewTile.index, col, row, point.x, point.y)
                      }
                      onCanceled: {
                        dragSurface.x = 0
                        dragSurface.y = 0
                      }
                    }

                    // CanvasTTY owns resize from every edge and corner. Only
                    // north-west and south-east draw a cue; all eight targets
                    // keep generous hit areas and the appropriate cursor.
                    Repeater {
                      model: ["n", "ne", "e", "se", "s", "sw", "w", "nw"]

                      delegate: MouseArea {
                        id: resizeHandle
                        required property var modelData
                        readonly property string direction: String(modelData)
                        readonly property bool north: direction.indexOf("n") !== -1
                        readonly property bool south: direction.indexOf("s") !== -1
                        readonly property bool east: direction.indexOf("e") !== -1
                        readonly property bool west: direction.indexOf("w") !== -1
                        readonly property bool corner: (north || south) && (east || west)

                        z: 20
                        width: corner ? 28 : ((north || south) ? Math.max(18, previewTile.width - 36) : 18)
                        height: corner ? 28 : ((east || west) ? Math.max(18, previewTile.height - 36) : 18)
                        x: west ? -7 : (east ? previewTile.width - width + 7 : 18)
                        y: north ? -7 : (south ? previewTile.height - height + 7 : 18)
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: direction === "n" || direction === "s"
                          ? Qt.SizeVerCursor
                          : (direction === "e" || direction === "w"
                            ? Qt.SizeHorCursor
                            : (direction === "ne" || direction === "sw"
                              ? Qt.SizeBDiagCursor
                              : Qt.SizeFDiagCursor))

                        onPressed: function(mouse) {
                          var point = resizeHandle.mapToItem(layoutPreview, mouse.x, mouse.y)
                          root.beginResize(previewTile.index, resizeHandle.direction, point.x, point.y)
                          mouse.accepted = true
                        }
                        onPositionChanged: function(mouse) {
                          if (!pressed) return
                          var point = resizeHandle.mapToItem(layoutPreview, mouse.x, mouse.y)
                          root.updateResize(point.x, point.y)
                        }
                        onReleased: function(mouse) {
                          var point = resizeHandle.mapToItem(layoutPreview, mouse.x, mouse.y)
                          root.updateResize(point.x, point.y)
                          root.finishResize()
                        }
                        onCanceled: root.cancelResize()

                        Item {
                          anchors.fill: parent
                          visible: resizeHandle.direction === "nw" || resizeHandle.direction === "se"

                          Rectangle {
                            width: 16
                            height: 3
                            radius: 2
                            color: Color.popups.text
                            x: resizeHandle.direction === "nw" ? 7 : parent.width - width - 7
                            y: resizeHandle.direction === "nw" ? 7 : parent.height - height - 7
                          }

                          Rectangle {
                            width: 3
                            height: 16
                            radius: 2
                            color: Color.popups.text
                            x: resizeHandle.direction === "nw" ? 7 : parent.width - width - 7
                            y: resizeHandle.direction === "nw" ? 7 : parent.height - height - 7
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            Button {
              anchors.left: parent.left
              anchors.leftMargin: 14
              anchors.top: layoutPreview.bottom
              anchors.topMargin: 18
              text: "Reset layout"
              foreground: Color.popups.text
              bordered: true
              focusable: true
              onClicked: root.resetLayout()
            }
          }
        }
      }
    }
  }
}
