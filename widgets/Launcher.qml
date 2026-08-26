import QtQuick
import qs.Commons

// Виджет «Лаунчер»: сетка приложений из AppLibrary (та же база, что у меню omarchy).
// Клик по плитке — запуск приложения.
Item {
  id: root

  property var shell: null
  property var appLibrary: null
  property var tileConfig: ({})
  property var tileColors: ({})

  readonly property int columns: Math.max(1, parseInt(tileConfig.columns || 4))
  readonly property int maxApps: Math.max(1, parseInt(tileConfig.maxApps || 12))
  readonly property var rows: root.appLibrary ? root.appLibrary.sortedEntries("") : []
  readonly property var apps: rows.slice(0, maxApps)
  readonly property color textColor: root.tileColors.text || "#cdd6f4"
  readonly property color bgColor: root.tileColors.background || "#313244"

  Grid {
    anchors.fill: parent
    columns: root.columns
    spacing: Math.max(4, root.height / 24)

    Repeater {
      model: root.apps

      delegate: Item {
        required property var modelData
        readonly property var entry: modelData.entry
        readonly property string appId: String(entry && entry.id || "")
        readonly property string appName: root.appLibrary ? root.appLibrary.entryName(entry) : ""
        readonly property string iconUrl: root.appLibrary ? root.appLibrary.iconSource(String(entry && entry.icon || "")) : ""

        width: (parent.width - (root.columns - 1) * parent.spacing) / root.columns
        height: width

        Rectangle {
          id: hoverBg
          anchors.fill: parent
          radius: Math.min(Style.cornerRadius, 10)
          color: "transparent"
        }

        Column {
          anchors.centerIn: parent
          spacing: 3

          Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(32, parent.parent.width * 0.45)
            height: width

            Image {
              id: appIcon
              anchors.fill: parent
              source: root.iconUrl
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              fillMode: Image.PreserveAspectFit
              visible: root.iconUrl !== ""
            }

            Text {
              anchors.fill: parent
              visible: root.iconUrl === ""
              text: root.appName.length > 0 ? root.appName.charAt(0).toUpperCase() : "?"
              color: root.textColor
              font.family: Style.font.family
              font.pixelSize: height * 0.6
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.appName
            color: root.textColor
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            maximumLineCount: 1
            width: parent.parent.width
            horizontalAlignment: Text.AlignHCenter
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onClicked: {
            if (root.appLibrary && root.appId) root.appLibrary.launch(root.appId, root.appName)
          }
          onEntered: hoverBg.color = Util.alpha(root.textColor, 0.08)
          onExited: hoverBg.color = "transparent"
        }
      }
    }
  }
}
