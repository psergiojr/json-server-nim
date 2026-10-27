**Title:** Tuple unpacking hides the value's own error behind "expected tuple for tuple unpacking"

---

```nim
proc f(s: string): tuple[a, b: string] = (s, s)

let (x, y) = f(undeclaredThing("abc"))
```

**Actual** at 358b9bc: `repro.nim(3, 15) Error: expected tuple for tuple unpacking`

**Expected:** `repro.nim(3, 16) Error: undeclared identifier: 'undeclaredThing'`

The real error is never printed. In a real module (a forgotten import), it
read as a type problem with `splitFile`'s result.

**Cause:** `semUnpackDecl` sems the value into `tupBuf`, and when the type is
not a tuple, it calls `buildErr` without an origin, so the error inside
`tupBuf` is dropped. `buildErr`'s overload with an origin already reports an
inner `err` instead of its own message.

PR with a one-line fix and a test follows.

<sub>Found while porting json-server to nimony with an AI coding assistant;
repro and diagnosis checked by hand at 358b9bc.</sub>
