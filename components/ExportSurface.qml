import QtQuick
import qs.Commons

// Off-screen copy of the graph at 1:1 world scale, used to rasterise a PNG
// with Item.grabToImage. Lives inside the visible viewport (grabToImage
// needs a window) but positioned outside its clip so it never shows.
Item {
  id: root

  property var layoutResult: null
  property var theme: null
  property var metrics: ({})
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.body
  property var badgeFor: function(node) { return "" }
  readonly property int padding: Style.space(24)
  readonly property int maxSide: 8192

  readonly property var bounds: layoutResult ? layoutResult.bounds : ({ x: 0, y: 0, w: 1, h: 1 })
  readonly property var shiftedNodes: {
    if (!layoutResult) return []
    var out = []
    for (var i = 0; i < layoutResult.nodes.length; i++) {
      var r = layoutResult.nodes[i]
      out.push({ id: r.id, x: r.x - bounds.x + padding, y: r.y - bounds.y + padding, w: r.w, h: r.h, node: r.node })
    }
    return out
  }

  width: Math.ceil(bounds.w + padding * 2)
  height: Math.ceil(bounds.h + padding * 2)
  visible: true
  x: 0
  y: 0

  property var pendingCallback: null

  // Renders, waits for the edge canvas to paint, then grabs at `scale`.
  function grab(scale, callback) {
    if (!layoutResult) { callback(null); return }
    var s = Math.min(scale, maxSide / Math.max(width, height))
    pendingCallback = function() {
      root.grabToImage(function(result) { callback(result) }, Qt.size(Math.round(width * s), Math.round(height * s)))
    }
    edges.requestPaint()
  }

  Rectangle {
    anchors.fill: parent
    color: root.theme ? root.theme.background : "black"
  }

  Canvas {
    id: edges
    anchors.fill: parent
    renderStrategy: Canvas.Cooperative

    onPainted: {
      if (!root.pendingCallback) return
      var cb = root.pendingCallback
      root.pendingCallback = null
      Qt.callLater(cb)
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      var lr = root.layoutResult
      if (!lr) return
      var byId = ({})
      for (var i = 0; i < root.shiftedNodes.length; i++) byId[root.shiftedNodes[i].id] = root.shiftedNodes[i]
      var horizontal = lr.direction === "LR"
      ctx.lineWidth = 1.5
      ctx.lineCap = "round"
      ctx.strokeStyle = root.theme.edge
      ctx.globalAlpha = 0.85
      for (var e = 0; e < lr.edges.length; e++) {
        var a = byId[lr.edges[e].from]
        var b = byId[lr.edges[e].to]
        if (!a || !b) continue
        var x1, y1, x2, y2
        if (horizontal) { x1 = a.x + a.w; y1 = a.y + a.h / 2; x2 = b.x; y2 = b.y + b.h / 2 }
        else { x1 = a.x + a.w / 2; y1 = a.y + a.h; x2 = b.x + b.w / 2; y2 = b.y }
        ctx.beginPath()
        ctx.moveTo(x1, y1)
        if (horizontal) { var mx = (x1 + x2) / 2; ctx.bezierCurveTo(mx, y1, mx, y2, x2, y2) }
        else { var my = (y1 + y2) / 2; ctx.bezierCurveTo(x1, my, x2, my, x2, y2) }
        ctx.stroke()
      }
      ctx.globalAlpha = 1
    }
  }

  Repeater {
    model: root.shiftedNodes
    delegate: GraphNode {
      required property var modelData
      rect: modelData
      x: modelData.x
      y: modelData.y
      width: modelData.w
      height: modelData.h
      theme: root.theme
      charWidth: root.metrics.charWidth
      rowHeight: root.metrics.rowHeight
      headerHeight: root.metrics.headerHeight
      paddingX: root.metrics.paddingX
      paddingY: root.metrics.paddingY
      fontFamily: root.fontFamily
      fontSize: root.fontSize
      badge: root.badgeFor(modelData.node)
    }
  }
}
