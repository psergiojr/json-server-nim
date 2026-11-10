---
id: 0008
title: Two chained operations in a `{.keepOverflowFlag.}:` block (`a + b + 1`) fail in lengc with "expected expression" and raw NIF
date: 2026-10-27
component: nimony
version: nimony 0.6.3 @ 358b9bce4dd855453f57a80a0c499b0b2e27d7ee; fixed at 0305d6c (re-checked 2026-11-10)
severity: crash
status: fixed
upstream: #2950 (1674f31, fixed independently on 2026-11-09; never filed)
---

## What I was doing

Writing a regression test for friction/0006: overflowing additions before and
after a suspension point in a `keepOverflowFlag` block. The first version added
three operands, and it failed in a way that had nothing to do with 0006.

## Expected

`repro.nim` prints `true`. The one example of the pragma in the repository,
`tests/nimony/basicarith/toverflowflag.nim`, has `let x = a + b` in the block.
Nothing suggests that an expression with two operations is different. (`doc/`
does not mention `keepOverflowFlag` at all.)

## Actual

Sema accepts it. lengc then fails:

```
repro.nim(7, 15) [Error] expected expression but got: (expr@E,7,repro.nim
 (stmts
  (var :`constRefTemp.1 .
   (i@G,l,.../lib/std/system/arithmetics.nim 64).@G,l,.../lib/std/system/ari…
  (keepovf
   (add
    (i@G,l,.../lib/std/system/arithmetics.nim 64)a.0~2 b.0@2)`constRefTemp.1))`constRefTemp.1)
```

| in a `keepOverflowFlag` block | 358b9bc |
|---|---|
| `let y = a + b` | compiles, `true` |
| `let y = result + a` (passive proc) | compiles |
| `let y = a + b + 1` (`repro.nim`) | lengc error |
| `let y = a + b + result` (passive proc) | lengc error |

The message is located (line and column of the outer `+`), but the rest is a
page of NIF with temporaries, not anything in the source.

## Minimal repro

See `repro.nim`, 9 lines, an ordinary (not passive) proc.

```
nimony c repro.nim
```

## Notes / suspected cause

Not verified. `constparams.checkedArithOp` lowers each checked operation to
`(expr (stmts (var tmp) (keepovf (add T A B) tmp)) tmp)`, and lowers the
operands with `tr` first. In `a + b + 1`, operand A is itself a checked
operation, so an `(expr …)` ends up as an operand of `keepovf`'s `add`. The
pass sets `needsXelim = true`, but the error suggests the nested `(expr …)`
reaches lengc without being taken apart (inside `keepovf` at least). Where
that should happen, in xelim or in `checkedArithOp` (by binding each operand
to a temp first), I did not establish.

## Proposed fix

None yet. A test for `basicarith/` would add `let y = a + b + 1` (and a
three-operand mix of `+`/`*`) to `toverflowflag.nim`.

## Re-check at 0305d6c (2026-11-10)

**Fixed upstream, independently:** #2950 (merged 2026-11-09), commit 1674f31
"xelim: lower the operands of `keepovf` and `emit` statements". The suspected
cause above was right: `constparams` leaves each checked operation as
`(expr (stmts (var t) (keepovf OP t)) t)`, and xelim's `trStmt` copied
`keepovf` verbatim, so a nested one reached lengc. xelim now lowers its
operands, and each nested operation becomes its own `keepovf` before the
statement. The commit adds `tests/nimony/basicarith/toverflowflag_nested.nim`,
the test proposed above.

Every row of the table now compiles. `repro.nim` prints `false`, not the
`true` given under "Expected":

| in a `keepOverflowFlag` block | 0305d6c |
|---|---|
| `let y = a + b` | `true` |
| `let y = a + b + 1` (`repro.nim`) | `false` |
| `let y = a + b + result` (passive proc, `result = 1`) | `false` |

That is the documented behaviour, not a bug. Since #2860 (merged 2026-11-03),
`doc/language.md` describes `keepOverflowFlag`: `overflowFlag()` reports
whether the *last* signed `+`, `-` or `*` overflowed. In `a + b + 1` that is
the `+ 1`, which doesn't overflow. At 358b9bc the C backend's flag was sticky
(any overflowing operation set it, nothing cleared it), so `true` matched what
the C backend did then. #2881 (merged 2026-11-04) made it non-sticky in C and
LLVM, as the JS and native backends already were. So the "Expected" above
relied on behaviour that was undocumented and has since changed on purpose.
The note that `doc/` doesn't mention the pragma no longer holds.

`upstream-issue.md` is kept as a record; it was never filed.

