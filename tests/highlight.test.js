// Run with: node tests/highlight.test.js
const fs = require("fs")
const path = require("path")
const vm = require("vm")
const assert = require("assert")

const src = fs.readFileSync(path.join(__dirname, "..", "components", "Highlight.js"), "utf8").replace(".pragma library", "")
const H = vm.runInThisContext("(function(){" + src + "\nreturn { highlight, paletteSpec, MAX_HIGHLIGHT_CHARS } })")()
const c = { key: "K", string: "S", number: "N", boolean: "B", nul: "U", punct: "P", error: "E" }

let passed = 0
function test(name, fn) { fn(); passed++; console.log("ok -", name) }

test("keys, strings, numbers, booleans, null and punctuation get their colors", () => {
  const out = H.highlight('{"a": "x", "n": -1.5e3, "t": true, "z": null}', c)
  assert.ok(out.includes('<font color="K">"a"</font>'))
  assert.ok(out.includes('<font color="S">"x"</font>'))
  assert.ok(out.includes('<font color="N">-1.5e3</font>'))
  assert.ok(out.includes('<font color="B">true</font>'))
  assert.ok(out.includes('<font color="U">null</font>'))
  assert.ok(out.includes('<font color="P">{</font>'))
  assert.ok(out.includes('<font color="P">:</font>'))
})

test("whitespace is preserved as nbsp and br", () => {
  const out = H.highlight('{\n  "a": 1\n}', c)
  assert.ok(out.includes("<br>&nbsp;&nbsp;"))
  assert.ok(!out.includes("\n"))
})

test("html in strings is escaped", () => {
  const out = H.highlight('"<b>&"', c)
  assert.ok(out.includes("&lt;b&gt;&amp;"))
})

test("escaped quotes stay inside the string token", () => {
  const out = H.highlight('{"k": "a \\" b"}', c)
  assert.ok(out.includes('<font color="S">"a&nbsp;\\"&nbsp;b"</font>'))
})

test("stray text is marked as error", () => {
  const out = H.highlight('{bad}', c)
  assert.ok(out.includes('<font color="E">bad</font>'))
})

test("huge input is skipped", () => {
  assert.strictEqual(H.highlight("x".repeat(H.MAX_HIGHLIGHT_CHARS + 1), c), null)
})

test("palette spec rotates hues from the accent and falls back for grey", () => {
  const p = H.paletteSpec(0.1, true)
  assert.ok(Math.abs(p.string.h - 0.1) < 1e-9)
  assert.ok(Math.abs(p.number.h - 0.52) < 1e-9)
  assert.ok(p.boolean.h !== p.string.h && p.nul.h !== p.string.h)
  const g = H.paletteSpec(-1, false)
  assert.ok(Math.abs(g.string.h - 0.58) < 1e-9)
  assert.ok(g.string.l < H.paletteSpec(-1, true).string.l)
})

console.log(`\n${passed} tests passed`)
