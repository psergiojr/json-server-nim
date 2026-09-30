# A mutable JSON document, with the semantics json-server's TypeScript relies on.
#
# `std/json` is a read-only cursor over a token buffer; json-server edits its
# database in place (push, splice, nullify foreign keys), so it needs a DOM.
#
# JavaScript semantics kept on purpose:
#
# * One number type, `float`. `JSON.stringify` prints `100`, not `100.0`, and
#   `jsNumberToString` reproduces `Number.prototype.toString` exactly.
# * Objects keep insertion order.
# * `undefined` is `Maybe` = `nil JsonValue`: a missing key, as opposed to a
#   present `null`. Nimony refs are not-nil by default, so the compiler makes
#   every caller check for undefined before touching one — the whole
#   `TypeError: cannot read properties of undefined` class, gone.

import std / [strutils, parseutils, assertions]

type
  JsonKind* = enum
    JNull, JBool, JNumber, JString, JArray, JObject

  JsonValue* = ref JsonValueObj
  Maybe* = nil JsonValue
    ## A value, or `undefined`.
  JsonValueObj* = object
    case kind*: JsonKind
    of JNull: discard
    of JBool: bval*: bool
    of JNumber: num*: float
    of JString: str*: string
    of JArray: elems*: seq[JsonValue]
    of JObject: fields*: seq[(string, JsonValue)]


# ------------------------------------------------------------ constructors --

proc newJNull*(): JsonValue = JsonValue(kind: JNull)
proc newJBool*(b: bool): JsonValue = JsonValue(kind: JBool, bval: b)
proc newJNumber*(n: float): JsonValue = JsonValue(kind: JNumber, num: n)
proc newJNumber*(n: int): JsonValue = JsonValue(kind: JNumber, num: float(n))
proc newJString*(s: string): JsonValue = JsonValue(kind: JString, str: s)
proc newJArray*(elems: seq[JsonValue] = @[]): JsonValue =
  JsonValue(kind: JArray, elems: elems)
proc newJObject*(): JsonValue = JsonValue(kind: JObject, fields: @[])

proc `%`*(s: string): JsonValue = newJString(s)
proc `%`*(n: int): JsonValue = newJNumber(n)
proc `%`*(n: float): JsonValue = newJNumber(n)
proc `%`*(b: bool): JsonValue = newJBool(b)

template isObject*(v: Maybe): bool = v != nil and v.kind == JObject
template isArray*(v: Maybe): bool = v != nil and v.kind == JArray
template isString*(v: Maybe): bool = v != nil and v.kind == JString
template isNull*(v: Maybe): bool = v != nil and v.kind == JNull

# ------------------------------------------------------------------ objects --

proc find(v: JsonValue; key: string): int =
  for i in 0 ..< v.fields.len:
    if v.fields[i][0] == key: return i
  result = -1

proc hasKey*(v: Maybe; key: string): bool =
  if v.isObject: v.find(key) >= 0 else: false

proc `[]`*(v: Maybe; key: string): Maybe =
  ## The value under `key`, or `nil` (undefined) — also for a non-object.
  if not v.isObject: return nil
  let i = v.find(key)
  if i < 0: result = nil
  else: result = v.fields[i][1]

proc `[]=`*(v: JsonValue; key: string; val: JsonValue) =
  ## Replace in place, or append — the order `obj[key] = val` gives in JS.
  assert v.isObject
  let i = v.find(key)
  if i < 0: v.fields.add((key, val))
  else: v.fields[i][1] = val

proc delete*(v: Maybe; key: string) =
  if not v.isObject: return
  let i = v.find(key)
  if i >= 0: v.fields.delete(i)

proc len*(v: Maybe): int =
  ## Elements, fields or bytes; 0 for anything else, undefined included.
  if v == nil: return 0
  case v.kind
  of JArray: result = v.elems.len
  of JObject: result = v.fields.len
  of JString: result = v.str.len
  else: result = 0

proc `[]`*(v: Maybe; i: int): Maybe =
  ## `v?.[i]`: undefined past the end or for a non-array.
  if v.isArray:
    if i >= 0 and i < v.elems.len: return v.elems[i]
  result = nil

proc getStr*(v: Maybe; default = ""): string =
  ## The string, or `default` for anything that is not one.
  if v.isString: result = v.str
  else: result = default

proc getNum*(v: Maybe; default = NaN): float =
  ## The number, or `default` for anything that is not one.
  if v != nil:
    if v.kind == JNumber: return v.num
  result = default

proc `==`*(v: Maybe; s: string): bool =
  ## `v === s`.
  if v.isString: result = v.str == s
  else: result = false

proc add*(v: JsonValue; x: JsonValue) =
  assert v.isArray
  v.elems.add x

iterator items*(v: Maybe): JsonValue =
  if v.isArray:
    for e in v.elems: yield e

iterator pairs*(v: Maybe): (string, JsonValue) =
  if v.isObject:
    for kv in v.fields: yield kv

iterator keys*(v: Maybe): string =
  if v.isObject:
    for kv in v.fields: yield kv[0]

proc spread*(a, b: Maybe): JsonValue =
  ## `{ ...a, ...b }`: a fresh object, `a`'s keys in order, then `b`'s.
  result = newJObject()
  for k, x in a: result[k] = x
  for k, x in b: result[k] = x

proc copy*(v: JsonValue): JsonValue =
  ## `structuredClone`.
  case v.kind
  of JNull: result = newJNull()
  of JBool: result = newJBool(v.bval)
  of JNumber: result = newJNumber(v.num)
  of JString: result = newJString(v.str)
  of JArray:
    result = newJArray()
    for e in v.elems: result.elems.add copy(e)
  of JObject:
    result = newJObject()
    for kv in v.fields: result.fields.add((kv[0], copy(kv[1])))

# --------------------------------------------------------------- equality --

proc strictEq*(a, b: Maybe): bool =
  ## JavaScript `===`: primitives by value, arrays and objects by identity.
  ## `undefined === undefined`, and `NaN` is not equal to itself.
  if a == nil or b == nil: return a == nil and b == nil
  if a.kind != b.kind: return false
  case a.kind
  of JNull: true
  of JBool: a.bval == b.bval
  of JNumber: a.num == b.num
  of JString: a.str == b.str
  of JArray, JObject: cast[pointer](a) == cast[pointer](b)

proc deepEqual*(a, b: Maybe): bool =
  ## `assert.deepStrictEqual` on JSON data. Key order does not matter.
  if a == nil or b == nil: return a == nil and b == nil
  if a.kind != b.kind: return false
  case a.kind
  of JNull: result = true
  of JBool: result = a.bval == b.bval
  of JNumber: result = a.num == b.num
  of JString: result = a.str == b.str
  of JArray:
    if a.elems.len != b.elems.len: return false
    for i in 0 ..< a.elems.len:
      if not deepEqual(a.elems[i], b.elems[i]): return false
    result = true
  of JObject:
    if a.fields.len != b.fields.len: return false
    for kv in a.fields:
      let j = b.find(kv[0])
      if j < 0 or not deepEqual(kv[1], b.fields[j][1]): return false
    result = true

# ---------------------------------------------------------------- numbers --

proc jsNumberToString*(x: float): string =
  ## `Number.prototype.toString()` (ECMA-262 §6.1.6.1.20). Built on the
  ## shortest round-trip digits `system.$` already computes.
  if x != x: return "NaN"
  if x == Inf: return "Infinity"
  if x == -Inf: return "-Infinity"
  if x == 0.0: return "0"
  let raw = $x                     # "123.45", "1e+21", "1.5e-07", "100.0"
  var neg = false
  var digits = ""
  var pointPos = -1                # digits before the '.'
  var exp10 = 0
  var i = 0
  if raw[0] == '-':
    neg = true
    inc i
  while i < raw.len and raw[i] != 'e':
    if raw[i] == '.': pointPos = digits.len
    else: digits.add raw[i]
    inc i
  if pointPos < 0: pointPos = digits.len
  if i < raw.len:
    var e: BiggestInt = 0
    discard parseBiggestInt(raw.substr(i + 1), e)  # accepts a sign
    exp10 = int(e)
  # value = 0.digits * 10^n, digits without leading/trailing zeros
  var lead = 0
  while lead < digits.len - 1 and digits[lead] == '0':
    inc lead
    dec pointPos
  digits = digits.substr(lead)
  while digits.len > 1 and digits[^1] == '0': digits.setLen digits.len - 1
  let k = digits.len
  let n = pointPos + exp10
  result = if neg: "-" else: ""
  if k <= n and n <= 21:
    result.add digits
    for _ in 0 ..< n - k: result.add '0'
  elif 0 < n and n <= 21:
    result.add digits.substr(0, n - 1)
    result.add '.'
    result.add digits.substr(n)
  elif -6 < n and n <= 0:
    result.add "0."
    for _ in 0 ..< -n: result.add '0'
    result.add digits
  else:
    result.add digits[0]
    if k > 1:
      result.add '.'
      result.add digits.substr(1)
    result.add 'e'
    let e = n - 1
    result.add(if e >= 0: "+" else: "-")
    result.add $abs(e)

proc isWs(c: char): bool {.inline.} =
  c in {' ', '\t', '\n', '\r', '\v', '\f'}

proc jsNumber*(s: string; ok: var bool): float =
  ## JavaScript `Number(s)` for a string: whitespace-trimmed decimal, `0x`/`0o`/
  ## `0b` integers, `Infinity`. `ok = false` where JS answers `NaN`.
  ok = false
  result = 0.0
  var a = 0
  var b = s.len
  while a < b and isWs(s[a]): inc a
  while b > a and isWs(s[b - 1]): dec b
  if a == b:
    ok = true                      # Number("") === 0
    return 0.0
  let t = s.substr(a, b - 1)
  if t.len > 2 and t[0] == '0' and t[1] in {'x', 'X', 'o', 'O', 'b', 'B'}:
    let base = case t[1]
               of 'x', 'X': 16
               of 'o', 'O': 8
               else: 2
    var v = 0.0
    for i in 2 ..< t.len:
      let c = t[i]
      let d = if c in {'0'..'9'}: ord(c) - ord('0')
              elif c in {'a'..'f'}: ord(c) - ord('a') + 10
              elif c in {'A'..'F'}: ord(c) - ord('A') + 10
              else: 99
      if d >= base: return 0.0
      v = v * float(base) + float(d)
    ok = true
    return v
  var body = t
  var sign = 1.0
  if body[0] in {'+', '-'}:
    if body[0] == '-': sign = -1.0
    body = body.substr(1)
  if body == "Infinity":
    ok = true
    return sign * Inf
  # StrUnsignedDecimalLiteral: digits [. digits] [e[+-]digits], at least one digit
  var i = 0
  var sawDigit = false
  while i < body.len and body[i] in {'0'..'9'}:
    inc i
    sawDigit = true
  if i < body.len and body[i] == '.':
    inc i
    while i < body.len and body[i] in {'0'..'9'}:
      inc i
      sawDigit = true
  if not sawDigit: return 0.0
  if i < body.len and body[i] in {'e', 'E'}:
    inc i
    if i < body.len and body[i] in {'+', '-'}: inc i
    var expDigit = false
    while i < body.len and body[i] in {'0'..'9'}:
      inc i
      expDigit = true
    if not expDigit: return 0.0
  if i != body.len: return 0.0
  var v = 0.0
  var src = body
  if src[0] == '.': src = "0" & src         # ".5"
  if src.len > 0 and src[^1] == '.': src.add '0'
  if parseBiggestFloat(src, v) == 0: return 0.0
  ok = true
  result = sign * v

# --------------------------------------------------------------- printing --

proc addQuoted*(r: var string; s: string) =
  ## `JSON.stringify` on a string: `"`, `\\`, and control characters escaped,
  ## everything else (UTF-8 included) passed through.
  const hex = "0123456789abcdef"
  r.add '"'
  for c in s:
    case c
    of '"': r.add "\\\""
    of '\\': r.add "\\\\"
    of '\b': r.add "\\b"
    of '\f': r.add "\\f"
    of '\n': r.add "\\n"
    of '\r': r.add "\\r"
    of '\t': r.add "\\t"
    of '\0'..'\7', '\11', '\14'..'\31':
      r.add "\\u00"
      r.add hex[ord(c) shr 4]
      r.add hex[ord(c) and 15]
    else: r.add c
  r.add '"'

proc addNumber(r: var string; x: float) =
  # JSON has no NaN or Infinity; JSON.stringify writes null for them.
  if x != x or x == Inf or x == -Inf: r.add "null"
  else: r.add jsNumberToString(x)

proc emit(r: var string; v: JsonValue; indent: int; depth: int) =
  case v.kind
  of JNull: r.add "null"
  of JBool: r.add(if v.bval: "true" else: "false")
  of JNumber: r.addNumber v.num
  of JString: r.addQuoted v.str
  of JArray:
    if v.elems.len == 0:
      r.add "[]"
      return
    r.add '['
    for i, e in v.elems:
      if i > 0: r.add ','
      if indent > 0:
        r.add '\n'
        r.add spaces(indent * (depth + 1))
      emit(r, e, indent, depth + 1)
    if indent > 0:
      r.add '\n'
      r.add spaces(indent * depth)
    r.add ']'
  of JObject:
    var first = true
    r.add '{'
    for kv in v.fields:
      if not first: r.add ','
      first = false
      if indent > 0:
        r.add '\n'
        r.add spaces(indent * (depth + 1))
      r.addQuoted kv[0]
      r.add ':'
      if indent > 0: r.add ' '
      emit(r, kv[1], indent, depth + 1)
    if indent > 0 and not first:
      r.add '\n'
      r.add spaces(indent * depth)
    r.add '}'

proc toJson*(v: Maybe; indent = 0): string =
  ## `JSON.stringify(v, null, indent)`; undefined prints as `null`.
  result = ""
  if v == nil: result = "null"
  else: emit(result, v, indent, 0)

proc `$`*(v: Maybe): string = toJson(v)

# ---------------------------------------------------------------- parsing --

type
  Parser = object
    s: string
    pos: int
    json5: bool
    err: string   ## `line:col: what`; set right before `SyntaxError` is raised

proc lineCol(p: Parser; pos: int): string =
  var line = 1
  var col = 1
  for i in 0 ..< min(pos, p.s.len):
    if p.s[i] == '\n':
      inc line
      col = 1
    else:
      inc col
  result = $line & ":" & $col

proc fail(p: var Parser; msg: string) {.raises.} =
  p.err = lineCol(p, p.pos) & ": " & msg
  raise SyntaxError

proc unexpected(p: var Parser) {.raises.} =
  if p.pos >= p.s.len: fail(p, "Unexpected end of JSON input")
  fail(p, "Unexpected token '" & p.s[p.pos] & "'")

proc skipWs(p: var Parser) {.raises.} =
  while p.pos < p.s.len:
    let c = p.s[p.pos]
    if c in {' ', '\t', '\n', '\r'}:
      inc p.pos
    elif p.json5 and c in {'\v', '\f'}:
      inc p.pos
    elif p.json5 and c == '\xC2' and p.pos + 1 < p.s.len and p.s[p.pos + 1] == '\xA0':
      p.pos += 2                                   # U+00A0
    elif p.json5 and c == '\xEF' and p.pos + 2 < p.s.len and
         p.s[p.pos + 1] == '\xBB' and p.s[p.pos + 2] == '\xBF':
      p.pos += 3                                   # BOM
    elif p.json5 and c == '/' and p.pos + 1 < p.s.len and p.s[p.pos + 1] == '/':
      while p.pos < p.s.len and p.s[p.pos] != '\n': inc p.pos
    elif p.json5 and c == '/' and p.pos + 1 < p.s.len and p.s[p.pos + 1] == '*':
      p.pos += 2
      while true:
        if p.pos + 1 >= p.s.len:
          p.pos = p.s.len
          fail(p, "Unterminated comment")
        if p.s[p.pos] == '*' and p.s[p.pos + 1] == '/':
          p.pos += 2
          break
        inc p.pos
    else:
      break

proc addUtf8(r: var string; cp: int) =
  if cp < 0x80:
    r.add chr(cp)
  elif cp < 0x800:
    r.add chr(0xC0 or (cp shr 6))
    r.add chr(0x80 or (cp and 0x3F))
  elif cp < 0x10000:
    r.add chr(0xE0 or (cp shr 12))
    r.add chr(0x80 or ((cp shr 6) and 0x3F))
    r.add chr(0x80 or (cp and 0x3F))
  else:
    r.add chr(0xF0 or (cp shr 18))
    r.add chr(0x80 or ((cp shr 12) and 0x3F))
    r.add chr(0x80 or ((cp shr 6) and 0x3F))
    r.add chr(0x80 or (cp and 0x3F))

proc hexDigits(p: var Parser; n: int): int {.raises.} =
  result = 0
  for _ in 0 ..< n:
    if p.pos >= p.s.len: unexpected(p)
    let c = p.s[p.pos]
    let d = if c in {'0'..'9'}: ord(c) - ord('0')
            elif c in {'a'..'f'}: ord(c) - ord('a') + 10
            elif c in {'A'..'F'}: ord(c) - ord('A') + 10
            else: -1
    if d < 0: fail(p, "Bad Unicode escape")
    result = result * 16 + d
    inc p.pos

proc parseString(p: var Parser): string {.raises.} =
  let quote = p.s[p.pos]
  inc p.pos
  result = ""
  while true:
    if p.pos >= p.s.len: fail(p, "Unterminated string in JSON")
    let c = p.s[p.pos]
    if c == quote:
      inc p.pos
      return
    if c == '\\':
      inc p.pos
      if p.pos >= p.s.len: fail(p, "Unterminated string in JSON")
      let e = p.s[p.pos]
      inc p.pos
      case e
      of '"': result.add '"'
      of '\\': result.add '\\'
      of '/': result.add '/'
      of 'b': result.add '\b'
      of 'f': result.add '\f'
      of 'n': result.add '\n'
      of 'r': result.add '\r'
      of 't': result.add '\t'
      of 'u':
        var cp = hexDigits(p, 4)
        if cp >= 0xD800 and cp <= 0xDBFF and p.pos + 1 < p.s.len and
           p.s[p.pos] == '\\' and p.s[p.pos + 1] == 'u':
          let save = p.pos
          p.pos += 2
          let lo = hexDigits(p, 4)
          if lo >= 0xDC00 and lo <= 0xDFFF:
            cp = 0x10000 + ((cp - 0xD800) shl 10) + (lo - 0xDC00)
          else:
            p.pos = save
        result.addUtf8 cp
      else:
        if not p.json5:
          dec p.pos
          fail(p, "Bad escaped character in JSON")
        case e
        of '\'': result.add '\''
        of 'v': result.add '\v'
        of '0': result.add '\0'
        of 'x': result.addUtf8 hexDigits(p, 2)
        of '\n': discard                           # line continuation
        of '\r':
          if p.pos < p.s.len and p.s[p.pos] == '\n': inc p.pos
        else: result.add e
    elif c in {'\0'..'\31'} and not p.json5:
      fail(p, "Bad control character in string literal in JSON")
    else:
      result.add c
      inc p.pos

proc parseNumber(p: var Parser): float {.raises.} =
  let start = p.pos
  var sign = 1.0
  if p.pos < p.s.len and p.s[p.pos] in {'-', '+'}:
    if p.s[p.pos] == '+' and not p.json5: unexpected(p)
    if p.s[p.pos] == '-': sign = -1.0
    inc p.pos
  if p.json5:
    if p.s.continuesWith("Infinity", p.pos):
      p.pos += 8
      return sign * Inf
    if p.s.continuesWith("NaN", p.pos):
      p.pos += 3
      return NaN
    if p.pos + 1 < p.s.len and p.s[p.pos] == '0' and p.s[p.pos + 1] in {'x', 'X'}:
      p.pos += 2
      var v = 0.0
      var any = false
      while p.pos < p.s.len and p.s[p.pos] in HexDigits:
        let c = p.s[p.pos]
        let d = if c in {'0'..'9'}: ord(c) - ord('0')
                elif c in {'a'..'f'}: ord(c) - ord('a') + 10
                else: ord(c) - ord('A') + 10
        v = v * 16.0 + float(d)
        any = true
        inc p.pos
      if not any: unexpected(p)
      return sign * v
  let intStart = p.pos
  while p.pos < p.s.len and p.s[p.pos] in {'0'..'9'}: inc p.pos
  let intLen = p.pos - intStart
  if intLen == 0 and not (p.json5 and p.pos < p.s.len and p.s[p.pos] == '.'):
    unexpected(p)
  if not p.json5 and intLen > 1 and p.s[intStart] == '0':
    p.pos = intStart + 1
    unexpected(p)
  if p.pos < p.s.len and p.s[p.pos] == '.':
    inc p.pos
    let fracStart = p.pos
    while p.pos < p.s.len and p.s[p.pos] in {'0'..'9'}: inc p.pos
    if p.pos == fracStart and (not p.json5 or intLen == 0): unexpected(p)
  if p.pos < p.s.len and p.s[p.pos] in {'e', 'E'}:
    inc p.pos
    if p.pos < p.s.len and p.s[p.pos] in {'+', '-'}: inc p.pos
    let expStart = p.pos
    while p.pos < p.s.len and p.s[p.pos] in {'0'..'9'}: inc p.pos
    if p.pos == expStart: unexpected(p)
  var ok = false
  let v = jsNumber(p.s.substr(start, p.pos - 1), ok)
  if not ok:
    p.pos = start
    unexpected(p)
  result = v

proc isIdentStart(c: char): bool {.inline.} =
  c in {'a'..'z', 'A'..'Z', '_', '$'} or ord(c) >= 0x80

proc isIdentPart(c: char): bool {.inline.} =
  isIdentStart(c) or c in {'0'..'9'}

proc parseValue(p: var Parser; depth: int): JsonValue {.raises.}

proc parseKey(p: var Parser): string {.raises.} =
  result = ""
  if p.pos >= p.s.len: unexpected(p)
  let c = p.s[p.pos]
  if c == '"' or (p.json5 and c == '\''):
    return parseString(p)
  if p.json5 and isIdentStart(c):
    while p.pos < p.s.len and isIdentPart(p.s[p.pos]):
      result.add p.s[p.pos]
      inc p.pos
    return
  unexpected(p)

proc parseValue(p: var Parser; depth: int): JsonValue {.raises.} =
  if depth > 512: fail(p, "Nesting too deep")
  skipWs(p)
  if p.pos >= p.s.len: unexpected(p)
  let c = p.s[p.pos]
  case c
  of '{':
    inc p.pos
    result = newJObject()
    skipWs(p)
    if p.pos < p.s.len and p.s[p.pos] == '}':
      inc p.pos
      return
    while true:
      skipWs(p)
      if p.json5 and p.pos < p.s.len and p.s[p.pos] == '}':
        inc p.pos                                  # trailing comma
        return
      let key = parseKey(p)
      skipWs(p)
      if p.pos >= p.s.len or p.s[p.pos] != ':': unexpected(p)
      inc p.pos
      result[key] = parseValue(p, depth + 1)
      skipWs(p)
      if p.pos >= p.s.len: unexpected(p)
      if p.s[p.pos] == ',':
        inc p.pos
      elif p.s[p.pos] == '}':
        inc p.pos
        return
      else:
        unexpected(p)
  of '[':
    inc p.pos
    result = newJArray()
    skipWs(p)
    if p.pos < p.s.len and p.s[p.pos] == ']':
      inc p.pos
      return
    while true:
      skipWs(p)
      if p.json5 and p.pos < p.s.len and p.s[p.pos] == ']':
        inc p.pos
        return
      result.elems.add parseValue(p, depth + 1)
      skipWs(p)
      if p.pos >= p.s.len: unexpected(p)
      if p.s[p.pos] == ',':
        inc p.pos
      elif p.s[p.pos] == ']':
        inc p.pos
        return
      else:
        unexpected(p)
  of '"':
    result = newJString(parseString(p))
  of '\'':
    if not p.json5: unexpected(p)
    result = newJString(parseString(p))
  of 't':
    if not p.s.continuesWith("true", p.pos): unexpected(p)
    p.pos += 4
    result = newJBool(true)
  of 'f':
    if not p.s.continuesWith("false", p.pos): unexpected(p)
    p.pos += 5
    result = newJBool(false)
  of 'n':
    if not p.s.continuesWith("null", p.pos): unexpected(p)
    p.pos += 4
    result = newJNull()
  else:
    result = newJNumber(parseNumber(p))

proc parse(p: var Parser): JsonValue {.raises.} =
  result = parseValue(p, 0)
  skipWs(p)
  if p.pos < p.s.len: unexpected(p)

proc tryParseJson*(s: string; dest: var Maybe; err: var string;
                   json5 = false): bool =
  ## `JSON.parse`, or `JSON5.parse` with `json5 = true`. On failure `err` is
  ## `line:col: what` — nimony's `ErrorCode` cannot carry a message, so the
  ## message travels beside it.
  var p = Parser(s: s, pos: 0, json5: json5, err: "")
  try:
    dest = parse(p)
    result = true
  except ErrorCode:
    dest = nil
    err = p.err
    result = false

proc parseJson*(s: string; json5 = false): JsonValue {.raises.} =
  ## As `tryParseJson`, raising `SyntaxError` and dropping the message.
  var p = Parser(s: s, pos: 0, json5: json5, err: "")
  result = parse(p)
