import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "components"

// Bar icon plus the compact popup. Left click opens JSONarchy in the
// user's preferred size (compact popup here, or the full-screen overlay);
// right click loads the clipboard first.
Panel {
  id: root
  moduleName: "io.github.matheusmedrado.jsonarchy"
  manageIpc: false

  readonly property string pluginId: "io.github.matheusmedrado.jsonarchy"
  readonly property var shellRef: bar ? bar.shell : null
  readonly property var doc: shellRef
    ? (shellRef.serviceFor(pluginId) || (typeof shellRef.ensureService === "function" ? shellRef.ensureService(pluginId) : null))
    : null

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function prefersFull() {
    return doc && doc.sizeMode === "full"
  }

  function openPreferred(payloadJson) {
    if (!doc) return
    if (prefersFull()) {
      root.close()
      if (shellRef) shellRef.summon(pluginId, payloadJson || '{"size": "full"}')
    } else {
      if (payloadJson) doc.applyPayload(payloadJson)
      else if (doc.text.length === 0) doc.loadClipboard(false)
      root.open()
    }
  }

  function togglePreferred() {
    if (prefersFull()) {
      root.close()
      if (shellRef) shellRef.toggle(pluginId, '{"size": "full"}')
    } else if (root.opened) {
      root.close()
    } else {
      openPreferred()
    }
  }

  function switchToFull() {
    if (!doc) return
    doc.sizeMode = "full"
    root.close()
    if (shellRef) shellRef.summon(pluginId, '{"size": "full"}')
  }

  // omarchy-shell jsonarchy <open|close|toggle|exportPng|exportSvg>
  IpcHandler {
    target: "jsonarchy"
    function open(): void { root.openPreferred() }
    function show(): void { root.openPreferred() }
    function close(): void { root.close() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePreferred() }
    function exportPng(): string { workspace.exportPng(); return "ok" }
    function exportSvg(): string { workspace.exportSvg(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰘦"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.openPreferred('{"clipboard": true}')
      else root.togglePreferred()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: workspace
    contentWidth: panel.fittedContentWidth(Style.space(1180))
    contentHeight: panel.cappedContentHeight(Style.space(720))

    Workspace {
      id: workspace
      anchors.fill: parent
      doc: root.doc
      active: root.opened
      compact: true
      surfaceBackground: Color.popups.background
      surfaceText: Color.popups.text
      onSizeToggleRequested: root.switchToFull()
      onCloseRequested: root.close()
    }
  }

  onOpenedChanged: if (opened) Qt.callLater(function() { workspace.focusDefault() })
}
