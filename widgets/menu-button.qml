import QtQuick
import qs.Commons

// Отдельная кнопка системного меню Omarchy. Она намеренно не совмещена с
// Home Zone Settings: у двух действий разные владельцы и разные окна.
Item {
  id: root
  anchors.fill: parent

  property var shell: null
  property var appLibrary: null
  property var tileConfig: ({})
  property var tileColors: ({})

  readonly property string label: String(tileConfig.label || "Menu")
  readonly property bool showLabel: tileConfig.showLabel === true
  readonly property color textColor: root.tileColors.text || Color.foreground

  function activate() {
    if (root.shell && typeof root.shell.summon === "function") {
      if (root.shell.summon("omarchy.menu", '{"menu":"root"}')) return
    }
    Util.execDetached("omarchy-shell shell summon omarchy.menu '{}'")
  }

  Rectangle {
    anchors.fill: parent
    radius: 20
    color: menuMouse.containsMouse ? Util.alpha(root.textColor, 0.08) : "transparent"

    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Column {
    anchors.centerIn: parent
    spacing: 7

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "\ue900" // Omarchy launcher glyph, same as the upstream bar button
      color: root.textColor
      font.family: "omarchy"
      font.pixelSize: 48
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.showLabel
      text: root.label
      color: root.textColor
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 12
      font.weight: Font.Bold
    }
  }

  MouseArea {
    id: menuMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activate()
  }
}
