# The JavaScript operators json-server's filtering and sorting lean on, applied
# to JSON values: `String(x)`, `ToNumber`, falsiness and the abstract relational
# comparison behind `<`.

import std / [strutils, unicode]
import jsonvalue

proc jsString*(v: Maybe): string =
  ## `String(v)`.
  if v == nil: return "undefined"
  case v.kind
  of JNull: result = "null"
  of JBool: result = if v.bval: "true" else: "false"
  of JNumber: result = jsNumberToString(v.num)
  of JString: result = v.str
  of JArray:
    # Array.prototype.join: null and undefined become "".
    result = ""
    for i, e in v.elems:
      if i > 0: result.add ','
      if e.kind != JNull: result.add jsString(e)
  of JObject: result = "[object Object]"

proc toPrimitive(v: Maybe): Maybe =
  if v != nil and v.kind in {JArray, JObject}: result = newJString(jsString(v))
  else: result = v

proc toNumber(v: Maybe): float =
  ## `ToNumber` on a primitive; NaN where JS gives NaN.
  if v == nil: return NaN
  case v.kind
  of JNull: result = 0.0
  of JBool: result = if v.bval: 1.0 else: 0.0
  of JNumber: result = v.num
  of JString:
    var ok = false
    result = jsNumber(v.str, ok)
    if not ok: result = NaN
  of JArray, JObject: result = toNumber(toPrimitive(v))

type
  JsOrder* = enum
    Less, Equal, Greater, Unordered   ## `Unordered`: a NaN was involved

proc jsCompare*(a, b: Maybe): JsOrder =
  ## The abstract relational comparison (ECMA-262 §7.2.13) generalized to all
  ## four outcomes, so `<`, `<=`, `>`, `>=` are one call each.
  let x = toPrimitive(a)
  let y = toPrimitive(b)
  if x != nil and y != nil and x.kind == JString and y.kind == JString:
    # UTF-16 code unit order; for UTF-8 byte order it only differs past the BMP.
    let c = cmp(x.str, y.str)
    return if c < 0: Less elif c > 0: Greater else: Equal
  let nx = toNumber(x)
  let ny = toNumber(y)
  if nx != nx or ny != ny: return Unordered
  result = if nx < ny: Less elif nx > ny: Greater else: Equal

proc jsLt*(a, b: Maybe): bool = jsCompare(a, b) == Less
proc jsLe*(a, b: Maybe): bool = jsCompare(a, b) in {Less, Equal}
proc jsGt*(a, b: Maybe): bool = jsCompare(a, b) == Greater
proc jsGe*(a, b: Maybe): bool = jsCompare(a, b) in {Greater, Equal}

proc isFalsy*(v: Maybe): bool =
  ## `!v`.
  if v == nil: return true
  case v.kind
  of JNull: result = true
  of JBool: result = not v.bval
  of JNumber: result = v.num == 0.0 or v.num != v.num
  of JString: result = v.str.len == 0
  of JArray, JObject: result = false

proc jsLower*(s: string): string =
  ## `String.prototype.toLowerCase`, Unicode-aware.
  unicode.toLower(s)

type
  CollationElement = object
    primary: int      ## script group, then base character
    secondary: int    ## 0 unaccented, >0 an accent
    tertiary: int     ## 0 lowercase, 1 uppercase

proc baseLatin(r: int; base: var char; accent: var int): bool =
  ## Latin-1 Supplement and Latin Extended-A letters folded to their base
  ## letter, the accent kept as a secondary difference.
  const
    s1 = "AAAAAAACEEEEIIIIDNOOOOOxOUUUUYTsaaaaaaaceeeeiiiidnooooo/ouuuuyty"
    ## U+00C0..U+00FF, `x`/`/` for × and ÷ (not letters)
  if r >= 0xC0 and r <= 0xFF:
    let c = s1[r - 0xC0]
    if c in {'x', '/'} and (r == 0xD7 or r == 0xF7): return false
    base = c
    accent = r - 0xBF
    return true
  if r >= 0x100 and r <= 0x17F:
    # Pairs of upper/lower case in this block; the base letter by range.
    const ranges = [(0x100, 0x105, 'a'), (0x106, 0x10D, 'c'), (0x10E, 0x111, 'd'),
                    (0x112, 0x11B, 'e'), (0x11C, 0x123, 'g'), (0x124, 0x127, 'h'),
                    (0x128, 0x131, 'i'), (0x134, 0x135, 'j'), (0x136, 0x138, 'k'),
                    (0x139, 0x142, 'l'), (0x143, 0x14B, 'n'), (0x14C, 0x151, 'o'),
                    (0x154, 0x159, 'r'), (0x15A, 0x161, 's'), (0x162, 0x167, 't'),
                    (0x168, 0x173, 'u'), (0x174, 0x175, 'w'), (0x176, 0x178, 'y'),
                    (0x179, 0x17E, 'z')]
    for (lo, hi, b) in ranges:
      if r >= lo and r <= hi:
        base = if (r - lo) mod 2 == 0 and r != 0x131 and r != 0x138: chr(ord(b) - 32) else: b
        accent = r - lo + 1
        return true
  result = false

proc collate(s: string): seq[CollationElement] =
  ## A small approximation of the Unicode Collation Algorithm's root order,
  ## which is what `localeCompare` without a locale uses: punctuation and
  ## symbols, then digits, then letters (case- and accent-insensitive at the
  ## first level), then everything else by code point.
  result = @[]
  for r in s.runes:
    let cp = int(r)
    var base = '\0'
    var accent = 0
    if cp < 0x80:
      let c = chr(cp)
      if c in {'a'..'z'}:
        result.add CollationElement(primary: 3000 + ord(c) * 4, secondary: 0, tertiary: 0)
      elif c in {'A'..'Z'}:
        result.add CollationElement(primary: 3000 + (ord(c) + 32) * 4, secondary: 0, tertiary: 1)
      elif c in {'0'..'9'}:
        result.add CollationElement(primary: 2000 + ord(c), secondary: 0, tertiary: 0)
      else:
        result.add CollationElement(primary: 1000 + cp, secondary: 0, tertiary: 0)
    elif baseLatin(cp, base, accent):
      let lower = if base in {'A'..'Z'}: chr(ord(base) + 32) else: base
      result.add CollationElement(primary: 3000 + ord(lower) * 4, secondary: accent,
                                  tertiary: (if base in {'A'..'Z'}: 1 else: 0))
    else:
      result.add CollationElement(primary: 10_000 + cp, secondary: 0, tertiary: 0)

proc localeCompare*(a, b: string): int =
  ## `a.localeCompare(b)` approximated with `collate`: compare all primary
  ## weights, then all secondary, then all tertiary — the multi-level order
  ## that puts "b" < "B" < "c" and "e" < "é" < "f".
  let x = collate(a)
  let y = collate(b)
  for level in 0 .. 2:
    for i in 0 ..< min(x.len, y.len):
      let wx = case level
               of 0: x[i].primary
               of 1: x[i].secondary
               else: x[i].tertiary
      let wy = case level
               of 0: y[i].primary
               of 1: y[i].secondary
               else: y[i].tertiary
      if wx != wy: return (if wx < wy: -1 else: 1)
    if level == 0 and x.len != y.len: return (if x.len < y.len: -1 else: 1)
  result = 0
