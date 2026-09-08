import QtQuick
import qs.Commons
import qs.Ui
import "Highlight.js" as Highlight
import "Export.js" as Export

// The JSONarchy UI: header, editor, graph, inspector and a footer with the
// key hints. Rendered inside either the bar popup (compact) or the overlay
// (full). All state lives in `doc` (Service.qml); this item only owns view
// state such as zoom and pan.
FocusScope {
  id: root

  property var doc: null
  property bool compact: false
  // The hosting surface sets this while it is shown. A hidden surface
  // freezes its editor and graph and catches up when it becomes active,
  // so only one copy of the document is ever rebuilt per change.
  property bool active: true
  property bool layoutDirty: false
  property bool textDirty: false
  property color surfaceBackground: Color.menu.background
  property color surfaceText: Color.menu.text

  signal sizeToggleRequested()
  signal closeRequested()

  readonly property bool ready: doc !== null
  readonly property string fontFamily: doc ? doc.fontFamily : Style.font.family
  readonly property int fontSize: doc ? doc.fontSize : Style.font.body
  readonly property bool editorVisible: doc ? doc.editorVisible : true
  readonly property bool typing: searchField.activeFocus || editor.textArea.activeFocus

  // Touch every input of statusLine() so the binding re-evaluates.
  readonly property string statusText: {
    if (!doc) return ""
    var deps = [doc.parseError, doc.graph, doc.visibleCount, doc.totalNodes, doc.sourceLabel, doc.exportNotice]
    return doc.statusLine()
  }

  // ---- export ---------------------------------------------------------------

  function rgba(c) { return { r: c.r, g: c.g, b: c.b, a: c.a } }

  function exportSvg() {
    if (!doc || !doc.layoutResult) return
    var t = root.theme
    var text = Export.svg(doc.layoutResult, {
      colors: {
        background: rgba(t.background), text: rgba(t.text), key: rgba(t.key), muted: rgba(t.muted),
        nodeBackground: rgba(t.nodeBackground), nodeBorder: rgba(t.nodeBorder), edge: rgba(t.edge),
        stringValue: rgba(t.stringValue), numberValue: rgba(t.numberValue),
        booleanValue: rgba(t.booleanValue), nullValue: rgba(t.nullValue)
      },
      metrics: doc.metrics,
      fontFamily: root.fontFamily,
      fontSize: root.fontSize,
      captionSize: Style.font.caption,
      cornerRadius: Style.cornerRadius,
      padding: Style.space(24),
      badgeFor: function(node) { return doc.badgeFor(node) }
    })
    var path = doc.exportPath("svg", Export.timestamp())
    doc.writeTextFile(path, text)
    doc.finishExport(path, "svg")
  }

  function exportPng() {
    if (!doc || !doc.layoutResult) return
    var path = doc.exportPath("png", Export.timestamp())
    exportLoader.active = true
    Qt.callLater(function() {
      if (!exportLoader.item) { exportLoader.active = false; return }
      exportLoader.item.grab(2, function(result) {
        if (result && result.saveToFile(path)) doc.finishExport(path, "png")
        exportLoader.active = false
      })
    })
  }

  // Vivid type colors: Omarchy themes are muted by design, but the editor
  // and node values need distinct hues to be readable at a glance.
  readonly property bool darkSurface: (0.2126 * surfaceBackground.r + 0.7152 * surfaceBackground.g + 0.0722 * surfaceBackground.b) < 0.5
  readonly property real accentHue: Color.accent.hslSaturation < 0.15 ? -1 : Color.accent.hslHue
  readonly property var syntaxSpec: Highlight.paletteSpec(accentHue, darkSurface)
  readonly property var syntax: ({
    key: String(Qt.hsla(syntaxSpec.key.h, syntaxSpec.key.s, syntaxSpec.key.l, 1)),
    string: String(Qt.hsla(syntaxSpec.string.h, syntaxSpec.string.s, syntaxSpec.string.l, 1)),
    number: String(Qt.hsla(syntaxSpec.number.h, syntaxSpec.number.s, syntaxSpec.number.l, 1)),
    boolean: String(Qt.hsla(syntaxSpec.boolean.h, syntaxSpec.boolean.s, syntaxSpec.boolean.l, 1)),
    nul: String(Qt.hsla(syntaxSpec.nul.h, syntaxSpec.nul.s, syntaxSpec.nul.l, 1)),
    punct: String(Qt.hsla(syntaxSpec.punct.h, syntaxSpec.punct.s, syntaxSpec.punct.l, 1)),
    error: String(Qt.hsla(syntaxSpec.error.h, syntaxSpec.error.s, syntaxSpec.error.l, 1))
  })
  property bool helpVisible: false

  readonly property QtObject theme: QtObject {
    readonly property color background: root.surfaceBackground
    readonly property color text: root.surfaceText
    readonly property color accent: Color.accent
    readonly property color muted: Color.muted
    readonly property color error: Color.urgent
    readonly property color errorBackground: Util.alpha(Color.urgent, 0.12)
    readonly property color key: root.surfaceText
    readonly property color stringValue: root.syntax.string
    readonly property color numberValue: root.syntax.number
    readonly property color booleanValue: root.syntax.boolean
    readonly property color nullValue: root.syntax.nul
    readonly property color nodeBackground: Util.alpha(root.surfaceText, 0.04)
    readonly property color nodeSelectedBackground: Util.alpha(Color.accent, 0.14)
    readonly property color nodeBorder: Util.alpha(root.surfaceText, 0.24)
    readonly property color nodeHoverBackground: Util.alpha(root.surfaceText, 0.08)
    readonly property color nodeHoverBorder: Util.alpha(root.surfaceText, 0.45)
    readonly property color matchBorder: Color.accent
    readonly property color edge: Util.alpha(root.surfaceText, 0.45)
    readonly property color editorBackground: Util.alpha(root.surfaceText, 0.03)
    readonly property color inspectorBackground: root.surfaceBackground
    readonly property color selection: Style.selectionFill
  }

  // ---- doc <-> view sync ----------------------------------------------------

  property int fittedSerial: -1

  function syncEditor() {
    if (!doc) return
    textDirty = false
    if (doc.text.length > doc.maxEditorChars) {
      // Too big for a TextEdit to lay out comfortably: graph only.
      editor.notice = "Document is " + (doc.text.length / (1024 * 1024)).toFixed(1) + " MiB, above the " + (doc.maxEditorChars / (1024 * 1024)) + " MiB editor limit. The graph is still available."
      if (editor.text !== "") editor.setText("")
      return
    }
    editor.notice = ""
    if (editor.text !== doc.text) editor.setText(doc.text)
  }

  function pushLayout() {
    if (!doc) return
    layoutDirty = false
    graphView.graphSerial = doc.graphSerial
    graphView.layoutResult = doc.layoutResult
  }

  property int fittedGraphSerial: -1

  function syncFit() {
    if (!active || !doc || !doc.layoutResult) return
    if (fittedSerial === doc.fitSerial) return
    fittedSerial = doc.fitSerial
    var sameDocument = fittedGraphSerial === doc.graphSerial
    fittedGraphSerial = doc.graphSerial
    graphView.fitToView(sameDocument)
  }

  // The portal chooser needs the keyboard, and both surfaces hold it while
  // open. Close, and let the service re-show us once the dialog is answered.
  function openFile() {
    if (!doc) return
    doc.openFileDialog()
    root.closeRequested()
  }

  function focusDefault() {
    if (!doc || doc.text.length === 0) editor.focusEditor()
    else graphView.forceActiveFocus()
  }

  Connections {
    target: root.doc
    function onTextChanged() { if (root.active) root.syncEditor(); else root.textDirty = true }
    function onLayoutResultChanged() {
      if (root.active) { root.pushLayout(); Qt.callLater(root.syncFit) } else root.layoutDirty = true
    }
    function onFitSerialChanged() { Qt.callLater(root.syncFit) }
    function onCenterRequested(id) { if (root.active) Qt.callLater(function() { graphView.centerOn(id) }) }
    function onSearchTextChanged() { if (searchField.text !== root.doc.searchText) searchField.text = root.doc.searchText }
  }

  onDocChanged: { if (active) { syncEditor(); pushLayout() } else { textDirty = true; layoutDirty = true }; Qt.callLater(syncFit) }
  onActiveChanged: {
    if (!active) return
    if (textDirty) syncEditor()
    if (layoutDirty) pushLayout()
    Qt.callLater(syncFit)
  }
  Component.onCompleted: { if (active) { syncEditor(); pushLayout() } else { textDirty = true; layoutDirty = true }; Qt.callLater(syncFit) }

  // ---- keys -----------------------------------------------------------------

  Keys.onPressed: function(event) {
    if (!doc) return
    var ctrl = event.modifiers & Qt.ControlModifier
    var shift = event.modifiers & Qt.ShiftModifier

    if (event.key === Qt.Key_Escape) {
      if (root.helpVisible) root.helpVisible = false
      else if (searchField.activeFocus && doc.searchText.length > 0) { searchField.text = ""; doc.applySearch("", false) }
      else if (doc.selectedId >= 0) doc.selectedId = -1
      else root.closeRequested()
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_F11 || (ctrl && event.key === Qt.Key_M)) { root.sizeToggleRequested(); event.accepted = true; return }
    if (event.key === Qt.Key_F1) { root.helpVisible = !root.helpVisible; event.accepted = true; return }
    if (ctrl && event.key === Qt.Key_O) { root.openFile(); event.accepted = true; return }
    // Shift combos first: they would otherwise be swallowed by the plain
    // Ctrl handlers below.
    if (ctrl && shift && event.key === Qt.Key_V) { doc.loadClipboard(true); event.accepted = true; return }
    if (ctrl && shift && event.key === Qt.Key_S) { root.exportSvg(); event.accepted = true; return }
    if (ctrl && event.key === Qt.Key_S) { root.exportPng(); event.accepted = true; return }
    if (ctrl && shift && event.key === Qt.Key_F) { doc.formatDocument(); event.accepted = true; return }
    if (ctrl && shift && event.key === Qt.Key_E) { doc.expandAll(); event.accepted = true; return }
    if (ctrl && shift && event.key === Qt.Key_C) { doc.collapseAll(); event.accepted = true; return }
    if (ctrl && event.key === Qt.Key_F) { searchField.forceActiveFocus(); searchField.selectAll(); event.accepted = true; return }
    if (ctrl && event.key === Qt.Key_E) { doc.editorVisible = !doc.editorVisible; event.accepted = true; return }
    if (ctrl && event.key === Qt.Key_L) { doc.toggleDirection(); event.accepted = true; return }
    if (ctrl && event.key === Qt.Key_0) { graphView.fitToView(); event.accepted = true; return }
    if (ctrl && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)) { graphView.zoomStep(1); event.accepted = true; return }
    if (ctrl && event.key === Qt.Key_Minus) { graphView.zoomStep(-1); event.accepted = true; return }

    if (root.typing) return

    var step = Style.space(80)
    switch (event.key) {
      case Qt.Key_Plus: case Qt.Key_Equal: graphView.zoomStep(1); break
      case Qt.Key_Minus: graphView.zoomStep(-1); break
      case Qt.Key_F: case Qt.Key_0: graphView.fitToView(); break
      case Qt.Key_L: doc.toggleDirection(); break
      case Qt.Key_E: doc.editorVisible = !doc.editorVisible; break
      case Qt.Key_Slash: searchField.forceActiveFocus(); searchField.selectAll(); break
      case Qt.Key_Question: root.helpVisible = !root.helpVisible; break
      case Qt.Key_N: if (doc.matchedIds.length > 0) doc.nextMatch(shift ? -1 : 1); break
      case Qt.Key_Left: case Qt.Key_H: graphView.panBy(step, 0); break
      case Qt.Key_Right: graphView.panBy(-step, 0); break
      case Qt.Key_Up: case Qt.Key_K: graphView.panBy(0, step); break
      case Qt.Key_Down: case Qt.Key_J: graphView.panBy(0, -step); break
      case Qt.Key_Space: if (doc.selectedId >= 0) doc.toggleNode(doc.selectedId); break
      default: return
    }
    event.accepted = true
  }

  // ---- layout ---------------------------------------------------------------

  Column {
    anchors.fill: parent
    spacing: Style.spacing.md

    // Header
    Item {
      id: header
      width: parent.width
      height: Style.spacing.controlHeight + Style.spacing.xs

      Row {
        id: headerLeft
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.md

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰘦"
          color: root.theme.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.iconLarge
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "JSONarchy"
          textFormat: Text.PlainText
          color: root.theme.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          visible: !root.compact || header.width > Style.space(720)
        }
      }

      TextField {
        id: searchField
        anchors.left: headerLeft.right
        anchors.leftMargin: Style.spacing.huge
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Style.space(160), Math.min(Style.space(380), headerRight.x - headerLeft.width - loadButtons.width - Style.spacing.huge * 2 - Style.spacing.sm))
        placeholderText: "Search…  (Ctrl+F)"
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        onTextChanged: if (root.doc && text !== root.doc.searchText) root.doc.applySearch(text, true)
        Keys.onReturnPressed: function(event) { root.doc.nextMatch((event.modifiers & Qt.ShiftModifier) ? -1 : 1); event.accepted = true }
        Keys.onEnterPressed: function(event) { root.doc.nextMatch(1); event.accepted = true }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          visible: root.doc && root.doc.searchText.length > 0
          text: !root.doc || root.doc.matchedIds.length === 0 ? "0" : (root.doc.matchIndex + 1) + "/" + root.doc.matchedIds.length
          textFormat: Text.PlainText
          color: root.theme.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: loadButtons
        anchors.left: searchField.right
        anchors.leftMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.sm

        Rectangle {
          width: 1
          height: Style.spacing.controlHeight - Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          color: Util.alpha(root.theme.text, 0.14)
        }

        Button {
          iconText: "󰝰"
          tooltipText: "Open file (Ctrl+O)"
          onClicked: root.openFile()
        }
        Button {
          iconText: "󰅇"
          tooltipText: "Load clipboard (Ctrl+Shift+V)"
          onClicked: root.doc.loadClipboard(true)
        }
      }

      Row {
        id: headerRight
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.sm

        // Document
        Button {
          iconText: "󰉶"
          tooltipText: "Format JSON (Ctrl+Shift+F)"
          onClicked: root.doc.formatDocument()
        }
        Button {
          iconText: "󰷈"
          tooltipText: root.editorVisible ? "Hide editor (Ctrl+E)" : "Show editor (Ctrl+E)"
          active: root.editorVisible
          onClicked: root.doc.editorVisible = !root.doc.editorVisible
        }
        Rectangle {
          width: 1
          height: Style.spacing.controlHeight - Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          color: Util.alpha(root.theme.text, 0.14)
        }

        // Graph
        Button {
          text: root.doc ? root.doc.direction : "LR"
          iconText: root.doc && root.doc.direction === "TB" ? "󰜮" : "󰜴"
          tooltipText: "Toggle layout direction (Ctrl+L)"
          onClicked: root.doc.toggleDirection()
        }
        Button {
          iconText: "󰊓"
          tooltipText: "Fit to view (Ctrl+0)"
          onClicked: graphView.fitToView()
        }
        Button {
          iconText: "󰐕"
          tooltipText: "Expand all (Ctrl+Shift+E)"
          onClicked: root.doc.expandAll()
        }
        Button {
          iconText: "󰍴"
          tooltipText: "Collapse all (Ctrl+Shift+C)"
          onClicked: root.doc.collapseAll()
        }
        Rectangle {
          width: 1
          height: Style.spacing.controlHeight - Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          color: Util.alpha(root.theme.text, 0.14)
        }

        // Export
        Button {
          text: "PNG"
          tooltipText: "Export graph as PNG (Ctrl+S)"
          onClicked: root.exportPng()
        }
        Button {
          text: "SVG"
          tooltipText: "Export graph as SVG (Ctrl+Shift+S)"
          onClicked: root.exportSvg()
        }
        Rectangle {
          width: 1
          height: Style.spacing.controlHeight - Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          color: Util.alpha(root.theme.text, 0.14)
        }

        // Window
        Button {
          iconText: root.compact ? "󰖯" : "󰖰"
          tooltipText: root.compact ? "Full screen (F11)" : "Compact window (F11)"
          onClicked: root.sizeToggleRequested()
        }
        Button {
          text: "?"
          tooltipText: "All keys and commands (?)"
          active: root.helpVisible
          onClicked: root.helpVisible = !root.helpVisible
        }
      }
    }

    // Body
    Item {
      id: body
      width: parent.width
      height: parent.height - header.height - footer.height - Style.spacing.md * 2

      EditorPane {
        id: editor
        visible: width > 0
        clip: true
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.editorVisible ? Math.max(Style.space(240), Math.round(parent.width * (root.compact ? 0.32 : 0.3))) : 0
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        theme: root.theme
        fontFamily: root.fontFamily
        fontSize: root.fontSize
        statusText: root.doc ? root.doc.parseError : ""
        statusIsError: root.doc ? root.doc.parseError.length > 0 : false
        syntax: root.syntax
        onTextEdited: if (root.doc && editor.notice === "") root.doc.editText(editor.text)
        onFileDropped: function(path) { if (root.doc) root.doc.loadFile(path) }
      }

      Item {
        id: graphArea
        anchors.left: editor.right
        anchors.leftMargin: root.editorVisible ? Style.spacing.md : 0
        Behavior on anchors.leftMargin { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        Rectangle {
          anchors.fill: parent
          color: "transparent"
          radius: Style.cornerRadius
          border.width: 1
          border.color: root.theme.nodeBorder
        }

        GraphView {
          id: graphView
          anchors.fill: parent
          anchors.margins: 1
          theme: root.theme
          metrics: root.doc ? root.doc.metrics : ({})
          fontFamily: root.fontFamily
          fontSize: root.fontSize
          selectedId: root.doc ? root.doc.selectedId : -1
          matchedIds: root.doc ? root.doc.matchedIds : []
          badgeFor: function(node) { return root.doc ? root.doc.badgeFor(node) : "" }
          onNodeActivated: function(id) { root.doc.selectNode(id); graphView.forceActiveFocus() }
          onToggleRequested: function(id) { root.doc.toggleNode(id) }
          onBackgroundClicked: { root.doc.selectedId = -1; graphView.forceActiveFocus() }
        }

        // The export surface only exists while a PNG is being produced;
        // keeping it alive would rebuild every node on each relayout.
        // grabToImage renders into its own buffer regardless of ancestor
        // clipping, so this 1x1 clipped box keeps it off the screen.
        Item {
          width: 1
          height: 1
          clip: true

          Loader {
            id: exportLoader
            active: false
            sourceComponent: ExportSurface {
              layoutResult: root.doc ? root.doc.layoutResult : null
              theme: root.theme
              metrics: root.doc ? root.doc.metrics : ({})
              fontFamily: root.fontFamily
              fontSize: root.fontSize
              badgeFor: function(node) { return root.doc ? root.doc.badgeFor(node) : "" }
            }
          }
        }

        // Empty state
        Column {
          anchors.centerIn: parent
          spacing: Style.spacing.md
          visible: !root.doc || !root.doc.layoutResult
          width: Math.min(parent.width - Style.spacing.huge * 2, Style.space(420))

          Text {
            width: parent.width
            text: "󰘦"
            color: root.theme.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            horizontalAlignment: Text.AlignHCenter
          }
          Text {
            width: parent.width
            text: root.doc && root.doc.parseError.length > 0
              ? root.doc.parseError
              : "Paste JSON into the editor, load the clipboard with Ctrl+Shift+V, or summon with a file."
            textFormat: Text.PlainText
            color: root.doc && root.doc.parseError.length > 0 ? root.theme.error : root.theme.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
          }
        }

        Inspector {
          readonly property bool shown: root.doc && root.doc.selectedNode !== null
          visible: opacity > 0
          opacity: shown ? 1 : 0
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.spacing.lg
          anchors.bottomMargin: shown ? Style.spacing.lg : Style.spacing.lg - Style.space(12)
          Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          Behavior on anchors.bottomMargin { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          width: Math.min(Style.space(420), parent.width * 0.45)
          height: Math.min(Style.space(360), parent.height * 0.6)
          theme: root.theme
          fontFamily: root.fontFamily
          fontSize: root.fontSize
          path: root.doc && root.doc.selectedNode ? root.doc.selectedNode.path : ""
          body: root.doc && root.doc.selectedNode ? root.doc.inspectText(root.doc.selectedNode) : ""
          kindLabel: root.doc && root.doc.selectedNode
            ? (root.doc.selectedNode.kind + (root.doc.selectedNode.kind === "value" ? "" : " · " + root.doc.selectedNode.count + " members") + " · depth " + root.doc.selectedNode.depth)
            : ""
          onCloseRequested: root.doc.selectedId = -1
          onCopyRequested: function(text) { root.doc.copyToClipboard(text) }
        }
      }
    }

    // Footer: key hints on the left, document status on the right.
    Item {
      id: footer
      width: parent.width
      height: Style.font.caption + Style.spacing.md

      Text {
        id: hints
        anchors.left: parent.left
        anchors.right: status.left
        anchors.rightMargin: Style.spacing.huge
        anchors.verticalCenter: parent.verticalCenter
        text: [
          "Esc close",
          root.compact ? "F11 full screen" : "F11 compact",
          "Ctrl+O open",
          "Ctrl+F search",
          "? all keys"
        ].join("   ·   ")
        textFormat: Text.PlainText
        color: root.theme.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      // Zoom readout is its own fixed-width item so per-frame zoom changes
      // never re-layout the footer.
      Text {
        id: zoomText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(40)
        horizontalAlignment: Text.AlignRight
        visible: root.doc && root.doc.layoutResult
        text: Math.round(graphView.zoom * 100) + "%"
        textFormat: Text.PlainText
        color: root.theme.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        id: status
        anchors.right: zoomText.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        text: root.statusText
        textFormat: Text.PlainText
        color: root.doc && root.doc.parseError.length > 0 ? root.theme.error : root.theme.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideLeft
        width: Math.min(implicitWidth, footer.width * 0.5)
      }
    }
  }

  // ---- help ----------------------------------------------------------------

  readonly property var helpSections: [
    { title: "Window", rows: [
      ["Esc", "Close help, clear search, deselect, then close"],
      ["F11 / Ctrl+M", root.compact ? "Full screen" : "Compact popup"],
      ["? / F1", "This help"],
      ["Ctrl+E / e", "Show or hide the editor"]
    ]},
    { title: "Document", rows: [
      ["Ctrl+O", "Open a JSON file"],
      ["Ctrl+Shift+V", "Load the clipboard"],
      ["Ctrl+Shift+F", "Format (pretty-print)"],
      ["Drop a file", "Load it into the editor"],
      ["Ctrl+S / Ctrl+Shift+S", "Export the graph as PNG (also copied) / SVG"]
    ]},
    { title: "Graph", rows: [
      ["Ctrl+F or /", "Search keys and values"],
      ["Enter / Shift+Enter, n / N", "Next / previous match"],
      ["Ctrl+L / l", "Toggle left-to-right / top-to-bottom"],
      ["Ctrl+0 / f", "Fit graph to view"],
      ["+ / -, pinch, mouse wheel, Ctrl+scroll", "Zoom"],
      ["Two-finger scroll, drag, arrows, h j k l", "Pan (Shift+wheel pans sideways)"],
      ["Click node", "Inspect path and value"],
      ["Double-click, middle-click, Space", "Collapse or expand a node"],
      ["Ctrl+Shift+E / Ctrl+Shift+C", "Expand all / collapse all"]
    ]},
    { title: "Commands", rows: [
      ["omarchy-shell jsonarchy toggle", "Toggle the popup"],
      ["omarchy-shell jsonarchy exportPng | exportSvg", "Export from a script"],
      ["omarchy-shell shell summon io.github.matheusmedrado.jsonarchy '{\"file\": \"/path.json\"}'", "Open a file"],
      ["… '{\"clipboard\": true}'", "Load the clipboard"],
      ["… '{\"text\": \"…\", \"size\": \"full\"}'", "Pass text, force a size"]
    ]}
  ]

  MouseArea {
    anchors.fill: parent
    visible: root.helpVisible
    onClicked: root.helpVisible = false
    onWheel: function(wheel) { wheel.accepted = true }
  }

  Rectangle {
    id: helpCard
    visible: opacity > 0
    opacity: root.helpVisible ? 1 : 0
    scale: root.helpVisible ? 1 : 0.96
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.spacing.huge * 2, Style.space(640))
    height: Math.min(parent.height - Style.spacing.huge * 2, helpColumn.implicitHeight + Style.spacing.panelPadding * 2)
    radius: Style.cornerRadius
    color: root.theme.background
    border.width: 1
    border.color: root.theme.accent

    MouseArea { anchors.fill: parent; onClicked: {} }

    Flickable {
      anchors.fill: parent
      anchors.margins: Style.spacing.panelPadding
      contentHeight: helpColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: helpColumn
        width: parent.width
        spacing: Style.spacing.lg

        Text {
          text: "JSONarchy keys and commands"
          textFormat: Text.PlainText
          color: root.theme.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Repeater {
          model: root.helpSections

          delegate: Column {
            required property var modelData
            width: helpColumn.width
            spacing: Style.spacing.xs

            Text {
              text: modelData.title
              textFormat: Text.PlainText
              color: root.theme.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Repeater {
              model: modelData.rows

              delegate: Item {
                required property var modelData
                width: helpColumn.width
                height: Math.max(keyText.implicitHeight, actionText.implicitHeight) + Style.spacing.xxs

                Text {
                  id: keyText
                  width: Math.round(parent.width * 0.46)
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData[0]
                  textFormat: Text.PlainText
                  color: root.syntax.key
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WrapAnywhere
                }
                Text {
                  id: actionText
                  anchors.left: keyText.right
                  anchors.leftMargin: Style.spacing.lg
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData[1]
                  textFormat: Text.PlainText
                  color: root.theme.text
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.Wrap
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          text: "Press Esc or ? to close"
          textFormat: Text.PlainText
          color: root.theme.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
