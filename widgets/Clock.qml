import QtQuick
import qs.Commons

// Виджет «Часы». Контракт виджета home-zone:
//   property var shell / appLibrary / tileConfig / tileColors
// Контекст инжектит HomeZone.qml через Loader.onLoaded.
Item {
  id: root

  property var shell: null
  property var appLibrary: null
  property var tileConfig: ({})
  property var tileColors: ({})

  readonly property string timeFmt: String(tileConfig.format || "HH:mm")
  readonly property string dateFmt: String(tileConfig.dateFormat || "dddd d MMMM")

  property string timeText: Qt.formatTime(new Date(), timeFmt)
  property string dateText: Qt.formatDate(new Date(), dateFmt)

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      root.timeText = Qt.formatTime(new Date(), root.timeFmt)
      root.dateText = Qt.formatDate(new Date(), root.dateFmt)
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 2

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.timeText
      color: root.tileColors.text || "#cdd6f4"
      font.family: Style.font.family
      font.pixelSize: Style.font.display
      style: Text.Raised
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.dateText
      color: Util.alpha(root.tileColors.text || "#cdd6f4", 0.75)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
}
