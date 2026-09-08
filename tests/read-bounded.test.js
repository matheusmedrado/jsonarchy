// Run with: node tests/read-bounded.test.js
// Exercises bin/read-bounded.sh against regular, oversized, special and
// missing paths. Needs a POSIX sh, stat, head, mkfifo (coreutils).
const { spawnSync } = require("child_process")
const fs = require("fs")
const os = require("os")
const path = require("path")
const assert = require("assert")

const script = path.join(__dirname, "..", "bin", "read-bounded.sh")
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "jsonarchy-"))
function run(target, max) {
  const r = spawnSync("sh", [script, target, String(max)], { encoding: "utf8", timeout: 5000 })
  return { code: r.status, out: r.stdout, err: r.stderr, timedOut: r.error && r.error.code === "ETIMEDOUT" }
}

let passed = 0
function test(name, fn) { fn(); passed++; console.log("ok -", name) }

const small = path.join(dir, "small.json"); fs.writeFileSync(small, '{"a": 1}')
const big = path.join(dir, "big.json"); fs.writeFileSync(big, "x".repeat(2000))
const link = path.join(dir, "link.json"); fs.symlinkSync(small, link)
const devlink = path.join(dir, "devzero"); fs.symlinkSync("/dev/zero", devlink)
const dangling = path.join(dir, "dangling"); fs.symlinkSync(path.join(dir, "nope"), dangling)
const fifo = path.join(dir, "fifo"); spawnSync("mkfifo", [fifo])

test("regular file within the limit is returned whole", () => {
  const r = run(small, 1000); assert.strictEqual(r.code, 0); assert.strictEqual(r.out, '{"a": 1}')
})
test("symlink to a regular file is followed", () => {
  const r = run(link, 1000); assert.strictEqual(r.code, 0); assert.strictEqual(r.out, '{"a": 1}')
})
test("file over the limit is rejected with exit 4 and no output", () => {
  const r = run(big, 1000); assert.strictEqual(r.code, 4); assert.strictEqual(r.out, ""); assert.ok(/too large/.test(r.err))
})
test("/dev/zero is rejected immediately", () => {
  const r = run("/dev/zero", 1000); assert.strictEqual(r.code, 3); assert.strictEqual(r.out, ""); assert.ok(!r.timedOut)
})
test("symlink to /dev/zero is rejected", () => {
  const r = run(devlink, 1000); assert.strictEqual(r.code, 3)
})
test("FIFO is rejected without blocking", () => {
  if (!fs.existsSync(fifo)) return
  const r = run(fifo, 1000); assert.strictEqual(r.code, 3); assert.ok(!r.timedOut)
})
test("directory, missing path and dangling symlink are rejected", () => {
  assert.strictEqual(run(dir, 1000).code, 3)
  assert.strictEqual(run(path.join(dir, "missing.json"), 1000).code, 3)
  assert.strictEqual(run(dangling, 1000).code, 3)
})
test("bad arguments exit 2", () => {
  assert.strictEqual(run(small, "lots").code, 2)
  assert.strictEqual(spawnSync("sh", [script], { encoding: "utf8" }).status, 2)
})

fs.rmSync(dir, { recursive: true, force: true })
console.log(`\n${passed} tests passed`)
