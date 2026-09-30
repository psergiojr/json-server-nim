# json-server-nim

[json-server](https://github.com/typicode/json-server) v1 (1.0.0-beta.15)
reimplemented in [nimony](https://github.com/nim-lang/nimony), in the spirit of
Project Summer: the server is the instrument, and **the friction log
(`friction/`) is the product**.

```
json-server [options] <file>

Options:
  -p, --port <port>  Port (default: 3000)
  -h, --host <host>  Host (default: localhost)
  -s, --static <dir> Static files directory (multiple allowed)
  --help             Show this message
  --version          Show version number
```

Same REST surface as upstream: `GET/POST /:name`, `GET/PUT/PATCH/DELETE
/:name/:id`, `PUT/PATCH` on singular resources, filters (`field:op=value`,
`field_op=value`, `_where=<json>`), `_sort`, `_page`/`_per_page`, `_embed`,
`_dependent`, static files from `./public` and `-s` dirs, CORS, JSON5 input,
and live reload when the file changes.

## Build, run, test

Needs a built nimony checkout (`~/lab/nimony/bin` on `PATH`).

```sh
nimony c src/jsonserver.nim                    # → nimcache/<hash>/jsonserver
$(find nimcache -name jsonserver -type f -perm -u+x) fixtures/db.json
tests/run.sh                                   # every tests/t*.nim
tools/difftest.py <upstream checkout> <binary> # against the real json-server
```

## Tests

Every upstream test file is ported; the assertions are the same, only the
syntax changed.

| upstream | here | cases |
|---|---|---|
| `src/app.test.ts` | `tests/tapp.nim` (real HTTP, ephemeral port) | 43 |
| `src/service.test.ts` | `tests/tservice.nim` | 13 |
| `src/matches-where.test.ts` | `tests/tmatcheswhere.nim` | 42 |
| `src/parse-where.test.ts` | `tests/tparsewhere.nim` | 17 |
| `src/paginate.test.ts` | `tests/tpaginate.nim` | 6 |
| `src/adapters/normalized-adapter.test.ts` | `tests/tnormalizedadapter.nim` | 2 |

Upstream takes the rest from npm packages or the JS runtime, so they have
tests of their own here: `tjsonvalue` (JSON.parse/stringify/JSON5,
`Number#toString`), `tinflection`, `tsorton` (including ICU collation order),
`tcli` (`node:util.parseArgs`), and `tappunit` (routing/query behaviors the
upstream table does not pin).

`tools/difftest.py` runs 52 requests (reads, filters, sorts, pagination,
embeds, every mutation, error paths) against upstream json-server and this
binary side by side and compares status, CORS/content-type headers, bodies
and the final `db.json`. Current result: **52/53 identical**; the one
difference is the text of the 500 for a malformed JSON body (below).

## Layout

| module | ports |
|---|---|
| `src/jsonserver.nim` | `src/bin.ts` |
| `jsonserver/app.nim` | `src/app.ts` + tinyhttp routing, `@tinyhttp/cors`, `milliparsec`, `sirv` |
| `jsonserver/service.nim` | `src/service.ts` |
| `jsonserver/lowdb.nim` | `lowdb` (`Low`, `Memory`, `JSONFile`, `DataFile`), `src/adapters/*` |
| `jsonserver/parsewhere.nim`, `matcheswhere.nim`, `paginate.nim`, `whereoperators.nim` | the same-named `src/*.ts` |
| `jsonserver/sorton.nim`, `dotprop.nim`, `inflection.nim` | `sort-on`, `dot-prop`, `inflection` |
| `jsonserver/jsonvalue.nim`, `jsops.nim` | `JSON`, `JSON5`, and the JS operators the filters rely on (`===`, `<`, `String()`, `Number()`, `localeCompare`) |
| `jsonserver/server.nim` | `app.listen`, on `std/httpserver` |

`undefined` is `Maybe = nil JsonValue`. Nimony refs are not-nil by default,
so every place that can read a missing key has to check before touching it —
the `cannot read properties of undefined` class is a compile error here.

## Divergences from upstream

Deliberate, or forced by the platform:

- **Upstream quirks are kept**, because clients depend on the observable
  behavior: `?id=1` matches nothing (the value is coerced to a number, ids are
  strings, and the comparison is `===`); `_limit`, `_start` and other
  non-reserved `_` keys become filters that match nothing; a bare value in
  `_where` never matches; `singularize("analyses")` is `"analyasis"`.
- **HEAD** is answered as GET without a body. tinyhttp runs *every* matching
  route for HEAD regardless of method, which in upstream reaches the POST
  handler and answers 400.
- **JSON5 files are written back as JSON.** Reading accepts JSON5; writing
  uses `JSON.stringify(data, null, 2)`, which is valid JSON5 but loses
  comments and unquoted keys (upstream rewrites them with `JSON5.stringify`,
  which also loses comments).
- **The watcher polls** the file's mtime/size every 500 ms instead of using
  inotify. Writes made by the server itself are recognized and do not trigger
  a reload.
- **The 500 for a malformed JSON body** carries this parser's message
  (`1:2: Unexpected token 'b'`) rather than V8's (`Expected property name or
  '}' in JSON at position 1 (line 1 column 2)`). Status and headers match.
- **`localeCompare`** (used by `_sort` on strings) is a three-level
  approximation of ICU root collation: punctuation < digits < letters, then
  accents, then case (lowercase first). Latin-1 and Latin Extended-A letters
  fold to their base letter; other scripts sort by code point.
- **Paths are percent-decoded before routing** (`std/httpserver` does it, and
  refuses `..` escapes with a 400), so `%2F` inside an id splits the path.
  tinyhttp decodes route parameters after matching.
- **`_embed` of a singular name whose plural is not an array** returns the item
  unchanged; upstream throws a `TypeError` (500).
- **Object keys that look like array indices** keep insertion order; V8 would
  move them to the front.
- **Static files**: sirv's dev-mode behavior (`Cache-Control: no-store`,
  `Last-Modified`, `.html`/`.htm` and `index.html` resolution, mrmime types)
  but no ETag, Range, or compression.
- **`--host`** only changes the URLs printed at startup, as upstream: the
  listener binds every interface.

## Friction

`friction/INBOX.md` is the running log, in Summer's format; `friction/NNNN-*`
are promoted reports with minimal repros. Highlights so far: two compiler
crashes reachable from ordinary code (one from the documented `.passive` HTTP
handler shape), three diagnostics printed with no location, nil-proof gaps
around `and` chains and if-expressions, and stdlib gaps against Nim 2
(`sort` with a closure, `parseopt` values, `sleep`, file mtimes, seq append).
