# A minimal node:test stand-in: `test` groups checks, `check` records a
# failure with its source line instead of stopping, `finish` sets the exit code.

import std / syncio
import ../src/jsonserver/jsonvalue

var failures* = 0
var passed* = 0
var current = ""

template test*(name: string; body: untyped) =
  block:
    let before = failures
    current = name
    body
    if failures == before:
      inc passed
      echo "ok - ", name
    else:
      echo "not ok - ", name

proc fail*(msg: string; file: string; line: int) =
  inc failures
  echo "  # ", file, ":", line, ": ", msg

template check*(cond: bool; msg = "check failed") =
  if not cond:
    let ii = instantiationInfo()
    fail(msg, ii.filename, ii.line)

template checkJson*(actual: Maybe; expected: Maybe) =
  if not deepEqual(actual, expected):
    let ii = instantiationInfo()
    fail("expected " & toJson(expected) & ", got " & toJson(actual),
         ii.filename, ii.line)

proc j*(s: string): JsonValue =
  ## A JSON literal in a test; JSON5 so keys need no quotes.
  var v: Maybe = nil
  var err = ""
  if not tryParseJson(s, v, err, json5 = true) or v == nil:
    echo "bad JSON literal in test: ", err, "\n", s
    quit(2)
  result = v

proc jstrict*(s: string): JsonValue =
  ## `JSON.parse` that must succeed.
  var v: Maybe = nil
  var err = ""
  if not tryParseJson(s, v, err) or v == nil:
    echo "bad JSON in test: ", err, "\n", s
    quit(2)
  result = v

proc finish*() =
  echo "# pass ", passed, ", fail ", failures
  if failures > 0: quit(1)
