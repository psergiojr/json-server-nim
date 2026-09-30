# The subset of the `dot-prop` npm package json-server uses: `getProperty` (via
# sort-on) and `setProperty` (via parse-where), with dot-prop's path grammar —
# `a.b`, `a\.b` for a literal dot, `a[0]` for an index, and `__proto__`,
# `prototype`, `constructor` refused outright.

import std / [strutils, parseutils]
import jsonvalue

type
  Segment* = object
    key*: string
    isIndex*: bool   ## a non-negative integer, which JS uses as an array index
    index*: int

const MaxArrayIndex = 1_000_000

proc isDisallowed(s: string): bool =
  s == "__proto__" or s == "prototype" or s == "constructor"

proc toInt(s: string): int =
  ## Digits only, at most 7 of them — the callers check both.
  var n: BiggestInt = 0
  discard parseBiggestInt(s, n)
  result = int(n)

proc shouldCoerce(s: string): bool =
  if s == "0": return true
  if s.len == 0 or s.len > 7 or s[0] notin {'1'..'9'}: return false
  for c in s:
    if c notin {'0'..'9'}: return false
  result = toInt(s) <= MaxArrayIndex

proc toSegment(s: string): Segment =
  if shouldCoerce(s): Segment(key: s, isIndex: true, index: toInt(s))
  else: Segment(key: s, isIndex: false, index: 0)

proc parsePath*(path: string; ok: var bool): seq[Segment] =
  ## `ok = false` where dot-prop throws (a malformed index). A disallowed key
  ## yields an empty path, as in dot-prop.
  type Part = enum pStart, pProperty, pIndex, pIndexEnd
  ok = true
  result = @[]
  var cur = ""
  var idx = ""
  var hadProperty = false
  var part = pStart
  var escaping = false
  for ch in path:
    if escaping:
      cur.add ch
      escaping = false
      continue
    if ch == '\\':
      if part in {pIndex, pIndexEnd}:
        ok = false
        return @[]
      escaping = true
      if part == pStart: part = pProperty
      continue
    case ch
    of '.':
      if part == pIndex:
        ok = false
        return @[]
      if part == pIndexEnd:
        part = pProperty
      else:
        if isDisallowed(cur): return @[]
        result.add toSegment(cur)
        cur = ""
        part = pProperty
    of '[':
      if part == pIndex:
        ok = false
        return @[]
      if part == pIndexEnd:
        part = pIndex
      else:
        if part == pProperty and isDisallowed(cur): return @[]
        hadProperty = part == pProperty
        part = pIndex
    of ']':
      if part == pIndexEnd:
        ok = false
        return @[]
      if part != pIndex:
        if part == pStart: part = pProperty
        cur.add ch
      elif idx.len == 0:
        cur.add "[]"
        part = pProperty
      else:
        if cur.len > 0 or hadProperty:
          if isDisallowed(cur): return @[]
          result.add toSegment(cur)
        cur = ""
        hadProperty = false
        let valid = idx.len <= 7 and (idx == "0" or idx[0] != '0') and
                    toInt(idx) <= MaxArrayIndex
        if valid: result.add Segment(key: idx, isIndex: true, index: toInt(idx))
        else: result.add Segment(key: idx, isIndex: false, index: 0)
        idx = ""
        part = pIndexEnd
    else:
      if part == pIndex:
        if ch notin {'0'..'9'}:
          ok = false
          return @[]
        idx.add ch
      elif part == pIndexEnd:
        ok = false
        return @[]
      else:
        if part == pStart: part = pProperty
        cur.add ch
  if escaping: cur.add '\\'
  case part
  of pProperty:
    if isDisallowed(cur): return @[]
    result.add toSegment(cur)
  of pIndex:
    ok = false
    return @[]
  of pStart:
    result.add Segment(key: "", isIndex: false, index: 0)
  of pIndexEnd: discard

proc member(v: JsonValue; s: Segment): Maybe =
  ## `v[s]` for an object or array.
  if v.kind == JArray:
    if s.isIndex and s.index < v.elems.len: result = v.elems[s.index]
    else: result = nil
  elif v.kind == JObject:
    result = v[s.key]
  else:
    result = nil

proc getProperty*(obj: Maybe; path: string): Maybe =
  ## `getProperty(obj, path)`: undefined for a missing link or a malformed path.
  if obj == nil or obj.kind notin {JObject, JArray}: return obj
  var ok = false
  let segs = parsePath(path, ok)
  if not ok or segs.len == 0: return nil
  var cur: Maybe = obj
  for i, s in segs:
    if cur == nil: return nil
    if cur.kind notin {JObject, JArray}:
      return nil
    cur = member(cur, s)
    if cur == nil or cur.kind == JNull:
      if i != segs.len - 1: return nil
  result = cur

proc assign(v: JsonValue; s: Segment; x: JsonValue) =
  if v.kind == JArray and s.isIndex:
    while v.elems.len <= s.index: v.elems.add newJNull()   # a hole prints as null
    v.elems[s.index] = x
  elif v.kind == JObject:
    v[s.key] = x

proc setProperty*(obj: JsonValue; path: string; value: JsonValue) =
  ## `setProperty(obj, path, value)`, creating objects (or arrays, before an
  ## index) along the way and overwriting primitives in the way.
  if obj.kind notin {JObject, JArray}: return
  var ok = false
  let segs = parsePath(path, ok)
  if not ok or segs.len == 0: return
  var cur = obj
  for i, s in segs:
    if i == segs.len - 1:
      assign(cur, s, value)
    else:
      let existing = member(cur, s)
      if existing != nil and existing.kind in {JObject, JArray}:
        cur = existing
      else:
        let fresh = if segs[i + 1].isIndex: newJArray() else: newJObject()
        assign(cur, s, fresh)
        cur = fresh
