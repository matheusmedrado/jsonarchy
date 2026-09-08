import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// JSONarchy document service. One instance per shell session; both the
// compact bar panel (Panel.qml) and the full-screen overlay (Overlay.qml)
// render whatever is in here, so switching surfaces never loses the
// document, the selection or the search.
Item {
  id: doc

  property var shell: null
  property var manifest: null
  readonly property string pluginId: (manifest && manifest.id) || "io.github.matheusmedrado.jsonarchy"

  // ---- preferences (persisted) ------------------------------------------

  // "compact": popup attached to the bar icon. "full": whole-screen overlay.
  property string sizeMode: "compact"
  property string direction: "LR"
  property bool editorVisible: true
  property bool prefsLoaded: false

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy"

  FileView {
    id: stateFile
    path: doc.stateDir + "/jsonarchy.json"
    preload: false
    blockLoading: true
    printErrors: false
  }

  function loadPreferences() {
    try {
      var prefs = JSON.parse(stateFile.text() || "{}")
      if (prefs.size === "full" || prefs.size === "compact") doc.sizeMode = prefs.size
      if (prefs.direction === "LR" || prefs.direction === "TB") doc.direction = prefs.direction
      if (typeof prefs.editorVisible === "boolean") doc.editorVisible = prefs.editorVisible
    } catch (e) {}
    doc.prefsLoaded = true
  }

  function savePreferences() {
    if (!doc.prefsLoaded) return
    stateFile.setText(JSON.stringify({
      size: doc.sizeMode,
      direction: doc.direction,
      editorVisible: doc.editorVisible
    }, null, 2) + "\n")
  }

  Component.onCompleted: loadPreferences()
  onSizeModeChanged: savePreferences()
  onEditorVisibleChanged: savePreferences()
  onDirectionChanged: { savePreferences(); requestFit(); relayout() }

  // ---- document state ----------------------------------------------------

  property string text: ""            // editor contents, the source of truth
  property var graph: null
  property var layoutResult: null
  property int selectedId: -1
  property var matchedIds: []
  property int matchIndex: 0
  property string searchText: ""
  property string sourceLabel: ""
  property string parseError: ""
  property int totalNodes: 0
  property int visibleCount: 0

  // Bumped whenever a view should re-fit the graph (new document, direction
  // change, expand/collapse all). Views compare against the last serial
  // they fitted so a popup that opens later still fits once.
  property int fitSerial: 0
  // Bumped when the graph is rebuilt from text so views do not tween node
  // positions across unrelated documents.
  property int graphSerial: 0
  signal centerRequested(int id)

  readonly property var selectedNode: (graph && selectedId >= 0 && selectedId < graph.nodes.length) ? graph.nodes[selectedId] : null

  function requestFit() { doc.fitSerial = doc.fitSerial + 1 }

  // ---- font metrics (layout depends on them) -----------------------------

  readonly property string fontFamily: Style.font.family
  readonly property int fontSize: Style.font.body

  TextMetrics {
    id: glyph
    font.family: doc.fontFamily
    font.pixelSize: doc.fontSize
    text: "M"
  }

  readonly property var metrics: ({
    charWidth: Math.max(4, glyph.advanceWidth),
    rowHeight: doc.fontSize + Style.spacing.md,
    headerHeight: doc.fontSize + Style.spacing.lg + 2,
    paddingX: Style.spacing.lg,
    paddingY: Style.spacing.sm,
    minWidth: Style.space(90),
    maxWidth: Style.space(420)
  })

  onMetricsChanged: relayout()

  // ---- input limits ----------------------------------------------------------

  // Every ingestion path (file, clipboard, summon payload, editor) is capped
  // at this many bytes before anything is parsed; the editor additionally
  // refuses to display documents above maxEditorChars and shows the graph
  // only. Both are documented in the README.
  readonly property int maxInputBytes: 1024 * 1024
  readonly property int maxEditorChars: 512 * 1024
  readonly property string readerScript: String(Qt.resolvedUrl("bin/read-bounded.sh")).replace(/^file:\/\//, "")

  function tooLargeMessage(what, size) {
    return what + " is " + (size / (1024 * 1024)).toFixed(1) + " MiB; the limit is " + (maxInputBytes / (1024 * 1024)) + " MiB."
  }

  // ---- payloads ------------------------------------------------------------

  // Applies a summon payload and returns it parsed. Recognised keys:
  //   text, file, clipboard (bool), direction ("LR"|"TB"),
  //   size ("compact"|"full"), show (bool: open, never toggle).
  // Returns { payload, loaded } where loaded says whether new content was requested.
  function applyPayload(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) { payload = {} }
    var loaded = false
    if (typeof payload.text === "string") {
      if (payload.text.length > doc.maxInputBytes) doc.parseError = tooLargeMessage("Payload text", payload.text.length)
      else loadText(payload.text, "payload")
      loaded = true
    } else if (typeof payload.file === "string" && payload.file.length > 0) {
      loadFile(payload.file); loaded = true
    } else if (payload.clipboard === true) {
      loadClipboard(true); loaded = true
    } else if (doc.text.length === 0) {
      loadClipboard(false)
    }
    if (typeof payload.direction === "string") {
      doc.direction = payload.direction === "TB" ? "TB" : "LR"
    }
    return { payload: payload, loaded: loaded }
  }

  // ---- loading -------------------------------------------------------------

  function loadText(text, label) {
    doc.sourceLabel = label || ""
    doc.text = text
    reparseNow()
    requestFit()
  }

  // Desktop portal chooser via omarchy-file-select. The popup usually loses
  // focus to the dialog, so the preferred surface is re-shown afterwards.
  function openFileDialog() {
    if (filePicker.running) return
    filePicker.running = true
  }

  Process {
    id: filePicker
    command: ["omarchy-file-select", "--title", "Open JSON", "--extensions", "json jsonl geojson txt"]
    stdout: StdioCollector {
      id: filePickerOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var picked = exitCode === 0 ? String(filePickerOut.text || "").trim().split("\n")[0] : ""
      if (picked) doc.loadFile(picked)
      // Re-show the surface that was closed for the dialog, picked or cancelled.
      if (doc.shell && typeof doc.shell.summon === "function") doc.shell.summon(doc.pluginId, '{"show": true}')
    }
  }

  // Files are read by bin/read-bounded.sh in a child process: regular
  // files only, at most maxInputBytes, never a device, FIFO or directory,
  // and never on the shell's thread. A wall-clock timeout backs that up.
  function loadFile(path) {
    if (fileReadProc.running) { doc.parseError = "A file is already being read."; return }
    fileReadProc.target = path
    fileReadProc.running = true
  }

  Process {
    id: fileReadProc
    property string target: ""
    command: ["timeout", "10", "sh", doc.readerScript, target, String(doc.maxInputBytes)]
    stdout: StdioCollector { id: fileReadOut; waitForEnd: true }
    stderr: StdioCollector { id: fileReadErr; waitForEnd: true }
    onExited: function(exitCode) {
      var text = String(fileReadOut.text || "")
      var why = String(fileReadErr.text || "").trim()
      if (exitCode === 4) doc.parseError = "File is too large (" + why.replace(/^too large: /, "") + ")."
      else if (exitCode === 3) doc.parseError = "Not a regular file: " + fileReadProc.target
      else if (exitCode === 124) doc.parseError = "Timed out reading " + fileReadProc.target
      else if (exitCode === 0) doc.parseError = "File is empty: " + fileReadProc.target
      else doc.parseError = "Could not read " + fileReadProc.target + (why ? " (" + why + ")" : "")
    }
  }

  // Qt's Wayland clipboard is only readable once a surface has focus, which
  // is too late for a summon-time load, so read through wl-paste like the
  // first-party clipboard manager does.
  function loadClipboard(force) {
    if (clipboardReader.running) return
    clipboardReader.force = force
    clipboardReader.running = true
  }

  function onClipboardRead(text, force) {
    if (!text || text.trim().length === 0) {
      if (force) doc.parseError = "Clipboard is empty."
      return
    }
    if (text.length > doc.maxInputBytes) {
      if (force) doc.parseError = "Clipboard text exceeds the " + (doc.maxInputBytes / (1024 * 1024)) + " MiB limit."
      return
    }
    if (!force) {
      var probe = Model.parseText(text)
      if (!probe.ok) return
    }
    loadText(text, "clipboard")
  }


  Process {
    id: clipboardReader
    property bool force: false
    // head stops reading one byte past the limit, so an enormous clipboard
    // costs at most maxInputBytes + 1 of buffer and is then rejected.
    command: ["timeout", "10", "sh", "-c", "wl-paste --no-newline --type text | head -c \"$1\"", "sh", String(doc.maxInputBytes + 1)]
    stdout: StdioCollector {
      id: clipboardOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      doc.onClipboardRead(exitCode === 0 ? clipboardOut.text : "", clipboardReader.force)
    }
  }

  // ---- export ----------------------------------------------------------------

  readonly property string exportDir: Quickshell.env("OMARCHY_SCREENSHOT_DIR")
    || Quickshell.env("XDG_PICTURES_DIR")
    || (Quickshell.env("HOME") + "/Pictures")

  function exportPath(ext, stamp) {
    return exportDir + "/jsonarchy-" + stamp + "." + ext
  }

  FileView {
    id: exportWriter
    preload: false
    printErrors: false
  }

  function writeTextFile(path, text) {
    exportWriter.path = path
    exportWriter.setText(text)
  }

  // Announce a finished export the way screenshots do: PNG goes to the
  // clipboard too, and the notification opens the file when clicked.
  function finishExport(path, kind) {
    doc.exportNotice = "Exported " + path
    if (kind === "png") Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < \"$1\"", "sh", path])
    Quickshell.execDetached(["omarchy-notification-send", "JSONarchy exported " + kind.toUpperCase(),
      path, "-g", "󰘦", "--exec", "xdg-open", path])
    exportNoticeTimer.restart()
  }

  property string exportNotice: ""
  Timer {
    id: exportNoticeTimer
    interval: 6000
    onTriggered: doc.exportNotice = ""
  }

  // ---- parsing + layout ----------------------------------------------------

  Timer {
    id: parseDebounce
    interval: 220
    repeat: false
    onTriggered: doc.reparseNow()
  }

  // Called by the editor while the user types.
  function editText(next) {
    if (next === doc.text) return
    doc.text = next
    doc.sourceLabel = ""
    if (next.length > doc.maxInputBytes) {
      parseDebounce.stop()
      doc.parseError = tooLargeMessage("Document", next.length)
      return
    }
    parseDebounce.restart()
  }

  function reparseNow() {
    parseDebounce.stop()
    if (doc.text.length > doc.maxInputBytes) {
      doc.parseError = tooLargeMessage("Document", doc.text.length)
      return
    }
    var result = Model.parseText(doc.text)
    if (result.empty) {
      doc.parseError = ""
      doc.graph = null
      doc.layoutResult = null
      doc.selectedId = -1
      doc.matchedIds = []
      doc.totalNodes = 0
      doc.visibleCount = 0
      return
    }
    if (!result.ok) {
      doc.parseError = result.error
      return
    }
    doc.parseError = ""
    doc.graph = Model.buildGraph(result.value)
    doc.graphSerial = doc.graphSerial + 1
    doc.totalNodes = doc.graph.nodes.length
    doc.selectedId = -1
    applySearch(doc.searchText, false)
    relayout()
  }

  function relayout() {
    if (!doc.graph) return
    doc.layoutResult = Model.layout(doc.graph, {
      direction: doc.direction,
      gapMain: Style.space(56),
      gapCross: Style.space(18),
      metrics: doc.metrics
    })
    doc.visibleCount = doc.layoutResult.nodes.length
  }

  // ---- interaction ----------------------------------------------------------

  function selectNode(id) {
    doc.selectedId = (doc.selectedId === id) ? -1 : id
  }

  function toggleNode(id) {
    if (!doc.graph) return
    Model.toggleCollapsed(doc.graph, id)
    relayout()
  }

  function expandAll() {
    if (!doc.graph) return
    Model.expandAll(doc.graph)
    relayout()
    requestFit()
  }

  function collapseAll() {
    if (!doc.graph) return
    Model.collapseToDepth(doc.graph, 1)
    relayout()
    requestFit()
  }

  function toggleDirection() {
    doc.direction = doc.direction === "LR" ? "TB" : "LR"
  }

  function toggleSize() {
    doc.sizeMode = doc.sizeMode === "full" ? "compact" : "full"
  }

  function applySearch(text, jump) {
    doc.searchText = text
    if (!doc.graph) { doc.matchedIds = []; return }
    var ids = Model.search(doc.graph, text)
    doc.matchedIds = ids
    doc.matchIndex = 0
    if (jump && ids.length > 0) jumpToMatch(0)
  }

  function jumpToMatch(index) {
    if (!doc.graph || doc.matchedIds.length === 0) return
    var i = ((index % doc.matchedIds.length) + doc.matchedIds.length) % doc.matchedIds.length
    doc.matchIndex = i
    var id = doc.matchedIds[i]
    Model.reveal(doc.graph, id)
    relayout()
    doc.selectedId = id
    doc.centerRequested(id)
  }

  function nextMatch(delta) {
    jumpToMatch(doc.matchIndex + delta)
  }

  function formatDocument() {
    var pretty = Model.prettyPrint(doc.text)
    if (pretty === null) return
    doc.text = pretty
    reparseNow()
  }

  function copyToClipboard(text) {
    Quickshell.clipboardText = text
  }

  function badgeFor(node) {
    return Model.badgeFor(node)
  }

  function inspectText(node) {
    return Model.inspectText(node)
  }

  function statusLine() {
    if (doc.exportNotice) return doc.exportNotice
    if (!doc.graph) return doc.parseError ? doc.parseError : "No document"
    var parts = [doc.visibleCount + " of " + doc.totalNodes + " nodes"]
    if (doc.graph.truncated > 0) parts.push("truncated: " + doc.graph.truncated + " containers beyond the " + Model.MAX_TOTAL_NODES + " node / depth " + Model.MAX_DEPTH + " budget")
    if (doc.graph.autoCollapsedDepth >= 0) parts.push("large document, collapsed below depth " + doc.graph.autoCollapsedDepth)
    if (doc.sourceLabel) parts.push(doc.sourceLabel)
    return parts.join("  ·  ")
  }
}
