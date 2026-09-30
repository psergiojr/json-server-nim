---
id: 0002
title: An if-expression is typed from its first branch, so `if b: nil else: x` crashes hexer and `if b: X() else: nilableX` fails the nil proof
date: 2026-09-23
component: nimony
version: b2c2df7 (2026-09-23); first seen at 0e1761f
severity: crash
status: open (cause verified, partial fix tested)
upstream:
---

## What I was doing

Writing a JSON value type in which `undefined` is `nil JsonValue` (a nilable
ref, as `doc/language.md` "Nil" describes). A lookup returns the value or
`nil`:

```nim
proc `[]`*(v: Maybe; key: string): Maybe =
  ...
  result = if i < 0: nil else: v.fields[i][1]
```

## Expected

`result` is declared `nil JsonValue`, so the if-expression should be typed by
that, and both branches (`nil`, and a `JsonValue`) fit it. That is how Nim 2
types an if-expression assigned to a typed location, and nothing in the
nimony manual says otherwise.

## Actual

Sema accepts it. hexer then crashes:

```
isTrivial: (nilt)
No stack traceback available
[Bug] bug in isTrival computation
nifmake: command failed (exit code 1): .../bin/hexer c ... nimcache/r3hwnya41.s.nif
```

No source location. In the real module (700 lines), the only clue was
`(nilt)`, the type of the `nil` literal.

The mirror image does not crash but is rejected:

```nim
proc pick(b: bool; o: nil Obj): nil Obj =
  result = if b: Obj(k: 2) else: o
```

```
r4.nim(6, 34) Error: cannot prove expression is not nil: o
```

Here the expression is typed `Obj` (not nil) from the first branch, and `o` is
then checked against *that*, not against `result`'s `nil Obj`.

## Minimal repro

`repro.nim` (crash) and `repro_nilable_else.nim` (spurious error), 7 lines each.

```
nimony c repro.nim
nimony c repro_nilable_else.nim
```

Writing two assignments in an `if` statement compiles both. Swapping the
branches fixes only the second. **Correction (2026-09-25):** swapping the
branches of `repro.nim` (`result = if b: o else: nil` with `o: Obj`) is
rejected at compile time with `expected non-nil value` (`repro_swapped.nim`).

## Notes / suspected cause

Observed: `lifter.isTrivial` lists `NiltT` among the kinds that must never
reach it (`lifter.nim` ~305) — so the `nil` literal's own type survived sema
as the type of a value that needs hooks.

Original guess: the if-expression's type comes from its first branch and the
expected type (`result`'s) is not used, the same root for both symptoms.

Verified against the source at b2c2df7 (follow-up, 2026-09-25). "Same root for
both symptoms" is right. "The expected type is not used" is wrong for *sema*;
the root is in the type that later passes recompute.

**Cause A (both reported symptoms): after sema, the if/case type is
recomputed from the first branch.**

- Sema does it right. `semAsgn` (`sem.nim:2214-2250`) passes the left side's
  type as the expected type. `semIf` → `semStmtBranch` (`sem.nim:2285-2307`)
  runs `commonType(branch, expected)` on each branch, and `nil` matches the ref.
- Sema's result type is not stored on the if node. Later passes recompute it
  with `typenav.getTypeImpl`:
  - `IfS` (`src/nimony/typenav.nim` ~391-412) returns the first non-void
    branch's type.
  - `CaseS` (~414-420) returns only the first `of` branch's type, without even
    skipping void.
  - `nil` is always `(nilt)` (typenav.nim:524).
- `xelim.declareTemp` (`src/hexer/xelim.nim:117-127`, called for `if` at :847)
  declares the if-expression's temp with that type. xelim also runs inside sem
  (via contracts/finalir), so the bad temp is already in `.s.nif`. From
  `repro.nim`:

  ```
  (var@9 :`x.0 . . (nilt).)
  (ite@9 b.0 (scope (asgn `x.0 (nil))) (scope (stmts (asgn `x.0 o.0))))
  (asgn@7 result.0 `x.0)
  ```

  hexer's lifter then meets `(nilt)`.
- For `repro_nilable_else.nim`, the temp is `(ref Obj (notnil))`, taken from
  `Obj(k: 2)`. `contracts_fir.checkNilMatch` (:2630) correctly rejects storing
  the nilable `o` into it. So symptom 2 is not a nil-checker bug: the checker is
  right about the temp it was given. Swapping the branches in `repro.nim` fails
  for the same reason: the temp is typed `Obj notnil` from `o`.
- The same failures occur for a `case` expression, for
  `let x: nil Obj = if …`, and for `if b: nil else: nil`.

**Cause B (separate, not in the original report): with no expected type, sema
itself pins the type to `nilt`.** For a call argument, a proc body's trailing
expression (`semProcBody` sems it with `auto`, `semdecls.nim:119-129`) or an
untyped `let`, `semStmtBranch`'s `AutoT` arm takes the first branch's `nilt`
and matches the rest against it:

```
repro_no_expected_type.nim(5, 48) Error: type mismatch: got: ref Obj.Obj not nil but wanted: (nilt)
```

`doc/language.md` (if/case expressions, :1888-1920) does not say how the result
type is chosen.

## Proposed fix

Type an if/case expression with the expected type when there is one, and
otherwise the common type of all branches, where `nil` unifies with any
nilable pointer type. A `nil` branch with no nilable type available should be
a sema error ("cannot infer the type of `nil`; annotate the other branch or
the destination"), never a type that reaches the backend.

In the code, the robust version is for sema to write its type into the tree
(e.g. a typed `(nil T)`, which sigmatch already emits for closures), so that no
pass has to re-derive it.

`fix.diff` (tested at b2c2df7) is a narrower two-part patch:

1. `typenav.nim` (cause A): fold the if/case type over **all** branches. Void,
   `auto` and `nilt` branches don't choose the type; a `nil` branch only sets a
   flag. A `nil`-marked branch type beats a `notnil` one. If any branch was
   `nil`, a `notnil` ptr/ref/pointer/cstring result is turned into its nilable
   variant. `CaseS` now walks every `of`/`elif`/`else`.
2. `sem.nim` `semStmtBranch` (cause B): when an earlier branch was `nil`, sem
   the later branch with `auto` and adopt its type if it is pointer-like;
   otherwise fall back to `commonType` against `nilt` for the usual error.

Results:

- All nine variants compile: both repros, the swapped form, `case` ×2, `let`
  ×2, the call argument and the trailing expression.
- A runtime check prints the expected nil/value for every one.
- `hastur test` passed on `tests/nimony/{notnil, contracts, casestmt, basics,
  errmsgs, misc, object, closures, exceptions, types, stdlib}`. Some
  directories finished in under a second, so cached results were not ruled
  out.

Still open with the patch:

- `if b: nil else: nil` still crashes, because no branch gives a type. Only the
  sema-writes-the-type fix covers it.
- An untyped `let x = if b: nil else: o` infers `Obj notnil`. It now fails
  cleanly, but the message names xelim's temp (`` `x ``): the same message
  defect as the one noted in 0004.
