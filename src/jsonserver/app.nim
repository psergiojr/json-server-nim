# Port of json-server src/app.ts, as a pure function from a request to a
# response. The middleware chain upstream builds with tinyhttp is spelled out
# in `handle`, in the same order: static files, CORS, body parser, routes,
# the final `/:name` responder, and tinyhttp's own 404.
#
# No sockets here: `server.nim` adapts this to `std/httpserver`, and the unit
# of testing is a `Request` value.

import std / [strutils, uri, os, syncio, times]
import std / http / httpdate
import std / posix / posix
import jsonvalue, lowdb, service, parsewhere

type
  Request* = object
    meth*: string                    ## "GET", "POST", ...
    path*: string                    ## percent-decoded, normalized
    query*: string                   ## raw, still encoded
    headers*: seq[(string, string)]  ## names lowercase
    body*: string
    bodyTooLarge*: bool

  Response* = object
    status*: int
    headers*: seq[(string, string)]
    body*: string

  AppOptions* = object
    staticDirs*: seq[string]   ## extra static directories, after ./public

  App* = ref object
    db*: Low
    service*: Service
    staticDirs*: seq[string]

const
  PayloadLimit* = 102400   ## milliparsec's default, 100 KiB
  ReservedQueryKeys = ["_sort", "_page", "_per_page", "_embed", "_where"]
  IndexTemplate = slurp("../../views/index.html")

proc newApp*(db: Low; options = AppOptions(staticDirs: @[])): App =
  result = App(db: db, service: newService(db), staticDirs: @["public"])
  var cwd = "."
  try: cwd = getCurrentDir()
  except ErrorCode: discard
  for dir in options.staticDirs:
    if isAbsolute(dir): result.staticDirs.add dir
    else: result.staticDirs.add cwd & "/" & dir

proc header*(req: Request; name: string): string =
  for (k, v) in req.headers:
    if k == name: return v
  result = ""

proc header*(res: Response; name: string): string =
  let lname = name.toLowerAscii
  for (k, v) in res.headers:
    if k.toLowerAscii == lname: return v
  result = ""

proc setHeader(res: var Response; name, value: string) =
  for i in 0 ..< res.headers.len:
    if res.headers[i][0] == name:
      res.headers[i][1] = value
      return
  res.headers.add((name, value))

proc json(res: var Response; status: int; data: Maybe) =
  ## tinyhttp's `res.status(s).json(data)`: pretty-printed, two spaces.
  res.status = status
  res.setHeader("Content-Type", "application/json")
  res.body = toJson(data, 2)

proc errorJson(msg: string): JsonValue =
  result = newJObject()
  result["error"] = newJString(msg)

proc plainError(res: var Response; status: int; msg: string) =
  ## tinyhttp's `onErrorHandler`: plain text, never sniffed as HTML.
  res.status = status
  res.setHeader("Content-Type", "text/plain; charset=utf-8")
  res.setHeader("X-Content-Type-Options", "nosniff")
  res.body = msg

# ----------------------------------------------------------- static files --

proc mimeType(path: string): string =
  ## sirv's `mrmime` lookup; only `text/html` gets a charset, and an unknown
  ## extension gets an empty type, both exactly as sirv does.
  let ext = path.substr(path.rfind('.') + 1).toLowerAscii
  case ext
  of "html", "htm": "text/html;charset=utf-8"
  of "css": "text/css"
  of "js", "mjs": "text/javascript"
  of "json", "map": "application/json"
  of "txt": "text/plain"
  of "md": "text/markdown"
  of "svg": "image/svg+xml"
  of "png": "image/png"
  of "jpg", "jpeg": "image/jpeg"
  of "gif": "image/gif"
  of "webp": "image/webp"
  of "ico": "image/vnd.microsoft.icon"
  of "wasm": "application/wasm"
  of "woff": "font/woff"
  of "woff2": "font/woff2"
  of "pdf": "application/pdf"
  of "xml": "application/xml"
  else: ""

proc lastModified(file: string): string =
  var st = default(Stat)
  var f = file
  if stat(f.toCString, st) != 0: return ""
  result = formatHttpDate(initTime(int64(st.st_mtim.tv_sec), 0))

proc serveStatic(app: App; req: Request; res: var Response): bool =
  ## `sirv(dir)` for each directory: the path itself, then with `.html` /
  ## `.htm`, then as a directory's `index.html` / `index.htm`.
  if req.meth != "GET" and req.meth != "HEAD": return false
  let p = if req.path.endsWith("/"): req.path.substr(0, req.path.len - 2)
          else: req.path
  var candidates: seq[string] = @[]
  if p.len > 0:
    for ext in ["", ".html", ".htm"]: candidates.add p & ext
  for idx in ["/index.html", "/index.htm"]: candidates.add p & idx
  for dir in app.staticDirs:
    for c in candidates:
      let file = dir & c
      if fileExists(file):
        try:
          res.body = readFile(file)
        except ErrorCode:
          continue
        res.status = 200
        res.setHeader("Content-Type", mimeType(file))
        res.setHeader("Last-Modified", lastModified(file))
        res.setHeader("Cache-Control", "no-store")   # sirv's dev mode
        return true
  result = false

# ------------------------------------------------------------------- CORS --

proc cors(req: Request; res: var Response) =
  ## `@tinyhttp/cors` with json-server's options: any origin, and the
  ## preflight's requested headers echoed back (`content-type` by default).
  res.setHeader("Access-Control-Allow-Origin", "*")
  res.setHeader("Access-Control-Allow-Methods", "GET, HEAD, PUT, PATCH, POST, DELETE")
  let requested = req.header("access-control-request-headers")
  if requested.len > 0:
    var names: seq[string] = @[]
    for h in requested.split(','): names.add h.strip()
    res.setHeader("Access-Control-Allow-Headers", names.join(","))
  else:
    res.setHeader("Access-Control-Allow-Headers", "content-type")

# ------------------------------------------------------------------ query --

proc jsParseInt(s: string; ok: var bool): int =
  ## `Number.parseInt(s, 10)`: optional whitespace and sign, then the longest
  ## run of digits; `ok = false` where JS answers NaN.
  var i = 0
  while i < s.len and s[i] in Whitespace: inc i
  var neg = false
  if i < s.len and s[i] in {'+', '-'}:
    neg = s[i] == '-'
    inc i
  let start = i
  result = 0
  while i < s.len and s[i] in {'0'..'9'}:
    if result < 100_000_000: result = result * 10 + (ord(s[i]) - ord('0'))
    inc i
  ok = i > start
  if neg: result = -result

proc queryAll(query, key: string): seq[string] =
  ## `req.query[key]` as tinyhttp parses it, always as a list.
  result = @[]
  for (k, v) in decodeQuery(query):
    if k == key: result.add v

proc queryFirst(query, key: string; found: var bool): string =
  ## `URLSearchParams.get(key)`.
  found = false
  result = ""
  for (k, v) in decodeQuery(query):
    if k == key:
      found = true
      return v

proc parseListParams(query: string): FindOpts =
  var filters: seq[(string, string)] = @[]
  for (k, v) in decodeQuery(query):
    if k notin ReservedQueryKeys: filters.add((k, v))
  result = FindOpts(where: parseWherePairs(filters), sort: "", page: 0,
                    hasPage: false, perPage: 0, hasPerPage: false,
                    embed: queryAll(query, "_embed"))

  var found = false
  let rawWhere = queryFirst(query, "_where", found)
  if found:
    # Invalid JSON, or JSON that is not an object/array, is ignored.
    var parsed: Maybe = nil
    var err = ""
    if tryParseJson(rawWhere, parsed, err) and parsed != nil:
      if parsed.kind in {JObject, JArray}: result.where = parsed

  let sort = queryFirst(query, "_sort", found)
  if found: result.sort = sort
  var ok = false
  let page = jsParseInt(queryFirst(query, "_page", found), ok)
  if found and ok:
    result.page = page
    result.hasPage = true
  let perPage = jsParseInt(queryFirst(query, "_per_page", found), ok)
  if found and ok:
    result.perPage = perPage
    result.hasPerPage = true

# ------------------------------------------------------------------ index --

proc escapeHtml(s: string): string =
  result = ""
  for c in s:
    case c
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    of '\'': result.add "&#39;"
    else: result.add c

proc renderIndex(data: JsonValue): string =
  var list = ""
  if data.len == 0:
    list = "<span class=\"empty\">No resources in db.json.</span>"
  else:
    for name, value in data:
      let n = escapeHtml(name)
      let meta = if value.kind == JArray: $value.len & " items" else: "object"
      list.add "<a href=\"/" & n & "\">\n        <span>/" & n &
               "</span>\n        <span class=\"meta\">" & meta &
               "</span>\n      </a>\n      "
  result = IndexTemplate.replace("{{resources}}", list)

# ---------------------------------------------------------------- routing --

proc splitRoute(path: string): seq[string] =
  ## `/a/b/` → `["a", "b"]`; one trailing slash is allowed, as regexparam's
  ## `/?$` does. Empty segments in the middle keep a route from matching.
  var p = path
  if p.len > 1 and p.endsWith("/"): p.setLen p.len - 1
  if p == "/" or p.len == 0: return @[]
  result = p.substr(1).split('/')

proc handle*(app: App; req: Request): Response =
  result = Response(status: 200, headers: @[], body: "")

  # Static files come before everything, CORS included.
  if serveStatic(app, req, result): return

  cors(req, result)
  if req.meth == "OPTIONS":
    result.status = 204
    result.setHeader("Content-Length", "0")
    return

  # Body parser: milliparsec parses whatever arrives on these methods, and an
  # empty body is `{}`.
  var body: Maybe = nil
  if req.meth in ["POST", "PUT", "PATCH", "DELETE"]:
    if req.bodyTooLarge:
      plainError(result, 500, "Payload too large. Limit: " & $PayloadLimit & " bytes")
      return
    if req.body.len == 0:
      body = newJObject()
    else:
      var err = ""
      if not tryParseJson(req.body, body, err):
        plainError(result, 500, escapeHtml(err))
        return

  let segs = splitRoute(req.path)
  let isGet = req.meth == "GET" or req.meth == "HEAD"

  if isGet and segs.len == 0 and req.path == "/":
    result.status = 200
    result.setHeader("Content-Type", "text/html; charset=utf-8")
    result.body = renderIndex(app.db.data)
    return

  if segs.len == 0 or segs[0].len == 0:
    plainError(result, 404, "Not Found")    # tinyhttp's noMatchHandler
    return

  let name = segs[0]
  let routeOk = segs.len <= 2 and (segs.len < 2 or segs[1].len > 0)
  var data: Maybe = nil

  if routeOk:
    if segs.len == 1:
      case req.meth
      of "GET", "HEAD":
        data = app.service.find(name, parseListParams(req.query))
      of "POST", "PUT", "PATCH":
        if not body.isObject:
          result.json(400, errorJson("Body must be a JSON object"))
          return
        case req.meth
        of "POST": data = app.service.create(name, body)
        of "PUT": data = app.service.update(name, body)
        else: data = app.service.patch(name, body)
      else: discard
    else:
      let id = segs[1]
      case req.meth
      of "GET", "HEAD":
        data = app.service.findById(name, id, queryAll(req.query, "_embed"))
      of "PUT", "PATCH":
        if not body.isObject:
          result.json(400, errorJson("Body must be a JSON object"))
          return
        if req.meth == "PUT": data = app.service.updateById(name, id, body)
        else: data = app.service.patchById(name, id, body)
      of "DELETE":
        data = app.service.destroyById(name, id, queryAll(req.query, "_dependent"))
      else: discard

  # `app.use('/:name', ...)`: a prefix match, so anything under a name ends here.
  if data == nil:
    result.json(404, errorJson("Not Found"))
  else:
    result.json(if req.meth == "POST": 201 else: 200, data)
