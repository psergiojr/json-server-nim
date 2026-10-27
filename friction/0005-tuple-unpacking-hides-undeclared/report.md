---
id: 0005
title: An undeclared identifier on the right of a tuple-unpacking `let` is reported as "expected tuple for tuple unpacking"
date: 2026-09-23
component: nimony
version: nimony 0.6.3 @ 358b9bce4dd855453f57a80a0c499b0b2e27d7ee (re-checked 2026-10-27); first seen at 0e1761f, written against b2c2df7
severity: bad-message
status: open
upstream:
---

## What I was doing

Building a temp-file path: `let (dir, name, ext) = splitFile(path(a.path))`,
having forgotten `import std/paths`, so `path` was undeclared.

## Expected

```
lowdb.nim(91, 35) Error: undeclared identifier: 'path'
```

## Actual

```
lowdb.nim(91, 35) Error: expected tuple for tuple unpacking
lowdb.nim(92, 15) Error: undeclared identifier: dir
lowdb.nim(94, 14) Error: Type mismatch at [position]
writeFile(tmp, toJson(data, 2))
[1] expected: string but got: auto ...
```

The actual error is never printed. What is printed is a consequence of it,
followed by a cascade for every use of the unpacked names.

## Minimal repro

`repro.nim` (4 lines):

```nim
proc f(s: string): tuple[a, b: string] = (s, s)

let (x, y) = f(undeclaredThing("abc"))
echo x
```

```
repro.nim(3, 15) Error: expected tuple for tuple unpacking
```

## Proposed fix

When the right-hand side is already an error node, report that error and do
not run the unpacking check on it. Declaring the unpacked names with an error
type would also stop the cascade (`undeclared identifier: dir`,
`got: auto`).

## Re-check at 358b9bc (2026-10-27)

Still reproduces. `repro.nim` was missing `import std/syncio`, so at 358b9bc it
also reported `undeclared identifier: 'echo'`. That was my mistake in the repro,
not part of the finding, and the import is now there:

```
repro.nim(5, 15) Error: expected tuple for tuple unpacking
repro.nim(6, 6) Error: undeclared identifier: x
```

No matching issue upstream (searched "expected tuple for tuple unpacking" and
"tuple unpacking undeclared", 2026-10-27).

**Cause, verified.** `semdecls.semUnpackDecl` sems the value into a
temporary buffer `tupBuf`. When the value's type is not a tuple it calls
`buildErr` without an origin, and `tupBuf`, which holds the real error, is
dropped. `buildErr` has an overload with an origin for exactly this case. Its
doc comment says that if the origin contains an `err` node, that error is
reported instead.

**Fix:** `fix.diff` passes `cursorAt(tupBuf, 0)` as the origin (one line,
plus a comment). With it:

```
repro.nim(5, 16) Error: undeclared identifier: 'undeclaredThing'
repro.nim(6, 6) Error: undeclared identifier: x
```

A value that is not a tuple (`let (u, v) = 3`) still gets "expected tuple for
tuple unpacking". Golden test `test/ttupleunpack_failed_value.{nim,msgs}` for
`tests/nimony/errmsgs/` covers both. On stock it prints "expected tuple" twice.
`hastur test` passes on `tests/nimony/{errmsgs, basics, stdlib, generics,
templates, iter, types, lookups, scopes, sysbasics, misc, object, notnil,
casestmt}` and `tests/contracts`.

Not covered: the cascade. The unpacked names are not declared after a failed
unpack, so every later use is another `undeclared identifier`. The same
happens at stock for a value that is not a tuple. Declaring them with an error
type, as a plain `let` does, would stop it. That is a larger change than this
message fix and is left out of the PR.
