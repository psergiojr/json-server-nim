**Title:** `v != nil and p and f(v)`: "cannot prove expression is not nil" (the fact is lost in a chained `and`)

---

```nim
type
  Obj = ref object
    k: int
  Maybe = nil Obj

proc f(v: Obj): bool = v.k > 0

proc a(v: Maybe): bool = v != nil and f(v)            # accepted
proc b(v: Maybe): bool = v != nil and true and f(v)   # rejected
```

**Actual** at 358b9bc: `repro.nim(9, 50) Error: cannot prove expression is not nil: v`

**Expected:** accepted, like `a`, and like the same condition in an `if`.

Also affected: a nil guard written as a template (`template isObject(v): bool =
v != nil and v.kind == JObject`), used as `v.isObject and use(v)`.

**Cause:** a value-position `and` is lowered by `xelim.trAnd` into a bool temp
plus an `ite`, and a nested `and` on the left becomes a temp of its own first.
`v != nil` then holds only inside the first `ite`, and the second one tests a
bool the prover can't tie back to `v`. `if` conditions don't have this problem
because they are compiled to jumps (`wantsCondJumps`, whose doc comment
describes the same problem). The value position never got that treatment.

PR with a fix and a test follows. Full write-up: <permalink>

<sub>Found while porting json-server to nimony with an AI coding assistant;
repro and diagnosis checked by hand at 358b9bc.</sub>
