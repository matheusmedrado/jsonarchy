.pragma library

// SVG export of a laid-out graph. Pure JS so it can be unit-tested; the
// caller passes colors as {r, g, b, a} (0..1) and the same metrics the
// on-screen renderer used, so the file matches what was on screen.

function esc(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

function hex2(v) {
  var n = Math.max(0, Math.min(255, Math.round(v * 255)))
  return (n < 16 ? "0" : "") + n.toString(16)
}

function hex(c) {
  return "#" + hex2(c.r) + hex2(c.g) + hex2(c.b)
}

function alpha(c) {
  return c.a === undefined ? 1 : c.a
}

function fill(c) {
  var a = alpha(c)
  return "fill=\"" + hex(c) + "\"" + (a < 1 ? " fill-opacity=\"" + a.toFixed(3) + "\"" : "")
}

function stroke(c) {
  var a = alpha(c)
  return "stroke=\"" + hex(c) + "\"" + (a < 1 ? " stroke-opacity=\"" + a.toFixed(3) + "\"" : "")
}

function typeColor(colors, type) {
  switch (type) {
    case "string": return colors.stringValue
    case "number": return colors.numberValue
    case "boolean": return colors.booleanValue
    case "null": return colors.nullValue
    default: return colors.text
  }
}

// layout: Model.layout() result
// opts: { colors: {background, text, key, muted, nodeBackground, nodeBorder, edge,
//                  stringValue, numberValue, booleanValue, nullValue},
//         metrics: {charWidth, rowHeight, headerHeight, paddingX, paddingY},
//         fontFamily, fontSize, captionSize, cornerRadius, padding, badgeFor }
function svg(layout, opts) {
  var pad = opts.padding
  var b = layout.bounds
  var W = Math.ceil(b.w + pad * 2)
  var H = Math.ceil(b.h + pad * 2)
  var ox = pad - b.x
  var oy = pad - b.y
  var m = opts.metrics
  var c = opts.colors
  var font = esc(opts.fontFamily)
  var horizontal = layout.direction === "LR"

  var out = []
  out.push("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
  out.push("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" + W + "\" height=\"" + H + "\" viewBox=\"0 0 " + W + " " + H + "\" font-family=\"" + font + ", monospace\" font-size=\"" + opts.fontSize + "\">")
  out.push("<rect width=\"100%\" height=\"100%\" " + fill(c.background) + "/>")

  var byId = {}
  for (var i = 0; i < layout.nodes.length; i++) byId[layout.nodes[i].id] = layout.nodes[i]

  // Edges first so nodes paint over them.
  out.push("<g fill=\"none\" " + stroke(c.edge) + " stroke-width=\"1.5\" stroke-linecap=\"round\">")
  for (var e = 0; e < layout.edges.length; e++) {
    var a = byId[layout.edges[e].from]
    var d = byId[layout.edges[e].to]
    if (!a || !d) continue
    var x1, y1, x2, y2, path
    if (horizontal) {
      x1 = a.x + a.w + ox; y1 = a.y + a.h / 2 + oy
      x2 = d.x + ox;       y2 = d.y + d.h / 2 + oy
      var mx = (x1 + x2) / 2
      path = "M" + x1 + " " + y1 + " C" + mx + " " + y1 + " " + mx + " " + y2 + " " + x2 + " " + y2
    } else {
      x1 = a.x + a.w / 2 + ox; y1 = a.y + a.h + oy
      x2 = d.x + d.w / 2 + ox; y2 = d.y + oy
      var my = (y1 + y2) / 2
      path = "M" + x1 + " " + y1 + " C" + x1 + " " + my + " " + x2 + " " + my + " " + x2 + " " + y2
    }
    out.push("<path d=\"" + path + "\"/>")
  }
  out.push("</g>")

  out.push("<defs>")
  for (var k = 0; k < layout.nodes.length; k++) {
    var r = layout.nodes[k]
    out.push("<clipPath id=\"n" + r.id + "\"><rect x=\"" + (r.x + ox) + "\" y=\"" + (r.y + oy) + "\" width=\"" + r.w + "\" height=\"" + r.h + "\"/></clipPath>")
  }
  out.push("</defs>")

  for (var n = 0; n < layout.nodes.length; n++) {
    var node = layout.nodes[n]
    var x = node.x + ox
    var y = node.y + oy
    var data = node.node
    out.push("<g clip-path=\"url(#n" + node.id + ")\">")
    out.push("<rect x=\"" + x + "\" y=\"" + y + "\" width=\"" + node.w + "\" height=\"" + node.h + "\" rx=\"" + opts.cornerRadius + "\" " + fill(c.nodeBackground) + " " + stroke(c.nodeBorder) + " stroke-width=\"1\"/>")

    var isValue = data.kind === "value"
    var titleColor = isValue ? c.muted : c.key
    var chevron = data.childIds.length > 0 ? (data.collapsed ? "› " : "⌄ ") : ""
    out.push("<text x=\"" + (x + m.paddingX) + "\" y=\"" + (y + m.headerHeight / 2) + "\" dominant-baseline=\"central\" " + fill(titleColor) + (isValue ? "" : " font-weight=\"bold\"") + ">" + esc(chevron + data.title) + "</text>")
    var badge = opts.badgeFor(data)
    if (badge) {
      out.push("<text x=\"" + (x + node.w - m.paddingX) + "\" y=\"" + (y + m.headerHeight / 2) + "\" dominant-baseline=\"central\" text-anchor=\"end\" font-size=\"" + opts.captionSize + "\" " + fill(c.muted) + ">" + esc(badge) + "</text>")
    }

    if (data.rows.length > 0) {
      out.push("<line x1=\"" + x + "\" y1=\"" + (y + m.headerHeight - 0.5) + "\" x2=\"" + (x + node.w) + "\" y2=\"" + (y + m.headerHeight - 0.5) + "\" " + stroke(c.nodeBorder) + " stroke-width=\"1\"/>")
      for (var ri = 0; ri < data.rows.length; ri++) {
        var row = data.rows[ri]
        var ry = y + m.headerHeight + m.paddingY / 2 + ri * m.rowHeight + m.rowHeight / 2
        var rx = x + m.paddingX
        if (row.key) {
          out.push("<text x=\"" + rx + "\" y=\"" + ry + "\" dominant-baseline=\"central\" " + fill(c.key) + ">" + esc(row.key + ":") + "</text>")
          rx += (row.key.length + 2) * m.charWidth
        }
        out.push("<text x=\"" + rx + "\" y=\"" + ry + "\" dominant-baseline=\"central\" " + fill(typeColor(c, row.type)) + ">" + esc(row.text) + "</text>")
      }
    }
    out.push("</g>")
  }

  out.push("</svg>")
  return out.join("\n")
}

function timestamp(date) {
  var d = date || new Date()
  function p(n) { return (n < 10 ? "0" : "") + n }
  return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) + "_" + p(d.getHours()) + "-" + p(d.getMinutes()) + "-" + p(d.getSeconds())
}
