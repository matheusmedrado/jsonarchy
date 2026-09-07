// Run with: node tests/export.test.js
const fs = require("fs")
const path = require("path")
const vm = require("vm")
const assert = require("assert")

function load(file, names) {
  const src = fs.readFileSync(path.join(__dirname, "..", file), "utf8").replace(".pragma library", "")
  return vm.runInThisContext("(function(){" + src + "\nreturn { " + names + " } })")()
}
const Model = load("Model.js", "buildGraph, layout, badgeFor")
const Export = load("components/Export.js", "svg, timestamp")

const metrics = { charWidth: 7, rowHeight: 18, headerHeight: 24, paddingX: 10, paddingY: 6, minWidth: 80, maxWidth: 420 }
const rgb = (r, g, b, a) => ({ r, g, b, a })
const colors = {
  background: rgb(0.06, 0.07, 0.08), text: rgb(0.8, 0.8, 0.8), key: rgb(0.8, 0.8, 0.8), muted: rgb(0.5, 0.5, 0.5),
  nodeBackground: rgb(0.8, 0.8, 0.8, 0.04), nodeBorder: rgb(0.8, 0.8, 0.8, 0.24), edge: rgb(0.8, 0.8, 0.8, 0.45),
  stringValue: rgb(0.4, 0.6, 0.9), numberValue: rgb(0.9, 0.5, 0.4), booleanValue: rgb(0.7, 0.5, 0.9), nullValue: rgb(0.4, 0.7, 0.7)
}
const opts = { colors, metrics, fontFamily: "Cascadia Mono", fontSize: 12, captionSize: 10, cornerRadius: 6, padding: 24, badgeFor: Model.badgeFor }

let passed = 0
function test(name, fn) { fn(); passed++; console.log("ok -", name) }

const g = Model.buildGraph({ name: "a<b>&\"c\"", n: 1, ok: true, z: null, child: { k: "v" }, list: [1, 2] })
const lay = Model.layout(g, { direction: "LR", gapMain: 60, gapCross: 20, metrics })
const out = Export.svg(lay, opts)

test("svg is well-formed with sized viewBox", () => {
  assert.ok(out.startsWith("<?xml"))
  assert.ok(out.includes('<svg xmlns="http://www.w3.org/2000/svg"'))
  assert.ok(out.trim().endsWith("</svg>"))
  const W = Math.ceil(lay.bounds.w + 48)
  assert.ok(out.includes(`width="${W}"`))
})

test("one rect and clip per node, one path per edge", () => {
  assert.strictEqual((out.match(/<clipPath /g) || []).length, lay.nodes.length)
  assert.strictEqual((out.match(/<path d=/g) || []).length, lay.edges.length)
})

test("text is escaped and typed colors applied", () => {
  assert.ok(out.includes("a&lt;b&gt;&amp;"))
  assert.ok(out.includes('fill="#6699e6"'))   // string color
  assert.ok(out.includes('fill="#e68066"'))   // number color
})

test("alpha colors emit opacity attributes", () => {
  assert.ok(out.includes('fill-opacity="0.040"'))
  assert.ok(out.includes('stroke-opacity="0.450"'))
})

test("badges and titles are present", () => {
  assert.ok(out.includes(">{6}<"))
  assert.ok(out.includes("⌄ root"))
})

test("TB layout produces vertical bezier control points", () => {
  const tb = Export.svg(Model.layout(g, { direction: "TB", gapMain: 60, gapCross: 20, metrics }), opts)
  assert.ok(/C(\d+(\.\d+)?) \d/.test(tb))
})

test("timestamp format", () => {
  assert.strictEqual(Export.timestamp(new Date(2026, 8, 7, 9, 5, 3)), "2026-09-07_09-05-03")
})

fs.writeFileSync(path.join(__dirname, "..", "tests", "out.svg"), out)
console.log(`\n${passed} tests passed`)
