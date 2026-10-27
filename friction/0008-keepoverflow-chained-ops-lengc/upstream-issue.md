**Title:** `a + b + 1` inside `{.keepOverflowFlag.}:` fails in lengc ("expected expression")

---

```nim
import std/syncio

proc p(a, b: int) =
  {.keepOverflowFlag.}:
    let y = a + b + 1
    echo overflowFlag()

p(1, high(int))
```

**Actual** at 358b9bc: sema accepts it, then

```
repro.nim(7, 15) [Error] expected expression but got: (expr@E,7,repro.nim
 (stmts
  (var :`constRefTemp.1 . (i 64) .)
  (keepovf (add (i 64) a.0 b.0) `constRefTemp.1)) `constRefTemp.1)
```

(abridged; the real output is a page of NIF with line info).

**Expected:** prints `true`. `let y = a + b` works; it is the second
operation that breaks it.

Possibly the cause: `constparams.checkedArithOp` lowers the operands first,
so the inner checked `+` becomes an `(expr …)` operand of the outer
`keepovf`'s `add`, and it reaches lengc as is. Not verified.

<sub>Found while writing a test for #NNNN (passive + `keepOverflowFlag`) with
an AI coding assistant; repro checked by hand at 358b9bc.</sub>
