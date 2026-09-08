.pragma library

// JSONarchy graph model.
//
// Pure JS, no QML dependencies, so it can be unit-tested with node
// (see tests/model.test.js). Everything the overlay renders comes from
// here: parse text -> build a node tree -> lay it out -> hand back
// absolute rectangles and edges.
//
// Semantics follow JSON Crack: every object and array becomes a node.
// Primitive members render as rows inside their parent node; object and
// array members become child nodes joined to the parent by an edge.

var MAX_VISIBLE_NODES = 2500
// Hard budgets for the graph itself. Beyond these, containers are shown as
// a single "{…}" / "[…]" row and graph.truncated reports how many were cut,
// so a pathological document can never make the builder recurse without
// bound or allocate without limit.
var MAX_TOTAL_NODES = 20000
var MAX_DEPTH = 200
var VALUE_MAX_CHARS = 48
var KEY_MAX_CHARS = 32
var INSPECT_MAX_CHARS = 20000

function typeOf(v) {
  if (v === null) return "null"
  if (Array.isArray(v)) return "array"
  return typeof v
}

function isContainer(v) {
  var t = typeOf(v)
  return t === "object" || t === "array"
}

function truncate(text, max) {
  if (text.length <= max) return text
  return text.slice(0, Math.max(0, max - 1)) + "…"
}

function formatValue(v, type) {
  switch (type) {
    case "string": return JSON.stringify(v)
    case "null": return "null"
    case "boolean": return v ? "true" : "false"
    case "number": return String(v)
    default: return String(v)
  }
}

// $.users[2]["first name"] style paths.
function pathSegment(key, isIndex) {
  if (isIndex) return "[" + key + "]"
  if (/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(key)) return "." + key
  return "[" + JSON.stringify(key) + "]"
}

function parseText(text) {
  var trimmed = (text || "").trim()
  if (trimmed.length === 0) return { ok: false, empty: true, error: "" }
  try {
    return { ok: true, value: JSON.parse(trimmed) }
  } catch (e) {
    return { ok: false, empty: false, error: describeParseError(e, trimmed) }
  }
}

// V8/QtJS error messages already carry the position, but they're wordy.
// Strip the "JSON.parse:" prefix some engines add.
function describeParseError(e, text) {
  var msg = String(e && e.message ? e.message : e)
  msg = msg.replace(/^JSON\.parse:\s*/i, "")
  return msg
}

function buildGraph(value) {
  var nodes = []
  var byId = {}
  var truncated = 0

  function overBudget(depth) {
    return nodes.length >= MAX_TOTAL_NODES || depth >= MAX_DEPTH
  }

  function placeholderRow(childTitle, child) {
    truncated += 1
    return { key: childTitle, text: Array.isArray(child) ? "[…]" : "{…}", type: "truncated" }
  }

  function makeNode(key, title, path, parentId, depth, kind, v) {
    var node = {
      id: nodes.length,
      key: key,
      title: title,
      path: path,
      parentId: parentId,
      depth: depth,
      kind: kind,
      value: v,
      rows: [],
      childIds: [],
      count: 0,
      collapsed: false,
      searchText: ""
    }
    nodes.push(node)
    byId[node.id] = node
    return node
  }

  function visit(v, key, title, path, parentId, depth, isIndex) {
    var type = typeOf(v)
    var searchParts = [String(title).toLowerCase()]

    if (!isContainer(v)) {
      var leaf = makeNode(key, title, path, parentId, depth, "value", v)
      leaf.rows.push({ key: "", text: truncate(formatValue(v, type), VALUE_MAX_CHARS), type: type })
      searchParts.push(formatValue(v, type).toLowerCase())
      leaf.searchText = searchParts.join("\n")
      return leaf.id
    }

    var node = makeNode(key, title, path, parentId, depth, type, v)
    var keys = type === "array" ? null : Object.keys(v)
    var length = type === "array" ? v.length : keys.length
    node.count = length

    for (var i = 0; i < length; i++) {
      var childKey = type === "array" ? i : keys[i]
      var child = type === "array" ? v[i] : v[childKey]
      var childIsIndex = type === "array"
      var childTitle = childIsIndex ? "[" + childKey + "]" : String(childKey)
      var childPath = path + pathSegment(childKey, childIsIndex)
      var childType = typeOf(child)

      if (isContainer(child)) {
        if (overBudget(depth + 1)) {
          node.rows.push(placeholderRow(truncate(childTitle, KEY_MAX_CHARS), child))
          continue
        }
        node.childIds.push(visit(child, childKey, childTitle, childPath, node.id, depth + 1, childIsIndex))
      } else {
        var full = formatValue(child, childType)
        node.rows.push({
          key: truncate(childTitle, KEY_MAX_CHARS),
          text: truncate(full, VALUE_MAX_CHARS),
          type: childType
        })
        searchParts.push(childTitle.toLowerCase())
        searchParts.push(full.toLowerCase())
      }
    }

    node.searchText = searchParts.join("\n")
    return node.id
  }

  visit(value, "", "root", "$", -1, 0, false)
  var graph = { nodes: nodes, rootId: 0, truncated: truncated }
  autoCollapse(graph)
  return graph
}

// Huge documents would drown the renderer. Collapse the deepest layers
// until the visible set fits the budget; the user can still expand by hand.
function autoCollapse(graph) {
  var nodes = graph.nodes
  graph.autoCollapsedDepth = -1
  if (nodes.length <= MAX_VISIBLE_NODES) return

  var perDepth = []
  for (var i = 0; i < nodes.length; i++) {
    var d = nodes[i].depth
    perDepth[d] = (perDepth[d] || 0) + 1
  }
  var running = 0
  var cutoff = 0
  for (var depth = 0; depth < perDepth.length; depth++) {
    running += perDepth[depth] || 0
    if (running > MAX_VISIBLE_NODES) break
    cutoff = depth
  }
  cutoff = Math.max(0, cutoff)
  for (var j = 0; j < nodes.length; j++) {
    if (nodes[j].depth === cutoff && nodes[j].childIds.length > 0) nodes[j].collapsed = true
  }
  graph.autoCollapsedDepth = cutoff
}

function nodeById(graph, id) {
  return graph.nodes[id]
}

function setCollapsed(graph, id, collapsed) {
  var node = graph.nodes[id]
  if (!node || node.childIds.length === 0) return
  node.collapsed = collapsed
}

function toggleCollapsed(graph, id) {
  var node = graph.nodes[id]
  if (!node || node.childIds.length === 0) return
  node.collapsed = !node.collapsed
}

function expandAll(graph) {
  for (var i = 0; i < graph.nodes.length; i++) graph.nodes[i].collapsed = false
}

function collapseToDepth(graph, depth) {
  for (var i = 0; i < graph.nodes.length; i++) {
    var n = graph.nodes[i]
    n.collapsed = n.childIds.length > 0 && n.depth >= depth
  }
}

// Expand every ancestor so `id` becomes visible.
function reveal(graph, id) {
  var node = graph.nodes[id]
  while (node && node.parentId >= 0) {
    node = graph.nodes[node.parentId]
    node.collapsed = false
  }
}

function visibleNodes(graph) {
  var out = []
  if (!graph || graph.nodes.length === 0) return out
  var stack = [graph.rootId]
  while (stack.length > 0) {
    var node = graph.nodes[stack.pop()]
    out.push(node)
    if (node.collapsed) continue
    for (var i = node.childIds.length - 1; i >= 0; i--) stack.push(node.childIds[i])
  }
  return out
}

// Measure a node in pixels. `metrics` is what the overlay knows about its
// font: average glyph advance, row height, header height and padding.
function measureNode(node, metrics) {
  var longest = node.title.length + 6 // room for the "{12}" badge
  for (var i = 0; i < node.rows.length; i++) {
    var row = node.rows[i]
    var len = row.text.length + (row.key ? row.key.length + 2 : 0)
    if (len > longest) longest = len
  }
  // +2 glyphs of slack: TextMetrics' advance for "M" undershoots the run
  // width of quoted strings by a hair, and Text.elide triggers on any
  // fractional overflow.
  var width = Math.round((longest + 2) * metrics.charWidth + metrics.paddingX * 2)
  width = Math.min(metrics.maxWidth, Math.max(metrics.minWidth, width))
  var height = metrics.headerHeight
  if (node.rows.length > 0) height += node.rows.length * metrics.rowHeight + metrics.paddingY
  return { w: width, h: Math.round(height) }
}

// Layered tree layout. Depth runs along the main axis (x for "LR",
// y for "TB"); siblings stack along the cross axis. Parents are centred
// on their children but never pulled back over an earlier sibling's
// subtree, so nothing overlaps.
//
// Returns { nodes: [{id, x, y, w, h, node}], edges: [{from, to}], bounds }.
function layout(graph, options) {
  var direction = options.direction === "TB" ? "TB" : "LR"
  var gapMain = options.gapMain
  var gapCross = options.gapCross
  var metrics = options.metrics

  var visible = visibleNodes(graph)
  var placed = {}
  var columnSize = []

  for (var i = 0; i < visible.length; i++) {
    var n = visible[i]
    var size = measureNode(n, metrics)
    var main = direction === "LR" ? size.w : size.h
    var cross = direction === "LR" ? size.h : size.w
    placed[n.id] = { id: n.id, node: n, w: size.w, h: size.h, main: 0, cross: 0, mainSize: main, crossSize: cross }
    if (!columnSize[n.depth] || columnSize[n.depth] < main) columnSize[n.depth] = main
  }

  var columnOffset = []
  var acc = 0
  for (var d = 0; d < columnSize.length; d++) {
    columnOffset[d] = acc
    acc += (columnSize[d] || 0) + gapMain
  }

  var cursor = 0

  function visibleChildren(node) {
    if (node.collapsed) return []
    var out = []
    for (var c = 0; c < node.childIds.length; c++) {
      var id = node.childIds[c]
      if (placed[id]) out.push(placed[id])
    }
    return out
  }

  function shiftSubtree(item, delta) {
    item.cross += delta
    var kids = visibleChildren(item.node)
    for (var k = 0; k < kids.length; k++) shiftSubtree(kids[k], delta)
  }

  function place(item) {
    item.main = columnOffset[item.node.depth]
    var kids = visibleChildren(item.node)
    if (kids.length === 0) {
      item.cross = cursor
      cursor += item.crossSize + gapCross
      return
    }
    var start = cursor
    for (var k = 0; k < kids.length; k++) place(kids[k])
    var first = kids[0]
    var last = kids[kids.length - 1]
    var mid = (first.cross + first.crossSize / 2 + last.cross + last.crossSize / 2) / 2
    item.cross = mid - item.crossSize / 2
    if (item.cross < start) {
      var delta = start - item.cross
      for (var s = 0; s < kids.length; s++) shiftSubtree(kids[s], delta)
      item.cross = start
    }
    var bottom = item.cross + item.crossSize + gapCross
    if (bottom > cursor) cursor = bottom
  }

  if (placed[graph.rootId]) place(placed[graph.rootId])

  var out = []
  var edges = []
  var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  for (var j = 0; j < visible.length; j++) {
    var p = placed[visible[j].id]
    var x = direction === "LR" ? p.main : p.cross
    var y = direction === "LR" ? p.cross : p.main
    var rect = { id: p.id, x: Math.round(x), y: Math.round(y), w: p.w, h: p.h, node: p.node }
    out.push(rect)
    if (rect.x < minX) minX = rect.x
    if (rect.y < minY) minY = rect.y
    if (rect.x + rect.w > maxX) maxX = rect.x + rect.w
    if (rect.y + rect.h > maxY) maxY = rect.y + rect.h
    if (p.node.parentId >= 0 && placed[p.node.parentId]) edges.push({ from: p.node.parentId, to: p.id })
  }

  if (out.length === 0) { minX = 0; minY = 0; maxX = 0; maxY = 0 }
  return {
    direction: direction,
    nodes: out,
    edges: edges,
    bounds: { x: minX, y: minY, w: maxX - minX, h: maxY - minY }
  }
}

// Ids of nodes whose title, keys or values contain `query` (case-insensitive).
function search(graph, query) {
  var q = (query || "").trim().toLowerCase()
  var out = []
  if (!graph || q.length === 0) return out
  for (var i = 0; i < graph.nodes.length; i++) {
    if (graph.nodes[i].searchText.indexOf(q) !== -1) out.push(graph.nodes[i].id)
  }
  return out
}

function inspectText(node) {
  if (!node) return ""
  var text
  try { text = JSON.stringify(node.value, null, 2) } catch (e) { text = String(node.value) }
  if (text.length > INSPECT_MAX_CHARS) text = text.slice(0, INSPECT_MAX_CHARS) + "\n… (truncated)"
  return text
}

function prettyPrint(text) {
  var parsed = parseText(text)
  if (!parsed.ok) return null
  return JSON.stringify(parsed.value, null, 2)
}

function badgeFor(node) {
  if (node.kind === "object") return "{" + node.count + "}"
  if (node.kind === "array") return "[" + node.count + "]"
  return ""
}

function countVisible(graph) {
  return visibleNodes(graph).length
}
