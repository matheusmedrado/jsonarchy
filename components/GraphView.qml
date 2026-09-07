import QtQuick
import QtQuick.Shapes
import qs.Commons

// Pannable, zoomable viewport for a laid-out graph. Nodes and edges both
// live in `world` (translated + scaled), so panning and zooming are pure
// scene-graph transforms: no JavaScript runs per frame. Edges are
// QtQuick.Shapes paths drawn with the curve renderer, so they stay smooth
// at every zoom level.
//
// Motion:
//  - Zoom and pan driven by wheel, keys, fit and centre ease over ~180ms.
//    Drag, trackpad scroll and pinch stay direct so the graph tracks the
//    fingers.
//  - Relayouts (collapse, expand, direction, search reveal) animate: every
//    node moves from its previous rectangle to its new one, and nodes that
//    just appeared grow out of their parent. Edges follow the same tween.
Item {
  id: root

  property var layoutResult: null     // Model.layout(...) output
  property int graphSerial: 0         // bumps when the document is rebuilt: no tween across documents
  property var theme: null
  property var metrics: ({})          // { charWidth, rowHeight, headerHeight, paddingX, paddingY }
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.body
  property int selectedId: -1
  property var matchedIds: []         // array of ids; empty means no active search
  property var badgeFor: function(node) { return "" }

  property real zoom: 1
  property real panX: 0
  property real panY: 0
  readonly property real minZoom: 0.15
  readonly property real maxZoom: 3

  // True while a programmatic (eased) view change is being applied.
  property bool eased: false
  readonly property int viewDuration: 180
  readonly property int layoutDuration: 260

  signal nodeActivated(int id)
  signal toggleRequested(int id)
  signal backgroundClicked()

  readonly property var matchedSet: {
    var set = ({})
    for (var i = 0; i < matchedIds.length; i++) set[matchedIds[i]] = true
    return set
  }
  readonly property bool searching: matchedIds.length > 0

  clip: true

  Behavior on zoom { enabled: root.eased; NumberAnimation { duration: root.viewDuration; easing.type: Easing.OutCubic } }
  Behavior on panX { enabled: root.eased; NumberAnimation { duration: root.viewDuration; easing.type: Easing.OutCubic } }
  Behavior on panY { enabled: root.eased; NumberAnimation { duration: root.viewDuration; easing.type: Easing.OutCubic } }

  // ---- view -----------------------------------------------------------------

  function clampZoom(z) {
    return Math.min(maxZoom, Math.max(minZoom, z))
  }

  function setView(z, x, y, animated) {
    root.eased = animated === true
    root.zoom = z
    root.panX = x
    root.panY = y
    root.eased = false
  }

  function zoomAt(factor, cx, cy, animated) {
    var next = clampZoom(zoom * factor)
    var ratio = next / zoom
    setView(next, cx - (cx - panX) * ratio, cy - (cy - panY) * ratio, animated)
  }

  function zoomStep(direction) {
    zoomAt(direction > 0 ? 1.25 : 1 / 1.25, width / 2, height / 2, true)
  }

  function panBy(dx, dy, animated) {
    setView(zoom, panX + dx, panY + dy, animated)
  }

  // A fit requested while the window is hidden (0x0) is deferred until the
  // viewport has a real size.
  property bool fitPending: false

  function fitToView(animated) {
    if (!layoutResult || layoutResult.nodes.length === 0) return
    if (width <= 0 || height <= 0) { fitPending = true; return }
    fitPending = false
    var b = layoutResult.bounds
    var margin = Style.spacing.panelPadding * 2
    var z = clampZoom(Math.min((width - margin) / Math.max(1, b.w), (height - margin) / Math.max(1, b.h), 1.25))
    setView(z, (width - b.w * z) / 2 - b.x * z, (height - b.h * z) / 2 - b.y * z, animated !== false)
  }

  function centerOn(id) {
    var r = positions[id]
    if (!r) return
    setView(zoom, width / 2 - (r.x + r.w / 2) * zoom, height / 2 - (r.y + r.h / 2) * zoom, true)
  }

  // ---- layout tween ----------------------------------------------------------

  property var positions: ({})      // id -> target rect for the current layout
  property var prevPositions: ({})  // id -> rect the tween starts from
  property var newIds: ({})         // ids that did not exist in the previous layout
  property real progress: 1

  NumberAnimation {
    id: progressAnimation
    target: root
    property: "progress"
    from: 0
    to: 1
    duration: root.layoutDuration
    easing.type: Easing.OutCubic
  }

  ListModel { id: nodeModel }
  ListModel { id: edgeModel }

  // Scalar tween helper: no per-frame object allocation.
  function mix(a, b, t) {
    return t >= 1 ? b : a + (b - a) * t
  }

  onLayoutResultChanged: syncLayout()
  onGraphSerialChanged: {
    progressAnimation.stop()
    root.positions = ({})
    root.prevPositions = ({})
    root.newIds = ({})
    nodeModel.clear()
    edgeModel.clear()
  }

  function syncLayout() {
    var lr = root.layoutResult
    var next = ({})
    var prev = ({})
    var fresh = ({})
    var rects = lr ? lr.nodes : []
    var hadPositions = Object.keys(positions).length > 0

    for (var i = 0; i < rects.length; i++) next[rects[i].id] = rects[i]

    // Starting rectangles: where the node was, or its nearest visible
    // ancestor's old spot so it appears to grow out of the parent.
    for (var j = 0; j < rects.length; j++) {
      var r = rects[j]
      var was = positions[r.id]
      if (was) { prev[r.id] = was; continue }
      fresh[r.id] = true
      var ancestor = r.node.parentId
      var origin = null
      while (ancestor >= 0 && !origin) {
        origin = positions[ancestor] || null
        if (!origin) {
          var up = next[ancestor]
          ancestor = up ? up.node.parentId : -1
        }
      }
      prev[r.id] = origin ? { x: origin.x + origin.w / 2 - r.w / 2, y: origin.y + origin.h / 2 - r.h / 2, w: r.w, h: r.h } : r
    }

    // Keep delegates for nodes that survive so they animate instead of
    // being recreated; drop the ones that left, append the newcomers.
    var present = ({})
    for (var k = nodeModel.count - 1; k >= 0; k--) {
      var id = nodeModel.get(k).nodeId
      if (next[id]) present[id] = true
      else nodeModel.remove(k)
    }
    for (var m = 0; m < rects.length; m++) {
      if (!present[rects[m].id]) nodeModel.append({ nodeId: rects[m].id })
    }

    var edgeList = lr ? lr.edges : []
    var wanted = ({})
    for (var w = 0; w < edgeList.length; w++) wanted[edgeList[w].to] = edgeList[w].from
    var haveEdge = ({})
    for (var q = edgeModel.count - 1; q >= 0; q--) {
      var row = edgeModel.get(q)
      if (wanted[row.toId] === row.fromId) haveEdge[row.toId] = true
      else edgeModel.remove(q)
    }
    for (var v = 0; v < edgeList.length; v++) {
      if (!haveEdge[edgeList[v].to]) edgeModel.append({ fromId: edgeList[v].from, toId: edgeList[v].to })
    }

    root.prevPositions = prev
    root.newIds = fresh
    root.positions = next

    if (!hadPositions || rects.length === 0) {
      progressAnimation.stop()
      root.progress = 1
    } else {
      progressAnimation.restart()
    }
  }

  onWidthChanged: if (fitPending && width > 0 && height > 0) fitToView(false)
  onHeightChanged: if (fitPending && width > 0 && height > 0) fitToView(false)

  // ---- input ----------------------------------------------------------------

  MouseArea {
    id: pad
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.ArrowCursor

    property real startX: 0
    property real startY: 0
    property real startPanX: 0
    property real startPanY: 0
    property bool moved: false

    onPressed: function(mouse) {
      startX = mouse.x; startY = mouse.y
      startPanX = root.panX; startPanY = root.panY
      moved = false
    }
    onPositionChanged: function(mouse) {
      if (!pressed) return
      var dx = mouse.x - startX
      var dy = mouse.y - startY
      if (Math.abs(dx) + Math.abs(dy) > 2) moved = true
      root.setView(root.zoom, startPanX + dx, startPanY + dy, false)
    }
    onClicked: function(mouse) {
      if (!moved) root.backgroundClicked()
    }
    // Trackpads deliver pixelDelta (two-finger scroll): pan, or zoom with
    // Ctrl. Mouse wheels only carry angleDelta: zoom, or pan sideways with
    // Shift. Pinch is handled by the PinchHandler below.
    onWheel: function(wheel) {
      var ctrl = wheel.modifiers & Qt.ControlModifier
      var shift = wheel.modifiers & Qt.ShiftModifier
      var trackpad = wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0
      if (trackpad) {
        if (ctrl) root.zoomAt(Math.pow(1.01, wheel.pixelDelta.y), wheel.x, wheel.y, false)
        else root.panBy(wheel.pixelDelta.x, wheel.pixelDelta.y, false)
      } else {
        var delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
        if (shift) root.panBy(delta, 0, true)
        else if (ctrl || wheel.angleDelta.y !== 0) root.zoomAt(Math.pow(1.0022, delta), wheel.x, wheel.y, true)
        else root.panBy(delta, 0, true)
      }
      wheel.accepted = true
    }
  }

  // Touchpad pinch (native zoom gesture) and touch-screen pinch.
  PinchHandler {
    id: pinch
    target: null
    property real lastScale: 1
    onActiveChanged: lastScale = 1
    onActiveScaleChanged: {
      if (!active) return
      var factor = activeScale / lastScale
      lastScale = activeScale
      root.zoomAt(factor, centroid.position.x, centroid.position.y, false)
    }
  }

  // ---- nodes ----------------------------------------------------------------

  Item {
    id: world
    x: root.panX
    y: root.panY
    scale: root.zoom
    transformOrigin: Item.TopLeft

    // Edges: one Shape per edge, endpoints tweened with the same progress
    // as the nodes. Stroke width is in world units so it scales with zoom
    // like everything else.
    Repeater {
      model: edgeModel

      delegate: Shape {
        required property int fromId
        required property int toId
        readonly property var a1: root.positions[fromId]
        readonly property var b1: root.positions[toId]
        readonly property var a0: root.prevPositions[fromId] || a1
        readonly property var b0: root.prevPositions[toId] || b1
        readonly property bool horizontal: root.layoutResult ? root.layoutResult.direction === "LR" : true
        readonly property bool highlighted: toId === root.selectedId || fromId === root.selectedId
        readonly property bool dim: root.searching && !(root.matchedSet[toId] || root.matchedSet[fromId])
        readonly property bool fresh: root.newIds[toId] === true

        readonly property real x1: !a1 ? 0 : root.mix(horizontal ? a0.x + a0.w : a0.x + a0.w / 2, horizontal ? a1.x + a1.w : a1.x + a1.w / 2, root.progress)
        readonly property real y1: !a1 ? 0 : root.mix(horizontal ? a0.y + a0.h / 2 : a0.y + a0.h, horizontal ? a1.y + a1.h / 2 : a1.y + a1.h, root.progress)
        readonly property real x2: !b1 ? 0 : root.mix(horizontal ? b0.x : b0.x + b0.w / 2, horizontal ? b1.x : b1.x + b1.w / 2, root.progress)
        readonly property real y2: !b1 ? 0 : root.mix(horizontal ? b0.y + b0.h / 2 : b0.y, horizontal ? b1.y + b1.h / 2 : b1.y, root.progress)

        visible: a1 !== undefined && b1 !== undefined
        opacity: (dim ? 0.25 : (highlighted ? 1 : 0.85)) * (fresh ? root.progress : 1)
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true

        ShapePath {
          strokeColor: highlighted ? root.theme.accent : root.theme.edge
          strokeWidth: 1.5
          fillColor: "transparent"
          capStyle: ShapePath.RoundCap
          startX: x1
          startY: y1
          PathCubic {
            x: x2
            y: y2
            control1X: horizontal ? (x1 + x2) / 2 : x1
            control1Y: horizontal ? y1 : (y1 + y2) / 2
            control2X: horizontal ? (x1 + x2) / 2 : x2
            control2Y: horizontal ? y2 : (y1 + y2) / 2
          }
        }
      }
    }

    // Nodes are incubated asynchronously so a large document streams in
    // over a few frames instead of freezing the shell while every item is
    // created at once.
    Repeater {
      model: nodeModel

      delegate: Loader {
        id: holder
        required property int nodeId
        readonly property var target: root.positions[nodeId]
        readonly property var start: root.prevPositions[nodeId] || target
        readonly property bool fresh: root.newIds[nodeId] === true

        asynchronous: true
        visible: target !== undefined && target !== null && status === Loader.Ready
        x: target ? root.mix(start.x, target.x, root.progress) : 0
        y: target ? root.mix(start.y, target.y, root.progress) : 0
        width: target ? root.mix(start.w, target.w, root.progress) : 1
        height: target ? root.mix(start.h, target.h, root.progress) : 1

        sourceComponent: GraphNode {
          rect: holder.target || ({ id: holder.nodeId, x: 0, y: 0, w: 1, h: 1, node: { title: "", kind: "value", rows: [], childIds: [], collapsed: false, id: holder.nodeId } })
          width: holder.width
          height: holder.height
          appearProgress: holder.fresh ? root.progress : 1
          theme: root.theme
          charWidth: root.metrics.charWidth
          rowHeight: root.metrics.rowHeight
          headerHeight: root.metrics.headerHeight
          paddingX: root.metrics.paddingX
          paddingY: root.metrics.paddingY
          fontFamily: root.fontFamily
          fontSize: root.fontSize
          selected: holder.nodeId === root.selectedId
          matched: root.matchedSet[holder.nodeId] === true
          dimmed: root.searching && root.matchedSet[holder.nodeId] !== true
          badge: holder.target ? root.badgeFor(holder.target.node) : ""
          onActivated: function(id) { root.nodeActivated(id) }
          onToggleRequested: function(id) { root.toggleRequested(id) }
        }
      }
    }
  }
}
