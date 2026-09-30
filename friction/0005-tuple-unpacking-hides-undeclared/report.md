---
id: 0005
title: An undeclared identifier on the right of a tuple-unpacking `let` is reported as "expected tuple for tuple unpacking"
date: 2026-09-23
component: nimony
version: b2c2df7 (2026-09-23); first seen at 0e1761f
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
