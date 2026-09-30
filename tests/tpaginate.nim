# Adapted from json-server src/paginate.test.ts.

import harness
import ../src/jsonserver / [jsonvalue, paginate]

proc items(s: string): seq[JsonValue] = j(s).elems

test "page=1 perPage=2 items=5 -> [1,2]":
  checkJson paginate(items"[1,2,3,4,5]", 1, 2),
    j"{first: 1, prev: null, next: 2, last: 3, pages: 3, items: 5, data: [1, 2]}"

test "page=2 perPage=2 items=5 -> [3,4]":
  checkJson paginate(items"[1,2,3,4,5]", 2, 2),
    j"{first: 1, prev: 1, next: 3, last: 3, pages: 3, items: 5, data: [3, 4]}"

test "page=9 perPage=2 items=5 -> clamp to last":
  checkJson paginate(items"[1,2,3,4,5]", 9, 2),
    j"{first: 1, prev: 2, next: null, last: 3, pages: 3, items: 5, data: [5]}"

test "page=0 perPage=2 items=3 -> clamp to first":
  checkJson paginate(items"[1,2,3]", 0, 2),
    j"{first: 1, prev: null, next: 2, last: 2, pages: 2, items: 3, data: [1, 2]}"

test "items=[] page=1 perPage=2 -> stable empty pagination":
  checkJson paginate(items"[]", 1, 2),
    j"{first: 1, prev: null, next: null, last: 1, pages: 1, items: 0, data: []}"

test "perPage=0 -> clamp perPage to 1":
  checkJson paginate(items"[1,2,3]", 1, 0),
    j"{first: 1, prev: null, next: 2, last: 3, pages: 3, items: 3, data: [1]}"

finish()
