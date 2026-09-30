# Not in upstream (the `sort-on` package). Pins the orderings json-server's
# `_sort` exposes.

import harness
import ../src/jsonserver / [jsonvalue, sorton]

proc ids(items: seq[JsonValue]): string =
  result = ""
  for it in items: result.add it["id"].getStr

let items = j"""[
  {id: 'a', n: 2, s: 'b', o: {k: 3}},
  {id: 'b', n: 10, s: 'B', o: {k: 1}},
  {id: 'c', n: 2, s: 'a', o: {k: 2}},
  {id: 'd', s: '', o: {k: 0}},
  {id: 'e', n: 0, s: 'c'}]""".elems

test "numeric ascending, stable, falsy last":
  check ids(sortOn(items, @["n"])) == "eacbd", ids(sortOn(items, @["n"]))
test "descending":
  check ids(sortOn(items, @["-n"])) == "dbace", ids(sortOn(items, @["-n"]))
test "tie broken by second key":
  check ids(sortOn(items, @["n", "s"])) == "ecabd", ids(sortOn(items, @["n", "s"]))
test "strings compare like localeCompare":
  check ids(sortOn(items, @["s"])) == "cabed", ids(sortOn(items, @["s"]))
test "nested path":
  check ids(sortOn(items, @["o.k"])) == "dbcae", ids(sortOn(items, @["o.k"]))

test "localeCompare order (checked against node 24 / ICU)":
  var words = j"""[{id: 'b'}, {id: 'B'}, {id: 'a'}, {id: ''}, {id: 'c'}, {id: 'é'},
                   {id: 'e'}, {id: '_x'}, {id: '1'}, {id: 'Z'}]""".elems
  # sort-on puts '' (falsy) last; ICU puts the rest as below.
  var got = ""
  for w in sortOn(words, @["id"]): got.add w["id"].getStr & "|"
  check got == "_x|1|a|b|B|c|e|é|Z||", got

finish()
