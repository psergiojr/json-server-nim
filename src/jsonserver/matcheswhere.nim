# Port of json-server src/matches-where.ts.

import std / strutils
import jsonvalue, jsops, whereoperators

proc knownOperators(value: JsonValue): seq[string] =
  result = @[]
  for op in WhereOperators:
    if value.hasKey(op): result.add op

proc matchesWhere*(obj: JsonValue; where: JsonValue): bool =
  for key, value in where:
    if key == "or":
      if not value.isArray or value.len == 0: return false
      var matched = false
      for sub in value:
        if sub.isObject and matchesWhere(obj, sub):
          matched = true
          break
      if not matched: return false
      continue

    let field = obj[key]

    if value.isObject:
      let ops = knownOperators(value)
      if ops.len > 0:
        if field == nil: return false
        if "lt" in ops and not jsLt(field, value["lt"]): return false
        if "lte" in ops and not jsLe(field, value["lte"]): return false
        if "gt" in ops and not jsGt(field, value["gt"]): return false
        if "gte" in ops and not jsGe(field, value["gte"]): return false
        if "eq" in ops and not strictEq(field, value["eq"]): return false
        if "ne" in ops and strictEq(field, value["ne"]): return false
        if "in" in ops:
          let inv = value["in"]
          var any = false
          if inv.isArray:
            for v in inv:
              if strictEq(field, v):
                any = true
                break
          else:
            any = strictEq(field, inv)
          if not any: return false
        if "contains" in ops:
          if not field.isString: return false
          if not jsLower(field.str).contains(jsLower(jsString(value["contains"]))):
            return false
        if "startsWith" in ops:
          if not field.isString: return false
          if not jsLower(field.str).startsWith(jsLower(jsString(value["startsWith"]))):
            return false
        if "endsWith" in ops:
          if not field.isString: return false
          if not jsLower(field.str).endsWith(jsLower(jsString(value["endsWith"]))):
            return false
        continue

      if field.isObject:
        if not matchesWhere(field, value): return false
      continue

    # A bare value (not an operator object) never matches: the upstream code
    # returns false here whether or not the field exists.
    return false

  result = true
