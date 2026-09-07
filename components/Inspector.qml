import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Floating card showing the selected node's JSON path and pretty value.
Rectangle {
  id: root

  property var theme: null
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.body
  property string path: ""
  property string body: ""
  property string kindLabel: ""

  signal closeRequested()
  signal copyRequested(string text)

  color: theme.inspectorBackground
  radius: Style.cornerRadius
  border.width: 1
  border.color: theme.nodeBorder

  MouseArea { anchors.fill: parent; onClicked: {} }

  Column {
    anchors.fill: parent
    anchors.margins: Style.spacing.lg
    spacing: Style.spacing.sm

    Item {
      width: parent.width
      height: Style.spacing.controlHeight

      Text {
        anchors.left: parent.left
        anchors.right: actions.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        text: root.path
        textFormat: Text.PlainText
        color: theme.accent
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        font.bold: true
        elide: Text.ElideLeft
      }

      Row {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

        Button {
          iconText: "󰆏"
          tooltipText: "Copy value"
          onClicked: root.copyRequested(root.body)
        }
        Button {
          iconText: "󰅖"
          tooltipText: "Close inspector"
          onClicked: root.closeRequested()
        }
      }
    }

    Text {
      width: parent.width
      text: root.kindLabel
      textFormat: Text.PlainText
      color: theme.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Flickable {
      id: flick
      width: parent.width
      height: parent.height - Style.spacing.controlHeight - Style.spacing.sm * 2 - Style.font.caption - Style.spacing.xs
      clip: true
      contentWidth: Math.max(width, bodyText.contentWidth)
      contentHeight: Math.max(height, bodyText.contentHeight)
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      TextEdit {
        id: bodyText
        width: flick.width
        text: root.body
        textFormat: TextEdit.PlainText
        readOnly: true
        selectByMouse: true
        color: theme.text
        selectionColor: theme.selection
        selectedTextColor: theme.text
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        wrapMode: TextEdit.NoWrap
      }
    }
  }
}
