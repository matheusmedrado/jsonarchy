.pragma library

// JSON syntax highlighting for the editor. Produces Qt StyledText: only
// <font color>, <br> and &nbsp; are used so the result lines up glyph for
// glyph with the transparent TextEdit drawn over it.

var MAX_HIGHLIGHT_CHARS = 200000

var TOKEN = /("(?:[^"\\\n]|\\.)*"?)(\s*:)?|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|\b(true|false|null)\b|([{}\[\],:])|(\n)|( +)|(\t)|([^\s"{}\[\],:\d-][^\s"{}\[\],:]*|.)/g

function escapeText(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function spaces(n) {
  var out = ""
  for (var i = 0; i < n; i++) out += "&nbsp;"
  return out
}

function span(color, text) {
  return "<font color=\"" + color + "\">" + text + "</font>"
}

// colors: { key, string, number, boolean, nul, punct, error }
// Returns null when the text is too large to highlight comfortably.
function highlight(text, colors) {
  if (!text) return ""
  if (text.length > MAX_HIGHLIGHT_CHARS) return null
  var out = []
  TOKEN.lastIndex = 0
  var m
  while ((m = TOKEN.exec(text)) !== null) {
    if (m[1] !== undefined) {
      var str = escapeText(m[1]).replace(/ /g, "&nbsp;")
      if (m[2] !== undefined) {
        out.push(span(colors.key, str))
        var colon = m[2]
        var ws = colon.slice(0, colon.length - 1)
        out.push(ws.replace(/ /g, "&nbsp;").replace(/\n/g, "<br>"))
        out.push(span(colors.punct, ":"))
      } else {
        out.push(span(colors.string, str))
      }
    } else if (m[3] !== undefined) {
      out.push(span(colors.number, m[3]))
    } else if (m[4] !== undefined) {
      out.push(span(m[4] === "null" ? colors.nul : colors.boolean, m[4]))
    } else if (m[5] !== undefined) {
      out.push(span(colors.punct, escapeText(m[5])))
    } else if (m[6] !== undefined) {
      out.push("<br>")
    } else if (m[7] !== undefined) {
      out.push(spaces(m[7].length))
    } else if (m[8] !== undefined) {
      out.push(spaces(4))
    } else {
      out.push(span(colors.error, escapeText(m[9]).replace(/ /g, "&nbsp;")))
    }
  }
  return out.join("")
}

// Syntax palette derived from the theme accent. Hues are rotated from the
// accent so the types stay distinct while sitting inside the theme's own
// harmony; saturation and lightness are fixed per surface so the colors
// read clearly on muted grounds without shouting.
//   accentHue: 0..1 (or -1 when the accent is grey)
//   dark: whether the surface is dark
// Returns hsl triples the caller turns into colors: { key, string, ... }
function paletteSpec(accentHue, dark) {
  var base = accentHue >= 0 ? accentHue : 0.58
  function wrap(h) { return ((h % 1) + 1) % 1 }
  var l = dark ? 0.70 : 0.38
  var s = dark ? 0.48 : 0.55
  return {
    string:  { h: wrap(base),        s: s,        l: l },
    number:  { h: wrap(base + 0.42), s: s,        l: l },
    boolean: { h: wrap(base + 0.17), s: s * 0.9,  l: l },
    nul:     { h: wrap(base - 0.10), s: s * 0.55, l: dark ? 0.60 : 0.48 },
    key:     { h: wrap(base + 0.5),  s: 0.0,      l: dark ? 0.86 : 0.20 },
    punct:   { h: base,              s: 0.08,     l: dark ? 0.55 : 0.50 },
    error:   { h: 0.0,               s: 0.65,     l: dark ? 0.66 : 0.42 }
  }
}
