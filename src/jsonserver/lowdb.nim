# The parts of `lowdb` json-server uses: `Low` (data + adapter), and the
# `Memory`, `JSONFile` and `DataFile` (JSON5) adapters, plus json-server's own
# `NormalizedAdapter` and `Observer` (src/adapters/*.ts).
#
# lowdb adapters are async and throw. Here they are synchronous (the server
# serializes every request under one lock anyway) and report failure through
# an `err` string, because an `ErrorCode` cannot say which line of db.json is
# broken.

import std / [os, syncio, strutils]
import jsonvalue, randomid

type
  Adapter* = ref object of RootObj

  Memory* = ref object of Adapter
    data: Maybe

  JsonFile* = ref object of Adapter
    ## `JSONFile`, or `DataFile` with JSON5 parse when `json5` is set. Writes
    ## are always plain JSON: every JSON document is a JSON5 document, and
    ## JSON5.stringify's unquoted keys are a formatting choice, not a
    ## requirement (see README).
    path*: string
    json5*: bool

  NormalizedAdapter* = ref object of Adapter
    inner: Adapter

  Hook* = proc () {.closure.}
  ReadHook* = proc (data: Maybe) {.closure.}

  Observer* = ref object of Adapter
    inner: Adapter
    onReadStart*: Hook
    onReadEnd*: ReadHook
    onWriteStart*: Hook
    onWriteEnd*: Hook

  Low* = ref object
    adapter*: Adapter
    data*: JsonValue

const DefaultSchemaPath* = "./node_modules/json-server/schema.json"

method read*(a: Adapter; err: var string): Maybe {.base.} =
  ## The stored document, or `nil` when there is none yet (lowdb's `null`).
  ## A document that exists but cannot be read sets `err`.
  result = nil

method write*(a: Adapter; data: JsonValue; err: var string) {.base.} =
  discard

# ----------------------------------------------------------------- Memory --

proc newMemory*(): Memory = Memory(data: nil)

method read*(a: Memory; err: var string): Maybe =
  let d = a.data
  if d == nil: result = nil
  else: result = copy(d)

method write*(a: Memory; data: JsonValue; err: var string) =
  a.data = copy(data)

proc stored*(a: Memory): Maybe = a.data

# --------------------------------------------------------------- JsonFile --

proc newJsonFile*(path: string; json5 = false): JsonFile =
  JsonFile(path: path, json5: json5)

method read*(a: JsonFile; err: var string): Maybe =
  result = nil
  if not fileExists(a.path): return nil
  var text = ""
  try:
    text = readFile(a.path)
  except ErrorCode as e:
    err = "cannot read " & a.path & ": " & $e
    return nil
  var v: Maybe = nil
  if not tryParseJson(text, v, err, a.json5):
    err = err
    return nil
  result = v

method write*(a: JsonFile; data: JsonValue; err: var string) =
  ## Atomic, as lowdb's steno writer: a temp file next to the target, then a
  ## rename over it, so a reader never sees half a document.
  let (dir, name, ext) = splitFile(a.path)
  let tmp = (if dir.len > 0: dir & "/" else: "") & "." & name & ext & ".tmp"
  try:
    writeFile(tmp, toJson(data, 2))
    if not tryMoveFSObject(tmp, a.path, false):
      err = "cannot replace " & a.path
  except ErrorCode as e:
    err = "cannot write " & a.path & ": " & $e

# ------------------------------------------------------ NormalizedAdapter --

proc newNormalizedAdapter*(inner: Adapter): NormalizedAdapter =
  NormalizedAdapter(inner: inner)

method read*(a: NormalizedAdapter; err: var string): Maybe =
  ## Drop `$schema`; make every array item's `id` a string, inventing one
  ## where it is missing.
  let data = a.inner.read(err)
  if data == nil: return nil
  data.delete("$schema")
  for _, value in data:
    for item in value:
      if item.isObject:
        let id = item["id"]
        if id == nil:
          item["id"] = newJString(randomId())
        elif id.kind == JNumber:
          item["id"] = newJString(jsNumberToString(id.num))
  result = data

method write*(a: NormalizedAdapter; data: JsonValue; err: var string) =
  let d = newJObject()
  d["$schema"] = newJString(DefaultSchemaPath)
  a.inner.write(spread(data, d), err)

# --------------------------------------------------------------- Observer --

proc noop() = discard
proc noopRead(data: Maybe) = discard

proc newObserver*(inner: Adapter): Observer =
  Observer(inner: inner, onReadStart: noop, onReadEnd: noopRead,
           onWriteStart: noop, onWriteEnd: noop)

method read*(a: Observer; err: var string): Maybe =
  a.onReadStart()
  result = a.inner.read(err)
  a.onReadEnd(result)

method write*(a: Observer; data: JsonValue; err: var string) =
  a.onWriteStart()
  a.inner.write(data, err)
  a.onWriteEnd()

# -------------------------------------------------------------------- Low --

proc newLow*(adapter: Adapter; defaultData: JsonValue): Low =
  Low(adapter: adapter, data: defaultData)

proc read*(db: Low; err: var string): bool =
  ## Load from the adapter; keep the current data when there is none.
  let d = db.adapter.read(err)
  if err.len > 0: return false
  if d != nil: db.data = d
  result = true

proc write*(db: Low; err: var string): bool =
  db.adapter.write(db.data, err)
  result = err.len == 0

proc write*(db: Low) =
  ## Fire-and-forget, the way the service awaits `db.write()` without
  ## catching: a failed write is reported, and the in-memory change stands.
  var err = ""
  if not db.write(err):
    stderr.writeLine err
