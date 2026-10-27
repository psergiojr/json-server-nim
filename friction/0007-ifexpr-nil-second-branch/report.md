---
id: 0007
title: An if/case expression with a `nil` branch is still rejected when the `nil` comes second ("expected non-nil value") or has no destination type ("wanted: (nilt)")
date: 2026-10-27
component: nimony
version: nimony 0.6.3 @ 358b9bce4dd855453f57a80a0c499b0b2e27d7ee
severity: wrong-behavior
status: open
upstream:
---

## What I was doing

Re-checking friction/0002 at 358b9bc. The crash in 0002 (`if b: nil else: o`
into a `nil Obj`) was reported upstream by someone else as #2605 and fixed by
#2611. This report covers the forms of 0002 that still fail. The original use
was a JSON value type in which `undefined` is `nil JsonValue`, and lookups
return the value or `nil`.

## Expected

Written in 0002 before diagnosing, and still the expectation: an if/case
expression is typed by its destination when it has one, and otherwise by the
common type of its branches, where `nil` fits any nilable pointer type. Both
branches below fit `nil Obj`:

```nim
proc pick(b: bool; o: Obj): nil Obj =
  result = if b: o else: nil          # repro.nim

proc take(o: nil Obj) = discard
proc g(b: bool; o: Obj) = take(if b: nil else: o)   # repro_no_expected_type.nim
```

The mirror of the first (`if b: nil else: o`) compiles since #2611, which
makes the asymmetry harder to guess.

## Actual

```
repro.nim(8, 26) Error: expected non-nil value [pass --verbose for the Final IR]
repro_no_expected_type.nim(9, 48) Error: type mismatch: got: ref Obj.Obj not nil but wanted: (nilt)
```

| form | 358b9bc |
|---|---|
| `result = if b: o else: nil`, `o: Obj` (`repro.nim`) | `expected non-nil value` |
| `let x: nil Obj = if b: o else: nil` | `expected non-nil value` |
| global `var r: nil Obj = if c: o0 else: nil` | `expected non-nil value` |
| `take(if b: nil else: o)` (`repro_no_expected_type.nim`) | `wanted: (nilt)` |
| a proc body's trailing `if b: nil else: o`, return type `nil Obj` | `wanted: (nilt)` |
| `let x = if b: nil else: o` | `wanted: (nilt)` |
| `result = if b: Obj(k: 1) else: nil` | compiles |
| the forms #2611 fixed (`nil` first with a typed destination, `case`, `nil`/`nil`) | compile |

## Minimal repro

`repro.nim` and `repro_no_expected_type.nim`, 9 lines each.

```
nimony c repro.nim
nimony c repro_no_expected_type.nim
```

## Notes / suspected cause

Verified against 358b9bc, by the fix below. These are 0002's causes A and B,
which #2611 did not reach.

**`expected non-nil value` (cause A).** Sema types the expression correctly,
but after sema, `typenav.getTypeImpl` recomputes the type of an `if`/`case`
expression from its first non-void branch. #2611 made the `nil` branch typed
(`(nil T)`, with `T` the destination's `nil Obj`), which helps when `nil` comes
first. When a not-nil branch comes first, the expression is typed `Obj
notnil`. xelim's temp gets that type, and `contracts_fir` correctly rejects
storing `nil` into it. `Obj(k: 1)` as the first branch happens not to carry a
`notnil` mark, so that form compiles.

**`wanted: (nilt)` (cause B).** With no destination type (a call argument, the
trailing expression that `semProcBody` sems with `auto`, an untyped `let`),
`semStmtBranch`'s `AutoT` arm types the first branch on its own. A bare `nil`
gives `nilt`, and every later branch is then matched against `nilt`.

## Proposed fix

`fix.diff` (`typenav.nim`, `sem.nim`, rebased from 0002's tested patch):

1. `typenav.nim`: fold the if/case type over all branches. A `void` branch does
   not choose the type. A bare `nil` only sets a flag. A nilable branch type
   beats a `notnil` one. If any branch was a bare `nil`, a `notnil`
   ptr/ref/pointer/cstring result becomes nilable. `auto` still counts as a
   type, as it did, so `tests/controlflow/if.nif` is unchanged.
2. `sem.nim` `semStmtBranch`: after a `nil` branch, sem the next branch with
   `auto`. If its type is pointer-like, adopt it. Otherwise fall back to
   `commonType` against `nilt` for the usual error.

Test `test/tifexpr_nil_second.nim` (for `tests/nimony/notnil/`): the swapped
form as `if` and `case`, the typed `let`, the call argument and the trailing
expression, each checked at run time for nil and not-nil. On stock 358b9bc it
fails to compile (`wanted: (nilt)`).

Tested in a scratch worktree of 358b9bc: every form in the table compiles
except the last (below). `hastur test` passes on `tests/nimony/{notnil,
casestmt, basics, errmsgs, misc, object, closures, exceptions, types, stdlib,
generics, templates, iter, sysbasics, strings, cps}`, `tests/contracts` and
`tests/controlflow`. A first version also treated `auto` branches as
"no type". It changed the golden for `tests/controlflow/if.nif` (temp typed
`(i 64)` instead of `(auto)`), so the patch keeps upstream's behaviour there.

Not covered:

- `let x = if b: nil else: o` (no type anywhere, nil first) still fails. The
  temp is now `Obj notnil` plus the nil flag, and the message names xelim's
  temp: `cannot prove expression is not nil: `` `x ``. friction/0004's
  `fix_message.diff` fixes that name. The type itself would need sema to
  infer `nil Obj`.
- The more robust fix is still for sema to store the expression's type in the
  tree, so that no later pass re-derives it. #2611 did this for `nil` alone.
