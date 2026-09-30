# Port of the `sort-on` npm package, for string properties: `-prop` sorts
# descending, `a.b` reaches into nested objects, and later properties break
# ties. Stable, like `Array.prototype.sort`.

import jsonvalue, jsops, dotprop

proc isZero(v: Maybe): bool =
  # Not `v != nil and v.kind == JNumber and v.num == 0.0`: nimony loses the
  # nil fact across a chained `and` (friction/0004).
  if v == nil: return false
  result = v.kind == JNumber and v.num == 0.0

proc compareOn(a, b: JsonValue; props: seq[string]): int =
  result = 0
  for element in props:
    let desc = element.len > 0 and element[0] == '-'
    let prop = if desc: element.substr(1) else: element
    let x = getProperty(a, prop)
    let y = getProperty(b, prop)
    if strictEq(x, y): continue
    # Falsy values (0 excepted) go last ascending, first descending — sort-on's
    # `if (y !== 0 && !y)` / `if (x !== 0 && !x)` pair, in that order.
    if not isZero(y) and isFalsy(y): return (if desc: 1 else: -1)
    if not isZero(x) and isFalsy(x): return (if desc: -1 else: 1)
    if x.isString and y.isString:
      let c = if desc: localeCompare(y.str, x.str) else: localeCompare(x.str, y.str)
      if c != 0: return c
      continue
    let lt = jsLt(x, y)
    return if desc: (if lt: 1 else: -1) else: (if lt: -1 else: 1)

proc sortOn*(items: seq[JsonValue]; props: seq[string]): seq[JsonValue] =
  ## A bottom-up merge sort: stable, and written out because `algorithm.sort`
  ## takes a nimcall comparator and this one needs `props`.
  result = items
  var buf = items
  var width = 1
  let n = result.len
  while width < n:
    var lo = 0
    while lo < n:
      let mid = min(lo + width, n)
      let hi = min(lo + 2 * width, n)
      var i = lo
      var j = mid
      var k = lo
      while i < mid and j < hi:
        if compareOn(result[j], result[i], props) < 0:
          buf[k] = result[j]
          inc j
        else:
          buf[k] = result[i]
          inc i
        inc k
      while i < mid:
        buf[k] = result[i]
        inc i
        inc k
      while j < hi:
        buf[k] = result[j]
        inc j
        inc k
      lo = hi
    swap(result, buf)
    width = width * 2
