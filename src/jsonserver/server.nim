# `app.handle` on a socket: `std/httpserver` for HTTP/1.1, one `.passive`
# chain per connection, resumed by pool workers.
#
# Connections run on several workers at once and the database is one mutable
# tree, so every `handle` call holds `gLock`. That is also what json-server
# gets from Node's single thread: requests never interleave inside the service.

import std / [httpserver, ioring, threadpool, atomics, locks, strutils]
import app

let gTags = newHttpTags()
var gLock: Lock
var gApp: nil App = nil
var gPort: int = 0
var gListening: int = 0
var gStop: int = 0
var gListenFd: int = -1

proc methodName(c: HttpConnection): string =
  let t = c.meth
  if t == tag(mGet): "GET"
  elif t == tag(mHead): "HEAD"
  elif t == tag(mPost): "POST"
  elif t == tag(mPut): "PUT"
  elif t == tag(mPatch): "PATCH"
  elif t == tag(mDelete): "DELETE"
  elif t == tag(mOptions): "OPTIONS"
  else: name(gTags, t)

proc otherHeaders(c: HttpConnection): seq[(string, string)] =
  ## Not inlined into `toRequest`: `httpmsg.otherHeaders` wraps its body in
  ## `{.cast(noSideEffect).}`, and looping over such an iterator inside a
  ## `.passive` proc crashes hexer (friction/0001).
  result = @[]
  for (k, v) in c.request.otherHeaders:
    result.add((k.toLowerAscii, v))

proc toRequest(c: var HttpConnection): Request {.passive.} =
  result = Request(meth: methodName(c), path: c.path, query: c.query,
                   headers: otherHeaders(c), body: "", bodyTooLarge: false)
  if c.hasBody:
    try:
      result.body = c.readBody(PayloadLimit)
    except ErrorCode as e:
      if e == ContentTooLong: result.bodyTooLarge = true
      else: result.body = ""

proc dispatch(req: Request): Response =
  acquire gLock
  let a = gApp
  if a != nil:
    result = a.handle(req)
  else:
    result = Response(status: 503, headers: @[], body: "")
  release gLock

proc handleConn(c: sink HttpConnection) {.passive.} =
  ## `sink`, not `var`: this chain outlives the accept loop that started it.
  var m = initHttpMsg(gTags)
  while c.next():
    try:
      let req = toRequest(c)
      let res = dispatch(req)
      c.prepare(m, res.status)
      for (k, v) in res.headers:
        if k == "Content-Type": m.addHeader(hContentType, v)
        elif k == "Content-Length": discard    # `respond` owns framing
        else: m.addOtherHeader(k, v)
      c.respond(m, res.body)
    except ErrorCode:
      c.close()

proc acceptLoop(port: uint16) {.passive.} =
  var s = listenHttp(port, gTags)
  gListenFd = int(s.fd)
  atomicStore(gPort, int(boundPort(s.fd)), moRelease)
  atomicStore(gListening, 1, moRelease)
  while atomicLoad(gStop, moAcquire) == 0:
    let c = s.accept()
    if c.isClosed: break
    submit(delay(handleConn(c)), -1)
  s.close()
  atomicStore(gListening, 0, moRelease)

proc startServer*(a: App; port: int): int =
  ## Serve `a` on `port` (0: the kernel picks) from the pool. Returns the port
  ## actually bound once the listener is up, or -1 if it did not come up.
  initLock gLock
  gApp = a
  initIoRing()
  submit(delay(acceptLoop(uint16(port))), 0)
  let start = monoNow()
  while atomicLoad(gListening, moAcquire) == 0:
    if millisUntil(monoNow(), start) > 5000: return -1
  result = atomicLoad(gPort, moAcquire)

proc swapApp*(a: App) =
  ## Replace the app between requests, e.g. after the database file changed.
  acquire gLock
  gApp = a
  release gLock

template withAppLock*(body: untyped) =
  ## Run `body` with no request in flight.
  acquire gLock
  try:
    body
  finally:
    release gLock
