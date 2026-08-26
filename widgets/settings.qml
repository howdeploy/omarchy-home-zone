import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Виджет «Настройки»: плитка-кнопка. Действие задаётся в конфиге
// (tile settings.action) — любая shell-команда.
Item {
  id: root

  property var shell: null
  property var appLibrary: null
  property var tileConfig: ({})
  property var tileColors: ({})

  readonly property string action: String(tileConfig.action || "omarchy-shell shell summon omarchy.menu '{}'")
  readonly property string label: String(tileConfig.label || "Настройки")
  readonly property color textColor: root.tileColors.text || "#cdd6f4"

  Process {
    id: runner
    command: ["sh", "-c", root.action]
  }

  Rectangle {
    id: hoverBg
    anchors.fill: parent
    radius: Math.min(Style.cornerRadius, 10)
    color: "transparent"
  }

  Column {
    anchors.centerIn: parent
    spacing: 5

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "\uf013" // nf-fa-gear
      color: root.textColor
      font.family: Style.font.family
      font.pixelSize: 26
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.label
      color: Util.alpha(root.textColor, 0.8)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: runner.run()
    onEntered: hoverBg.color = Util.alpha(root.textColor, 0.08)
    onExited: hoverBg.color = "transparent"
  }
}
