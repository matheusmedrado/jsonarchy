import QtQuick
import qs.Commons

// One graph node: a header (chevron + title + count badge) and the
// primitive rows. Deliberately few items: the header is two Text items and
// all rows are a single StyledText, so a 2000-node document stays cheap to
// create and to render.
Rectangle {
  id: root

  required property var rect          // { id, x, y, w, h, node } from Model.layout
  property var theme: null            // see Workspace.theme
  property real charWidth: 7
  property int rowHeight: 18
  property int headerHeight: 24
  property int paddingX: 10
  property int paddingY: 6
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.body
  property bool selected: false
  property bool matched: false
  property bool dimmed: false
  property string badge: ""
  // 0..1 while a freshly revealed node grows out of its parent.
  property real appearProgress: 1
  readonly property bool hovered: hoverArea.containsMouse
  property real dimOpacity: dimmed ? 0.3 : 1

  signal activated(int id)
  signal toggleRequested(int id)

  readonly property var node: rect.node
  readonly property bool hasChildren: node.childIds.length > 0

  radius: Style.cornerRadius
  color: selected ? theme.nodeSelectedBackground : (hovered ? theme.nodeHoverBackground : theme.nodeBackground)
  border.width: selected || matched ? 2 : 1
  border.color: selected ? theme.accent : (matched ? theme.matchBorder : (hovered ? theme.nodeHoverBorder : theme.nodeBorder))
  opacity: dimOpacity * appearProgress
  scale: 0.7 + 0.3 * appearProgress
  transformOrigin: Item.Center
  antialiasing: true

  Behavior on dimOpacity { NumberAnimation { duration: 140 } }
  Behavior on color { ColorAnimation { duration: 120 } }
  Behavior on border.color { ColorAnimation { duration: 120 } }

  function hex(c) {
    // Opaque hex for StyledText <font color>; theme type colors are opaque.
    return "#" + Math.round(c.r * 255).toString(16).padStart(2, "0")
      + Math.round(c.g * 255).toString(16).padStart(2, "0")
      + Math.round(c.b * 255).toString(16).padStart(2, "0")
  }

  function escapeText(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/ /g, "&nbsp;")
  }

  function typeColor(type) {
    switch (type) {
      case "string": return theme.stringValue
      case "number": return theme.numberValue
      case "boolean": return theme.booleanValue
      case "null": return theme.nullValue
      default: return theme.text
    }
  }

  // All rows as one StyledText: "<key>: <value>" per line.
  readonly property string rowsHtml: {
    var rows = node.rows
    if (!rows || rows.length === 0) return ""
    var keyColor = hex(theme.key)
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var line = ""
      if (row.key) line += "<font color=\"" + keyColor + "\">" + escapeText(row.key + ":") + "</font>&nbsp;"
      line += "<font color=\"" + hex(typeColor(row.type)) + "\">" + escapeText(row.text) + "</font>"
      out.push(line)
    }
    return out.join("<br>")
  }

  // Header: chevron + title in one Text, badge in another.
  Text {
    id: title
    x: root.paddingX
    y: 0
    width: parent.width - root.paddingX * 2 - badgeText.width - Style.spacing.xs
    height: root.headerHeight
    verticalAlignment: Text.AlignVCenter
    text: (root.hasChildren ? (root.node.collapsed ? "󰅂 " : "󰅀 ") : "") + root.node.title
    textFormat: Text.PlainText
    color: root.node.kind === "value" ? theme.muted : theme.key
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: root.node.kind !== "value"
    elide: Text.ElideMiddle
  }

  Text {
    id: badgeText
    anchors.right: parent.right
    anchors.rightMargin: root.paddingX
    y: 0
    height: root.headerHeight
    verticalAlignment: Text.AlignVCenter
    text: root.badge
    textFormat: Text.PlainText
    color: theme.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Rectangle {
    visible: root.node.rows.length > 0
    x: 0
    y: root.headerHeight - 1
    width: parent.width
    height: 1
    color: root.selected ? theme.accent : theme.nodeBorder
    opacity: 0.6
  }

  Text {
    visible: root.rowsHtml.length > 0
    x: root.paddingX
    y: root.headerHeight + root.paddingY / 2
    width: parent.width - root.paddingX * 2
    height: parent.height - root.headerHeight - root.paddingY
    clip: true
    text: root.rowsHtml
    textFormat: Text.StyledText
    lineHeight: root.rowHeight
    lineHeightMode: Text.FixedHeight
    verticalAlignment: Text.AlignTop
    color: theme.text
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    wrapMode: Text.NoWrap
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.MiddleButton) root.toggleRequested(root.node.id)
      else if (root.hasChildren && mouse.x < root.paddingX + root.fontSize * 1.4 && mouse.y < root.headerHeight) root.toggleRequested(root.node.id)
      else root.activated(root.node.id)
    }
    onDoubleClicked: function(mouse) {
      if (mouse.button === Qt.LeftButton) root.toggleRequested(root.node.id)
    }
  }
}
