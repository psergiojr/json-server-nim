# Port of json-server src/bin.ts.
#
#   json-server [options] <file>
#
# Differences from upstream are listed in README.md. The one worth knowing
# here: the watcher polls the file's mtime twice a second instead of using
# inotify (chokidar), since nimony's stdlib has neither a watcher nor `sleep`.

import std / [syncio, strutils, os, envvars, terminal, cmdline, algorithm]
import std / posix / posix
import jsonserver / [jsonvalue, lowdb, app, server, cli, randomid]

const Version = "1.0.0-beta.15"

var useColor = false

proc paint(code, s: string): string =
  if useColor: "\e[" & code & "m" & s & "\e[0m" else: s

proc bold(s: string): string = paint("1", s)
proc gray(s: string): string = paint("90", s)
proc red(s: string): string = paint("31", s)
proc yellow(s: string): string = paint("33", s)
proc blue(s: string): string = paint("34", s)
proc magenta(s: string): string = paint("35", s)

proc say(s: string) =
  ## `console.log`: one line, visible now even when stdout is a pipe.
  stdout.writeLine s
  flushFile(stdout)

proc help() =
  say """Usage: json-server [options] <file>

Options:
  -p, --port <port>  Port (default: 3000)
  -h, --host <host>  Host (default: localhost)
  -s, --static <dir> Static files directory (multiple allowed)
  --help             Show this message
  --version          Show version number
"""

proc sleepMs(ms: int) =
  var req = Timespec(tv_sec: posix.Time(ms div 1000), tv_nsec: (ms mod 1000) * 1_000_000)
  var rem = default(Timespec)
  discard nanosleep(req, rem)

type
  FileStamp = object
    sec, nsec, size: int64
    exists: bool

proc stamp(file: string): FileStamp =
  var st = default(Stat)
  var f = file
  if stat(f.toCString, st) != 0:
    return FileStamp(sec: 0, nsec: 0, size: 0, exists: false)
  result = FileStamp(sec: int64(st.st_mtim.tv_sec), nsec: int64(st.st_mtim.tv_nsec),
                     size: int64(st.st_size), exists: true)

proc sortedKeys(data: Maybe): seq[string] =
  result = @[]
  for k in data.keys: result.add k
  result.sort()

proc logRoutes(data: JsonValue; file, host: string; port: int) =
  say bold("Endpoints:")
  if data.len == 0:
    say gray("No endpoints found, try adding some data to " & file)
    return
  var lines: seq[string] = @[]
  for key in data.keys:
    lines.add gray("http://" & host & ":" & $port & "/") & blue(key)
  say lines.join("\n")

proc main() =
  useColor = isatty(stdout)
  var args = default(CliArgs)
  var err = ""
  if not parseCli(commandLineParams(), getEnv("PORT"), getEnv("HOST"), args, err):
    say red(err)
    help()
    quit(1)

  if args.version:
    say Version
    quit(0)
  if args.watch:
    say yellow("--watch/-w can be omitted, JSON Server 1+ watches for file changes by default")
  if args.help or args.positionals.len == 0:
    help()
    quit(0)

  let file = args.file
  var port = 0
  for ch in args.port:            # parseInt: leading digits
    if ch notin {'0'..'9'}: break
    port = port * 10 + (ord(ch) - ord('0'))
  let host = args.host

  if not fileExists(file):
    say red("File " & file & " not found")
    quit(1)

  # Handle empty string JSON file
  try:
    if readFile(file).strip() == "": writeFile(file, "{}")
  except ErrorCode as e:
    say red("Cannot read " & file & ": " & $e)
    quit(1)

  # Set up database
  let json5 = file.toLowerAscii.endsWith(".json5")
  let observer = newObserver(newNormalizedAdapter(newJsonFile(file, json5)))
  let db = newLow(observer, newJObject())
  if not db.read(err):
    say red("Error parsing " & file & "\n" & err)
    quit(1)

  # Create app
  let a = newApp(db, AppOptions(staticDirs: args.staticDirs))
  let bound = startServer(a, port)
  if bound < 0:
    say red("Cannot listen on port " & $port)
    quit(1)

  const kaomojis = ["♡⸜(˶˃ ᵕ ˂˶)⸝♡", "♡( ◡‿◡ )", "( ˶ˆ ᗜ ˆ˵ )", "(˶ᵔ ᵕ ᵔ˶)"]
  say [
    bold("JSON Server started on PORT :" & $bound),
    gray("Press CTRL-C to stop"),
    gray("Watching " & file & "..."),
    "",
    magenta(kaomojis[ord(randomId()[0]) mod kaomojis.len]),
    "",
    bold("Index:"),
    gray("http://localhost:" & $bound & "/"),
    "",
    bold("Static files:"),
    gray("Serving ./public directory if it exists"),
    ""].join("\n")
  logRoutes(db.data, file, host, bound)

  if getEnv("NODE_ENV") == "production":
    while true: sleepMs(60_000)

  # Watch the file. The server's own writes move the mtime too; the observer
  # records the stamp they leave so the poll can tell them apart. Both run
  # under the app lock, so a request never sees a half-applied reload.
  var known = stamp(file)
  var hadReadError = false
  var prevEndpoints: seq[string] = @[]
  observer.onWriteEnd = proc () {.closure.} =
    known = stamp(file)
  observer.onReadStart = proc () {.closure.} =
    prevEndpoints = sortedKeys(db.data)
  observer.onReadEnd = proc (data: Maybe) {.closure.} =
    if data == nil: return
    if hadReadError or prevEndpoints != sortedKeys(data):
      say ""
      logRoutes(data, file, host, bound)
    hadReadError = false

  while true:
    sleepMs(500)
    withAppLock:
      let now = stamp(file)
      if now != known:
        known = now
        if now.exists:
          var readErr = ""
          if not db.read(readErr):
            hadReadError = true
            say red("\nError parsing " & file & "\n" & readErr)

main()
