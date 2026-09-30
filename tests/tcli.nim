# Not in upstream (bin.ts has no tests): pins the node:util.parseArgs
# behavior the binary relies on.

import harness
import ../src/jsonserver/cli

proc parse(args: seq[string]; ok: var bool; err: var string): CliArgs =
  var a = default(CliArgs)
  ok = parseCli(args, "", "", a, err)
  result = a

test "defaults":
  var ok = false
  var err = ""
  let a = parse(@["db.json"], ok, err)
  check ok and a.file == "db.json" and a.port == "3000" and a.host == "localhost"

test "env defaults":
  var a = default(CliArgs)
  var err = ""
  check parseCli(@["db.json"], "4000", "0.0.0.0", a, err)
  check a.port == "4000" and a.host == "0.0.0.0"

test "separate, inline and long values":
  var ok = false
  var err = ""
  let a = parse(@["-p", "3001", "--host=h", "-sassets", "--static", "b", "db.json"], ok, err)
  check ok, err
  check a.port == "3001" and a.host == "h" and a.file == "db.json"
  check a.staticDirs == @["assets", "b"]

test "flags":
  var ok = false
  var err = ""
  let a = parse(@["--help", "--version", "-w"], ok, err)
  check ok and a.help and a.version and a.watch and a.file == ""

test "unknown option":
  var ok = true
  var err = ""
  discard parse(@["--foo", "db.json"], ok, err)
  check not ok and err == "Unknown option '--foo'", err
  discard parse(@["-x"], ok, err)
  check not ok and err == "Unknown option '-x'", err

test "missing value":
  var ok = true
  var err = ""
  discard parse(@["db.json", "-p"], ok, err)
  check not ok, err

test "-- ends options":
  var ok = false
  var err = ""
  let a = parse(@["--", "--weird.json"], ok, err)
  check ok and a.file == "--weird.json"

finish()
