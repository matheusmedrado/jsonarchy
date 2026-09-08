import QtQuick
import QtQuick.Controls
import qs.Commons
import "Highlight.js" as Highlight

// Plain-text JSON editor with a status line. Deliberately simple: no
// syntax highlighting in v1, just monospace text, theme colors and a
// parse error readout.
Item {
  id: root

  property var theme: null
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.body
  property string statusText: ""
  property bool statusIsError: false
  property alias text: area.text
  property alias textArea: area
  // Syntax palette (see Highlight.paletteSpec) or null for plain text.
  property var syntax: null
  // Only the lines in view are highlighted, so the cost of the styled
  // overlay scales with the viewport rather than the document.
  property string highlightHtml: ""
  property real highlightY: 0
  readonly property bool highlighting: syntax !== null && highlightHtml.length > 0
  readonly property int maxSliceChars: 40000

  // Shown instead of the placeholder when the document is not editable here.
  property string notice: ""

  signal textEdited()
  signal fileDropped(string path)

  function setText(next) {
    area.text = next
    area.cursorPosition = 0
  }

  function focusEditor() {
    area.forceActiveFocus()
  }

  onSyntaxChanged: scheduleHighlight()

  Timer {
    id: highlightTimer
    interval: 16
    repeat: false
    onTriggered: root.updateHighlight()
  }

  function scheduleHighlight() {
    if (!root.syntax) return
    highlightTimer.restart()
  }

  function updateHighlight() {
    if (!root.syntax || area.text.length === 0) { root.highlightHtml = ""; return }
    var text = area.text
    var top = flick.contentY
    var bottom = top + flick.height
    var firstPos = area.positionAt(0, Math.max(0, top - area.topPadding) + area.topPadding)
    var lastPos = area.positionAt(area.width, bottom + area.topPadding)
    var start = text.lastIndexOf("\n", Math.max(0, firstPos - 1)) + 1
    var end = text.indexOf("\n", lastPos)
    if (end < 0) end = text.length
    if (end - start > root.maxSliceChars) { root.highlightHtml = ""; return }
    var html = Highlight.highlight(text.slice(start, end), root.syntax)
    if (html === null) { root.highlightHtml = ""; return }
    root.highlightY = area.positionToRectangle(start).y
    root.highlightHtml = html
  }

  Rectangle {
    anchors.fill: parent
    color: theme.editorBackground
    radius: Style.cornerRadius
    border.width: 1
    border.color: theme.nodeBorder
  }

  Flickable {
    id: flick
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: status.top
    anchors.margins: 1
    anchors.bottomMargin: 0
    clip: true
    contentWidth: Math.max(width, area.contentWidth + Style.spacing.md * 2)
    contentHeight: Math.max(height, area.contentHeight + Style.spacing.md * 2)
    boundsBehavior: Flickable.StopAtBounds

    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    function ensureVisible(r) {
      if (contentX >= r.x) contentX = r.x
      else if (contentX + width <= r.x + r.width) contentX = r.x + r.width - width
      if (contentY >= r.y) contentY = r.y
      else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
    }

    // Colored copy of the visible lines, drawn underneath the (transparent)
    // editor at exactly the same glyph positions.
    Text {
      id: highlightLayer
      visible: root.highlighting
      x: area.leftPadding
      y: root.highlightY
      text: root.highlightHtml
      textFormat: Text.StyledText
      color: theme.text
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      wrapMode: Text.NoWrap
      lineHeight: area.lineCount > 0 ? area.contentHeight / area.lineCount : root.fontSize * 1.3
      lineHeightMode: Text.FixedHeight
    }

    onContentYChanged: root.scheduleHighlight()
    onHeightChanged: root.scheduleHighlight()

    TextEdit {
      id: area
      width: Math.max(flick.width, contentWidth + Style.spacing.md * 2)
      height: Math.max(flick.height, contentHeight + Style.spacing.md * 2)
      padding: Style.spacing.md
      color: root.highlighting ? "transparent" : theme.text
      cursorDelegate: Rectangle {
        width: 2
        color: theme.accent
        visible: area.activeFocus
        SequentialAnimation on opacity {
          loops: Animation.Infinite
          running: area.activeFocus
          NumberAnimation { to: 0; duration: 500 }
          NumberAnimation { to: 1; duration: 500 }
        }
      }
      selectionColor: theme.selection
      selectedTextColor: theme.text
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      wrapMode: TextEdit.NoWrap
      selectByMouse: true
      readOnly: root.notice !== ""
      persistentSelection: false
      textFormat: TextEdit.PlainText
      tabStopDistance: root.fontSize * 2
      onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)
      onTextChanged: { root.textEdited(); root.scheduleHighlight() }

      Text {
        visible: area.text.length === 0
        anchors.fill: parent
        anchors.margins: Style.spacing.md
        text: root.notice !== "" ? root.notice : "Paste JSON here.\n\nCtrl+Shift+V loads the clipboard."
        textFormat: Text.PlainText
        color: theme.muted
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        wrapMode: Text.Wrap
      }
    }
  }

  DropArea {
    anchors.fill: parent
    onDropped: function(drop) {
      if (!drop.hasUrls || drop.urls.length === 0) return
      var url = String(drop.urls[0])
      if (url.indexOf("file://") === 0) {
        root.fileDropped(decodeURIComponent(url.slice(7)))
        drop.accept()
      }
    }
  }

  Rectangle {
    id: status
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 1
    height: statusLabel.implicitHeight + Style.spacing.sm * 2
    color: root.statusIsError ? theme.errorBackground : "transparent"
    radius: Style.cornerRadius

    Rectangle {
      anchors.top: parent.top
      width: parent.width
      height: 1
      color: theme.nodeBorder
    }

    Text {
      id: statusLabel
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.md
      anchors.rightMargin: Style.spacing.md
      text: root.statusText
      textFormat: Text.PlainText
      color: root.statusIsError ? theme.error : theme.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      maximumLineCount: 2
      wrapMode: Text.Wrap
    }
  }
}
