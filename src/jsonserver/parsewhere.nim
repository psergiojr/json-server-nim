# Port of json-server src/parse-where.ts: a query string of `field:op=value`
# pairs (or the v0.17 spelling `field_op=value`) to a `where` object.

import std / [strutils, uri]
import jsonvalue, whereoperators, dotprop

type
  KeyOp = object
    path: string
    op: string     ## "" when the key names an operator that does not exist

proc splitKey(key: string): KeyOp =
  let colon = key.rfind(':')
  if colon != -1:
    let path = key.substr(0, colon - 1)
    let op = key.substr(colon + 1)
    if op.len == 0: return KeyOp(path: key, op: "eq")
    return if isWhereOperator(op): KeyOp(path: path, op: op)
           else: KeyOp(path: path, op: "")
  # Compatibility with v0.17 operator style (e.g. _lt, _gt): /^(.*)_([a-z]+)$/
  var j = key.len
  while j > 0 and key[j - 1] in {'a'..'z'}: dec j
  if j < key.len and j > 0 and key[j - 1] == '_':
    let path = key.substr(0, j - 2)
    let op = key.substr(j)
    if path.len > 0 and isWhereOperator(op): return KeyOp(path: path, op: op)
  result = KeyOp(path: key, op: "eq")

proc coerceValue*(value: string): JsonValue =
  if value == "true": return newJBool(true)
  if value == "false": return newJBool(false)
  if value == "null": return newJNull()
  if value.strip().len == 0: return newJString(value)
  var ok = false
  let n = jsNumber(value, ok)
  if ok and n == n and n != Inf and n != -Inf: return newJNumber(n)
  result = newJString(value)

proc setPathOp(root: JsonValue; path, op, value: string) =
  let fullPath = path & "." & op
  if op == "in":
    let arr = newJArray()
    for part in value.split(','): arr.add coerceValue(part.strip())
    setProperty(root, fullPath, arr)
  else:
    setProperty(root, fullPath, coerceValue(value))

proc parseWherePairs*(pairs: openArray[(string, string)]): JsonValue =
  ## As `parseWhere`, on a query string already split and decoded.
  result = newJObject()
  for (rawKey, rawValue) in pairs:
    let ko = splitKey(rawKey)
    if ko.op.len == 0: continue
    setPathOp(result, ko.path, ko.op, rawValue)

proc parseWhere*(query: string): JsonValue =
  var pairs: seq[(string, string)] = @[]
  for kv in decodeQuery(query): pairs.add kv
  result = parseWherePairs(pairs)
