# Just enough of `fetch` for the HTTP-level tests: one request per
# connection, `Connection: close`, read to EOF, split status/headers/body.
#
# A `.passive` chain resumed by pool workers, driven from the main thread by
# `fetch`, which submits it and waits — the same shape as nimony's own
# tests/nimony/http/tserver.nim.

import std / [httpserver, socket, ioring, threadpool, atomics, strutils]

type
  FetchResponse* = object
    status*: int
    headers*: seq[(string, string)]   ## names lowercase
    body*: string
    raw*: string

var gPort = 0
var gDone: int = 0
var gRequest = ""
var gReply = ""

proc exchange(request: string): string {.passive.} =
  result = ""
  let fd = socketNonBlocking()
  var sa = default(Sockaddr_storage)
  var sl = default(SockLen)
  loopbackAddr(sa, sl, uint16(gPort))
  var r = 0
  let k = delay()
  discard submitConnect(cint(fd), sa, sl, afterMs(5000), k, addr r)
  suspend()
  if r != 0:
    closeFd(cint(fd))
    return "CONNECT FAILED " & $r
  var sock = initSocket(cint(fd), afterMs(5000))
  try:
    sock.write(toOpenArray(request, 0, request.len - 1))
    while true:
      if sock.fill() == 0: break
    let n = sock.buffered
    for i in 0 ..< n: result.add sock.peek[i]
    sock.consume n
  except ErrorCode as e:
    result.add "\nCLIENT " & $e

proc runOne() {.passive.} =
  gReply = exchange(gRequest)
  atomicStore(gDone, 1, moRelease)

proc setPort*(port: int) = gPort = port

proc parseResponse(raw: string): FetchResponse =
  result = FetchResponse(status: 0, headers: @[], body: "", raw: raw)
  let headEnd = raw.find("\r\n\r\n")
  if headEnd < 0: return
  let lines = raw.substr(0, headEnd - 1).split("\r\n")
  let parts = lines[0].split(' ')
  if parts.len >= 2:
    var st = 0
    for ch in parts[1]:
      if ch in {'0'..'9'}: st = st * 10 + (ord(ch) - ord('0'))
    result.status = st
  for i in 1 ..< lines.len:
    let colon = lines[i].find(':')
    if colon > 0:
      result.headers.add((lines[i].substr(0, colon - 1).toLowerAscii,
                          lines[i].substr(colon + 1).strip()))
  result.body = raw.substr(headEnd + 4)

proc header*(r: FetchResponse; name: string): string =
  for (k, v) in r.headers:
    if k == name: return v
  result = ""

proc fetch*(meth, target: string; body = ""; contentType = "";
            extraHeaders: seq[(string, string)] = @[]): FetchResponse =
  var req = meth & " " & target & " HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n"
  if contentType.len > 0: req.add "Content-Type: " & contentType & "\r\n"
  for (k, v) in extraHeaders: req.add k & ": " & v & "\r\n"
  if body.len > 0 or meth in ["POST", "PUT", "PATCH"]:
    req.add "Content-Length: " & $body.len & "\r\n"
  req.add "\r\n"
  req.add body
  gRequest = req
  atomicStore(gDone, 0, moRelease)
  submit(delay(runOne()), 1)
  let start = monoNow()
  while atomicLoad(gDone, moAcquire) == 0:
    if millisUntil(monoNow(), start) > 20_000: break
  result = parseResponse(gReply)
