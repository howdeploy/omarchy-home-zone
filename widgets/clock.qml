import QtQuick
import qs.Commons

// CanvasTTY HomeZONE clock: one oversized, tightly tracked mono time readout.
Item {
  id: root
  anchors.fill: parent

  property var shell: null
  property var appLibrary: null
  property var tileConfig: ({})
  property var tileColors: ({})

  readonly property string timeFmt: String(tileConfig.format || "HH:mm")
  readonly property string dateFmt: String(tileConfig.dateFormat || "ddd, dd.MM.yyyy")
  readonly property string fontFamily: String(tileConfig.fontFamily || "JetBrainsMono Nerd Font")
  readonly property int timeSize: parseInt(tileConfig.timeSize || 118)
  readonly property real tracking: Number(tileConfig.letterSpacing === undefined ? -9 : tileConfig.letterSpacing)
  readonly property bool showDate: tileConfig.showDate === true
  readonly property int dateSize: parseInt(tileConfig.dateSize || 17)

  property string timeText: Qt.formatTime(new Date(), timeFmt)
  property string dateText: Qt.locale().toString(new Date(), dateFmt)

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      root.timeText = Qt.formatTime(new Date(), root.timeFmt)
      root.dateText = Qt.locale().toString(new Date(), root.dateFmt)
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 8

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.timeText
      color: root.tileColors.text || Color.bar.text
      font.family: root.fontFamily
      font.pixelSize: root.timeSize
      font.weight: Font.Black
      font.letterSpacing: root.tracking
    }

    Text {
      visible: root.showDate
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.dateText
      color: Util.alpha(root.tileColors.text || Color.bar.text, 0.8)
      font.family: root.fontFamily
      font.pixelSize: root.dateSize
      font.weight: Font.Medium
    }
  }
}
