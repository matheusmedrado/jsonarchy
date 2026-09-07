import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "components"

// Full-screen surface. Summon payloads land here first; when the user's
// preferred size is the compact popup and the payload does not ask for
// full screen, the request is handed to the bar panel instead.
//
//   omarchy-shell shell toggle io.github.matheusmedrado.jsonarchy '{}'
//   omarchy-shell shell summon io.github.matheusmedrado.jsonarchy '{"clipboard": true}'
//   omarchy-shell shell summon io.github.matheusmedrado.jsonarchy '{"file": "/path/to/data.json"}'
//   omarchy-shell shell summon io.github.matheusmedrado.jsonarchy '{"text": "{\"a\": 1}", "size": "full"}'
Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: (manifest && manifest.id) || "io.github.matheusmedrado.jsonarchy"
  readonly property var doc: shell
    ? (shell.serviceFor(pluginId) || (typeof shell.ensureService === "function" ? shell.ensureService(pluginId) : null))
    : null

  property bool opened: false

  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

  function barPanel() {
    if (!shell || !shell.bar || typeof shell.bar.findPanelWidget !== "function") return null
    return shell.bar.findPanelWidget(pluginId)
  }

  function open(payloadJson) {
    if (!doc) { root.opened = true; return }
    var result = doc.applyPayload(payloadJson)
    var size = result.payload.size
    var wantFull = size === "full" || (size !== "compact" && doc.sizeMode === "full")

    if (!wantFull) {
      var panel = barPanel()
      if (panel) {
        root.hideSelf()
        if (result.loaded || result.payload.show === true || !panel.opened) panel.open()
        else panel.close()
        return
      }
    }

    root.opened = true
    Qt.callLater(function() { workspace.focusDefault() })
  }

  function close() {
    root.opened = false
  }

  function hideSelf() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function dismiss() {
    hideSelf()
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function switchToCompact() {
    if (doc) doc.sizeMode = "compact"
    var panel = barPanel()
    hideSelf()
    if (panel) panel.open()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-jsonarchy"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: panel.width - Style.spacing.huge * 2
      height: panel.height - Style.spacing.huge * 2
      radius: Style.cornerRadius
      anchors.centerIn: parent
      // Entrance: the window maps instantly; the card settles in.
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.985
      Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      color: Color.menu.background
      borderSpec: root.borderSpec
      padding: Style.spacing.popupPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Workspace {
        id: workspace
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        focus: true
        doc: root.doc
        active: root.opened
        compact: false
        surfaceBackground: Color.menu.background
        surfaceText: Color.menu.text
        onSizeToggleRequested: root.switchToCompact()
        onCloseRequested: root.dismiss()
      }
    }
  }
}
