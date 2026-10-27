**Title:** if/case expression with `nil` second, or with no destination type, is still rejected after #2611

---

```nim
type
  Obj = ref object
    k: int

proc pick(b: bool; o: Obj): nil Obj =
  result = if b: o else: nil

proc take(o: nil Obj) = discard
proc g(b: bool; o: Obj) = take(if b: nil else: o)
```

**Actual** at 358b9bc:

```
repro.nim(6, 26) Error: expected non-nil value
repro.nim(9, 48) Error: type mismatch: got: ref Obj.Obj not nil but wanted: (nilt)
```

**Expected:** both compile. `if b: nil else: o` into a `nil Obj` compiles
since #2611 (#2605).

Also failing:

- `let x: nil Obj = if b: o else: nil`
- a proc body's trailing `if b: nil else: o` with return type `nil Obj` (`wanted: (nilt)`)

**Cause:**

- `expected non-nil value`: after sema, `typenav` still types an `if`/`case`
  from its first non-void branch. Here that is `o`, `Obj notnil`, so xelim's
  temp can't hold the `nil`.
- `wanted: (nilt)`: with no destination type, `semStmtBranch`'s `AutoT` arm
  takes the bare `nil`'s `nilt` from the first branch and matches the others
  against it.

PR with a fix and a test follows. Full write-up: <permalink>

<sub>Found while porting json-server to nimony with an AI coding assistant;
repros and diagnosis checked by hand at 358b9bc.</sub>
