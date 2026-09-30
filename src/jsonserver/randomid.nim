# Port of json-server src/random-id.ts: 8 random bytes, base64url, no padding.

import std / [syncio, base64, strutils]

proc randomId*(): string =
  var buf = default(array[8, char])
  var f: File
  if open(f, "/dev/urandom"):
    discard readBuffer(f, addr buf[0], buf.len)
    close(f)
  result = encode(buf, safe = true)
  while result.len > 0 and result[^1] == '=': result.setLen result.len - 1
