// Run with: node tests/model.test.js
const fs = require("fs")
const path = require("path")
const vm = require("vm")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(".pragma library", "")
const Model = vm.runInThisContext("(function(){" + src + "\nreturn { parseText, buildGraph, layout, search, visibleNodes, toggleCollapsed, reveal, inspectText, badgeFor, collapseToDepth, expandAll, prettyPrint, MAX_VISIBLE_NODES } })")()

const metrics = { charWidth: 7, rowHeight: 18, headerHeight: 24, paddingX: 10, paddingY: 6, minWidth: 80, maxWidth: 420 }
const opts = { direction: "LR", gapMain: 60, gapCross: 20, metrics }

let passed = 0
function test(name, fn) { fn(); passed++; console.log("ok -", name) }

test("parseText reports errors and empties", () => {
  assert.strictEqual(Model.parseText("").empty, true)
  assert.strictEqual(Model.parseText("{bad").ok, false)
  assert.ok(Model.parseText("{bad").error.length > 0)
  assert.strictEqual(JSON.stringify(Model.parseText(' {"a":1} ').value), '{"a":1}')
})

test("buildGraph splits primitives into rows and containers into children", () => {
  const g = Model.buildGraph({ name: "x", tags: ["a", "b"], meta: { n: 1, deep: { z: null } } })
  const root = g.nodes[0]
  assert.strictEqual(root.title, "root")
  assert.strictEqual(root.path, "$")
  assert.deepStrictEqual(root.rows.map(r => r.key), ["name"])
  assert.strictEqual(root.childIds.length, 2)
  const tags = g.nodes[root.childIds[0]]
  assert.strictEqual(tags.kind, "array")
  assert.strictEqual(tags.rows.length, 2)
  assert.strictEqual(tags.rows[1].key, "[1]")
  assert.strictEqual(tags.path, "$.tags")
  const deep = g.nodes.find(n => n.title === "deep")
  assert.strictEqual(deep.path, "$.meta.deep")
  assert.strictEqual(deep.rows[0].type, "null")
  assert.strictEqual(Model.badgeFor(root), "{3}")
  assert.strictEqual(Model.badgeFor(tags), "[2]")
})

test("array of objects yields [i] titled children with bracket paths", () => {
  const g = Model.buildGraph({ users: [{ id: 1 }, { id: 2 }] })
  const users = g.nodes[1]
  assert.strictEqual(users.childIds.length, 2)
  assert.strictEqual(g.nodes[users.childIds[1]].title, "[1]")
  assert.strictEqual(g.nodes[users.childIds[1]].path, "$.users[1]")
})

test("odd keys get quoted path segments", () => {
  const g = Model.buildGraph({ "first name": { x: 1 } })
  assert.strictEqual(g.nodes[1].path, '$["first name"]')
})

test("primitive root becomes a single value node", () => {
  const g = Model.buildGraph(42)
  assert.strictEqual(g.nodes.length, 1)
  assert.strictEqual(g.nodes[0].kind, "value")
  assert.strictEqual(g.nodes[0].rows[0].text, "42")
})

test("layout never overlaps and lays depth along x", () => {
  const value = { a: { b: 1, c: [1, 2, 3] }, d: { e: { f: { g: "h" } } }, i: [{ j: 1 }, { k: 2 }, { l: 3 }] }
  const g = Model.buildGraph(value)
  const l = Model.layout(g, opts)
  assert.strictEqual(l.nodes.length, g.nodes.length)
  for (const a of l.nodes) for (const b of l.nodes) {
    if (a.id === b.id) continue
    const overlap = a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
    assert.ok(!overlap, `nodes ${a.id} and ${b.id} overlap`)
  }
  const byId = Object.fromEntries(l.nodes.map(n => [n.id, n]))
  for (const e of l.edges) assert.ok(byId[e.from].x < byId[e.to].x, "child is right of parent")
  assert.ok(l.bounds.w > 0 && l.bounds.h > 0)
})

test("TB layout stacks depth along y", () => {
  const g = Model.buildGraph({ a: { b: 1 }, c: { d: 2 } })
  const l = Model.layout(g, { ...opts, direction: "TB" })
  const byId = Object.fromEntries(l.nodes.map(n => [n.id, n]))
  for (const e of l.edges) assert.ok(byId[e.from].y < byId[e.to].y)
})

test("collapse hides subtree and reveal expands ancestors", () => {
  const g = Model.buildGraph({ a: { b: { c: { d: 1 } } } })
  assert.strictEqual(Model.visibleNodes(g).length, 4)
  Model.toggleCollapsed(g, 1)
  assert.strictEqual(Model.visibleNodes(g).length, 2)
  assert.strictEqual(Model.layout(g, opts).edges.length, 1)
  Model.reveal(g, 3)
  assert.strictEqual(Model.visibleNodes(g).length, 4)
  Model.collapseToDepth(g, 1)
  assert.strictEqual(Model.visibleNodes(g).length, 2)
  Model.expandAll(g)
  assert.strictEqual(Model.visibleNodes(g).length, 4)
})

test("search matches titles, keys and full values", () => {
  const g = Model.buildGraph({ users: [{ name: "Matheus Medrado", role: "dev" }], other: 1 })
  assert.deepStrictEqual(Model.search(g, "medrado"), [2])
  assert.deepStrictEqual(Model.search(g, "USERS"), [1])
  assert.deepStrictEqual(Model.search(g, ""), [])
})

test("huge documents auto-collapse below the node budget", () => {
  const big = {}
  for (let i = 0; i < 60; i++) { big["k" + i] = {}; for (let j = 0; j < 60; j++) big["k" + i]["x" + j] = { v: j } }
  const g = Model.buildGraph(big)
  assert.ok(g.nodes.length > Model.MAX_VISIBLE_NODES)
  assert.ok(Model.visibleNodes(g).length <= Model.MAX_VISIBLE_NODES)
  assert.ok(g.autoCollapsedDepth >= 0)
})

test("inspectText pretty prints", () => {
  const g = Model.buildGraph({ a: { b: 1 } })
  assert.strictEqual(Model.inspectText(g.nodes[1]), '{\n  "b": 1\n}')
})

test("prettyPrint reformats valid JSON and rejects invalid", () => {
  assert.strictEqual(Model.prettyPrint('{"a":[1,2]}'), '{\n  "a": [\n    1,\n    2\n  ]\n}')
  assert.strictEqual(Model.prettyPrint('{nope'), null)
})

console.log(`\n${passed} tests passed`)
