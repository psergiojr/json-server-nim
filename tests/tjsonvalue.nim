# Not in upstream: JSON.parse / JSON.stringify / JSON5.parse come from the JS
# runtime there. These pin the behaviors json-server's output depends on.

import harness
import ../src/jsonserver / [jsonvalue, jsops]

test "Number.prototype.toString":
  for (x, s) in [(100.0, "100"), (0.5, "0.5"), (-3.0, "-3"), (1e21, "1e+21"),
                 (1e20, "100000000000000000000"), (1.5e-7, "1.5e-7"),
                 (0.000001, "0.000001"), (123.456, "123.456"), (0.0, "0"),
                 (0.1 + 0.2, "0.30000000000000004"), (-0.0, "0"),
                 (2.5e+25, "2.5e+25"), (9007199254740993.0, "9007199254740992")]:
    check jsNumberToString(x) == s, $x & " -> " & jsNumberToString(x) & ", want " & s

test "JSON.stringify round trip":
  let src = """{"a":[1,2.5,"x\n\"\u0001",null,true,false],"b":{},"c":[],"é":"ü"}"""
  check toJson(jstrict(src)) == src

test "JSON.stringify with indent 2":
  check toJson(j"{a: [1, {}], b: {c: null}, d: []}", 2) ==
    "{\n  \"a\": [\n    1,\n    {}\n  ],\n  \"b\": {\n    \"c\": null\n  },\n  \"d\": []\n}"

test "strict JSON rejects JSON5":
  for bad in ["{a: 1}", "[1,]", "'x'", "+1", "01", "1.", ".5", "NaN", "// c\n1",
              "{\"a\":1}x", "", "[", "\"\t\""]:
    var v: Maybe = nil
    var err = ""
    check not tryParseJson(bad, v, err), "accepted: " & bad

test "parse error names line and column":
  var v: Maybe = nil
  var err = ""
  check not tryParseJson("{\n  \"a\": x\n}", v, err)
  check err == "2:8: Unexpected token 'x'", err

test "JSON5":
  let v = j("""
    // comment
    {
      unquoted: 'single',
      "trailing": [1, 2,],
      hex: 0x10, lead: .5, trail: 5., plus: +1,
      /* block */ inf: Infinity,
      multi: 'a\
b',
    }""")
  checkJson v, j"""{"unquoted": "single", "trailing": [1, 2], "hex": 16,
                   "lead": 0.5, "trail": 5, "plus": 1, "inf": Infinity, "multi": "ab"}"""

test "unicode escapes and surrogate pairs":
  check jstrict("\"\\u00e9\\ud83d\\ude00\"") == "é😀"

test "Number(string)":
  for (s, ok, x) in [("12", true, 12.0), (" 12 ", true, 12.0), ("0x1f", true, 31.0),
                     ("1e3", true, 1000.0), ("-.5", true, -0.5), ("12abc", false, 0.0),
                     ("", true, 0.0), ("Infinity", true, Inf), ("1_000", false, 0.0)]:
    var got = false
    let n = jsNumber(s, got)
    check got == ok and (not ok or n == x), "Number(" & s & ")"

test "strictEq is identity for objects":
  let a = j"{x: 1}"
  check strictEq(a, a)
  check not strictEq(a, j"{x: 1}")
  check deepEqual(a, j"{x: 1}")
  check strictEq(newJString("a"), newJString("a"))
  check strictEq(nil, nil)
  check not strictEq(nil, newJNull())

test "relational comparison":
  check jsLt(newJNumber(2), newJString("10"))        # number vs numeric string
  check jsLt(newJString("10"), newJString("2"))      # string vs string
  check not jsLt(newJString("a"), newJNumber(1))     # NaN
  check not jsLe(newJString("a"), newJNumber(1))
  check jsLt(newJNull(), newJNumber(1))
  check jsGe(newJBool(true), newJNumber(1))

finish()
