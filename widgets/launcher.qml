import QtQuick
import qs.Commons

// Виджет «Лаунчер»: сетка приложений из AppLibrary (та же база, что у меню omarchy).
// Клик по плитке — запуск приложения.
Item {
  id: root
  anchors.fill: parent

  property var shell: null
  property var appLibrary: null
  // Loader boundaries can coerce nested JS arrays into QVariant values. Pass
  // this widget's settings as JSON so an explicit [] stays different from a
  // missing appIds key and every config update has a scalar change signal.
  property string tileConfigJson: "{}"
  property var tileColors: ({})
  property var parsedConfig: ({})

  readonly property int configuredColumns: Math.max(1, parseInt(parsedConfig.columns || 4))
  readonly property int maxApps: Math.max(1, parseInt(parsedConfig.maxApps || 4))
  readonly property bool hasConfiguredAppIds: Object.prototype.hasOwnProperty.call(parsedConfig, "appIds")
    && Array.isArray(parsedConfig.appIds)
  readonly property var configuredAppIds: hasConfiguredAppIds
    ? parsedConfig.appIds.map(function(id) { return String(id) })
    : null
  property var apps: []
  readonly property int columns: Math.max(1, Math.min(configuredColumns, root.apps.length || 1))
  readonly property color textColor: root.tileColors.text || Color.bar.text
  readonly property color buttonColor: root.tileColors.launcherTile || Util.alpha(textColor, 0.10)
  readonly property int rowCount: Math.max(1, Math.ceil(root.apps.length / root.columns))

  function loadTileConfig() {
    try {
      var value = JSON.parse(root.tileConfigJson || "{}")
      root.parsedConfig = value && typeof value === "object" ? value : ({})
    } catch (e) {
      console.warn("home-zone launcher: failed to parse tile config:", String(e))
      root.parsedConfig = ({})
    }
    root.refreshApps()
  }

  function refreshApps() {
    var next = []
    if (root.appLibrary) {
      try {
        var rows = root.appLibrary.sortedEntries("") || []
        if (root.configuredAppIds !== null) {
          var byId = ({})
          for (var i = 0; i < rows.length; i++) {
            var indexedRow = rows[i]
            if (indexedRow && indexedRow.entry && indexedRow.entry.id)
              byId[String(indexedRow.entry.id)] = indexedRow
          }
          for (var j = 0; j < root.configuredAppIds.length && next.length < root.maxApps; j++) {
            var selected = byId[String(root.configuredAppIds[j])]
            if (selected) next.push(selected)
          }
        } else {
          for (var k = 0; k < rows.length && next.length < root.maxApps; k++) {
            var row = rows[k]
            if (row && row.entry && row.entry.id) next.push(row)
          }
        }
      } catch (e) {
        console.warn("home-zone launcher: failed to read applications:", String(e))
      }
    }
    root.apps = next
  }

  function diagnostics() {
    return {
      tileConfigJson: root.tileConfigJson,
      hasConfiguredAppIds: root.hasConfiguredAppIds,
      configuredAppIds: root.configuredAppIds,
      renderedAppIds: root.apps.map(function(row) {
        return String(row && row.entry && row.entry.id || "")
      })
    }
  }

  onAppLibraryChanged: refreshApps()
  onTileConfigJsonChanged: loadTileConfig()
  onMaxAppsChanged: refreshApps()
  Component.onCompleted: loadTileConfig()

  Connections {
    target: root.appLibrary
    function onAppsChanged() { root.refreshApps() }
  }

  Grid {
    id: appGrid
    anchors.fill: parent
    columns: root.columns
    spacing: 8

    Repeater {
      model: root.apps

      delegate: Item {
        id: appTile
        required property var modelData
        readonly property var entry: modelData.entry
        readonly property string appId: String(entry && entry.id || "")
        readonly property string appName: root.appLibrary ? String(root.appLibrary.entryName(entry) || "") : ""
        readonly property string iconUrl: root.appLibrary ? String(root.appLibrary.iconSource(String(entry && entry.icon || "")) || "") : ""

        width: (appGrid.width - (root.columns - 1) * appGrid.spacing) / root.columns
        height: (appGrid.height - (root.rowCount - 1) * appGrid.spacing) / root.rowCount

        Rectangle {
          id: hoverBg
          anchors.fill: parent
          radius: 12
          color: appMouse.containsMouse ? Util.alpha(root.textColor, 0.16) : root.buttonColor

          Behavior on color { ColorAnimation { duration: 120 } }
        }

        Item {
          anchors.centerIn: parent
          width: 58
          height: 58

          Image {
            id: appIcon
            anchors.centerIn: parent
            width: 46
            height: 46
            source: appTile.iconUrl
            sourceSize.width: 92
            sourceSize.height: 92
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            visible: appTile.iconUrl !== ""
          }

          Text {
            anchors.fill: parent
            visible: appTile.iconUrl === ""
            text: appTile.appName.length > 0 ? appTile.appName.charAt(0).toUpperCase() : "?"
            color: root.textColor
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 34
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
        }

        MouseArea {
          id: appMouse
          anchors.fill: parent
          hoverEnabled: true
          onClicked: {
            if (root.appLibrary && appTile.appId) root.appLibrary.launch(appTile.appId, appTile.appName)
          }
        }
      }
    }
  }

  Text {
    anchors.centerIn: parent
    visible: root.apps.length === 0
    text: root.hasConfiguredAppIds ? "No applications selected" : "No applications"
    color: Util.alpha(root.textColor, 0.7)
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: 13
    font.weight: Font.Bold
  }
}
