# Port of json-server src/where-operators.ts.

const WhereOperators* = ["lt", "lte", "gt", "gte", "eq", "ne", "in",
                         "contains", "startsWith", "endsWith"]

proc isWhereOperator*(s: string): bool =
  for op in WhereOperators:
    if op == s: return true
  result = false
