import QtQuick
import qs.Commons

// CanvasTTY HomeZONE clock: one oversized, tightly tracked mono time readout.
Item {
  id: root
  anchors.fill: parent
  clip: true

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

  Item {
    id: content
    anchors.fill: parent
    anchors.margins: Math.max(6, Math.min(root.width, root.height) * 0.06)
    readonly property real dateGap: root.showDate ? Math.min(8, height * 0.04) : 0

    Text {
      id: timeLabel
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: root.showDate
        ? Math.max(0, parent.height - dateLabel.height - parent.dateGap)
        : parent.height
      text: root.timeText
      color: root.tileColors.text || Color.bar.text
      font.family: root.fontFamily
      font.pixelSize: root.timeSize
      font.weight: Font.Black
      font.letterSpacing: root.tracking
      fontSizeMode: Text.Fit
      minimumPixelSize: Math.max(1, Math.min(12, root.timeSize))
      wrapMode: Text.NoWrap
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }

    Text {
      id: dateLabel
      visible: root.showDate
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: visible ? Math.min(root.dateSize * 1.6, parent.height * 0.25) : 0
      text: root.dateText
      color: Util.alpha(root.tileColors.text || Color.bar.text, 0.8)
      font.family: root.fontFamily
      font.pixelSize: root.dateSize
      font.weight: Font.Medium
      fontSizeMode: Text.Fit
      minimumPixelSize: Math.max(1, Math.min(9, root.dateSize))
      wrapMode: Text.NoWrap
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
  }
}
