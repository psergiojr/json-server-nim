# Command-line parsing for the `json-server` binary, with the semantics of
# `node:util.parseArgs` for bin.ts's option spec: string options take the
# next token (`-p 3000`), or an inline value (`-p3000`, `--port=3000`);
# `--` ends options; anything unknown is an error.

import std / strutils

type
  CliArgs* = object
    file*: string
    port*: string
    host*: string
    staticDirs*: seq[string]
    help*: bool
    version*: bool
    watch*: bool          ## deprecated -w/--watch, accepted and warned about
    positionals*: seq[string]

proc parseCli*(args: seq[string]; envPort, envHost: string;
               args2: var CliArgs; err: var string): bool =
  ## `err` is what `parseArgs` would throw, cut at the first `.` the way
  ## bin.ts prints it: "Unknown option '--foo'".
  args2 = CliArgs(file: "", port: (if envPort.len > 0: envPort else: "3000"),
                  host: (if envHost.len > 0: envHost else: "localhost"),
                  staticDirs: @[], help: false, version: false, watch: false,
                  positionals: @[])
  var i = 0
  var onlyPositionals = false
  while i < args.len:
    let a = args[i]
    inc i
    if onlyPositionals or a.len < 2 or a[0] != '-':
      args2.positionals.add a
      continue
    if a == "--":
      onlyPositionals = true
      continue
    var name = ""
    var inline = ""
    var hasInline = false
    if a.startsWith("--"):
      let eq = a.find('=')
      if eq >= 0:
        name = a.substr(2, eq - 1)
        inline = a.substr(eq + 1)
        hasInline = true
      else:
        name = a.substr(2)
    else:
      # A short option; `-p3000` carries its value inline.
      name = case a[1]
             of 'p': "port"
             of 'h': "host"
             of 's': "static"
             of 'w': "watch"
             else: ""
      if name.len == 0:
        err = "Unknown option '" & a.substr(0, 1) & "'"
        return false
      if a.len > 2:
        inline = a.substr(2)
        hasInline = true
    case name
    of "port", "host", "static":
      var value = inline
      if not hasInline:
        if i >= args.len or (args[i].len > 0 and args[i][0] == '-'):
          err = "Option '" & (if a.startsWith("--"): a else: a & ", --" & name) &
                " <value>' argument missing"
          return false
        value = args[i]
        inc i
      if name == "port": args2.port = value
      elif name == "host": args2.host = value
      else: args2.staticDirs.add value
    of "help", "version", "watch":
      if hasInline:
        err = "Option '--" & name & "' does not take an argument"
        return false
      if name == "help": args2.help = true
      elif name == "version": args2.version = true
      else: args2.watch = true
    else:
      err = "Unknown option '--" & name & "'"
      return false
  if args2.positionals.len > 0: args2.file = args2.positionals[0]
  result = true
