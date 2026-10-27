---
id: 0004
title: The not-nil proof is lost in a chained `and`: `v != nil and true and f(v)` is rejected
date: 2026-09-23
component: nimony
version: nimony 0.6.3 @ 358b9bce4dd855453f57a80a0c499b0b2e27d7ee (re-checked 2026-10-27); first seen at 0e1761f, written against b2c2df7
severity: wrong-behavior
status: open
upstream:
---

## What I was doing

Checking the kind of a nilable JSON value before using it, on one line:

```nim
v != nil and v.kind == JObject and v.find(key) >= 0
```

## Expected

Accepted. `and` short-circuits, so by the third operand both earlier operands
held, `v != nil` included. `v != nil and f(v)` is accepted, and so is the
same condition in `if` position.

## Actual

```
repro.nim(9, 50) Error: cannot prove expression is not nil: v
```

## Minimal repro

`repro.nim`:

```nim
type
  Obj = ref object
    k: int
  Maybe = nil Obj

proc f(v: Obj): bool = v.k > 0

proc a(v: Maybe): bool = v != nil and f(v)            # accepted
proc b(v: Maybe): bool = v != nil and true and f(v)   # rejected
proc c(v: Maybe): bool =
  if v != nil and true:                               # accepted
    result = f(v)
  else:
    result = false
```

## Notes / suspected cause

Original guess (written mid-port): `and` is left-associative, so `b`'s condition
is `(v != nil and true) and f(v)`. The fact is recorded when the *immediate* left
operand is the nil comparison, but not when it is inside a nested `and` on the
left. The `if` in `c` does walk nested `and`s, so the logic exists; the
expression form doesn't reuse it.

Verified against the source at b2c2df7 (follow-up, 2026-09-25): the
associativity part is right. The rest is the right effect for the wrong reason,
and the bug is in the wrong layer: it is in hexer's expression elimination
(`xelim`), not in the prover.

Observed (`nimony c --verbose`, Final IR of `b`): no `and` reaches the prover.
The value-position `and` has already been lowered into bool temporaries:

```
(var `x.2 bool) (var `x.3 bool)
(ite (not (eq v nil)) (scope (asgn `x.3 true)) (scope (asgn `x.3 false)))
(ite `x.3 (scope (let `x.4 (call f v)) (asgn `x.2 `x.4)) (scope (asgn `x.2 false)))
```

`v != nil` holds only inside the first `ite`, and it is dropped where that
`ite`'s branches join. The second `ite` tests the bool `` `x.3 ``, and nothing
ties that bool back to `v`.

- `xelim.trAnd` (`src/hexer/xelim.nim:285`, and `trOr` at :255) lowers a
  value-position `x and y` to "bool temp + if". Its left operand goes through
  plain `trExpr`, so a nested `and` on the left becomes a temp of its own first.
  `isComplex` classes every `and`/`or` as complex (:49).
- `a` is accepted only because its right operand lands directly inside
  `ite (v != nil)`. The prover records nothing special about an immediate left
  operand.
- `c` is accepted because an `if` condition takes a different path, and it is
  not the prover's. `wantsCondJumps` (xelim.nim:666) with
  `trCondJump`/`trIfFlat`, or, for a spine of pure leaves, finalir's `genCond`
  (`src/finalir/finalir.nim:336`), compiles the condition into a flat
  `jmp`/`lab` chain, so the fact survives on the fall-through path.
- The prover does have an `AndX` handler (`analyseCondition`,
  `src/nimony/contracts_fir.nim:2318`), but in this pipeline no `and` ever
  reaches it: `finalir.trExpr` raises a `bug` on `AndX`/`OrX`
  (finalir.nim:173).
- The doc comment on `wantsCondJumps` (xelim.nim:674-677) describes this
  problem for conditions: "the Final IR then tested a temp whose meaning lived
  in the diamond that built it". Conditions were switched to jumps; the
  value-position path never was.

The template-guard failure (next paragraph) is exactly this bug, and `fix.diff` fixes it too.
This also makes the idiomatic workaround for another gap fail: a nil-guard
written as a template (`template isObject(v): bool = v != nil and v.kind ==
JObject`, since a guard *proc* never narrows) only works in `if` position,
because `v.isObject and use(v)` is exactly this chain.

Related, but a separate defect (INBOX, "cannot prove expression is not nil:
`` `x ``"): passing a *call* to such a template (`item[key].isNull`) substitutes
the call twice. `[]` then really runs twice, and xelim binds each result to its
own temp, so the nil test and the dereference are on two different values.
The prover is right to reject that. The only defect is the message, which names
the temp, not the expression. The temp's name is `` "`x." & counter `` (xelim
`tempSymName`, :107), and the renderer prints only its basename
(`renderer.nim:1999`), which is where the stray backtick in `` `x `` comes from.
Repro: `repro_template_call.nim`. `fix_message.diff` (contracts_fir.nim only)
renders a temp's initializer in its place, giving `cannot prove expression is
not nil: item[key]`. With it applied, `tests/nimony/{notnil,errmsgs,basics,stdlib}`
and `tests/contracts` pass. `fix.diff` does not change this case.

## Proposed fix

In xelim, not the prover. `fix.diff` (about 60 lines, `xelim.nim`): when an
`and`/`or` in value position has a short-circuit spine on its left (and the goal
is not `LowerCasts`), `trAnd`/`trOr` call a new `trShortCircuitViaCx`. It
compiles the left spine with the same jump machinery `trIfFlat` uses
(`trExprToLabel`):

```
(var tmp) (scope Cjmp(a)(Lf); tmp = b) (jmp Lend) (lab Lf) tmp = false (lab Lend)
```

`b` then sits on the path where every conjunct held. Tested at b2c2df7:

- `repro.nim` compiles clean.
- `test_semantics.nim` (nested `and`/`or`/`not` truth tables and a
  side-effect call count) gives the right output.
- `hastur --no-build test` passed on every `tests/nimony/*` subdirectory,
  `tests/contracts` and `tests/controlflow`. The first run failed in `opt`
  (`shoggoth` not built), plus one test each in `cps` and `plugins`; all three
  pass on rerun.
- `tests/hexer` was not run: its setup failed with a missing `.s.nif` in that
  environment.

Not covered: a nested short-circuit inside another expression form, e.g.
`f(a and b)`, is still materialised through a temp.

## Re-check at 358b9bc (2026-10-27)

Still reproduces: `repro.nim` gives `repro.nim(9, 50) Error: cannot prove
expression is not nil: v`, and `repro_template_call.nim` still names the temp
(`` `x ``). The nearest upstream items are #1984 and #2054 ("refine
nil-tracking through `and`/`or` short-circuit guards", closed 2026-06-30, before
this report). They taught the prover's `analyseCondition` about `and`/`or`,
which, as described above, a value-position `and` never reaches. Nothing open
upstream matches.

Both diffs apply unchanged to 358b9bc and were re-tested there, in a scratch
worktree with its own nimcache:

- `fix.diff`: `repro.nim` compiles. The semantics test, now
  `test/tnil_and_chain.nim` (for `tests/nimony/notnil/`), prints the expected
  truth tables and call count (18, counted by hand). It needed one change for
  358b9bc: the counter increments are wrapped in `{.cast(assumeSync).}:`
  because of the newer rule against unsynchronized global access, whose
  message names that fix. On stock it fails with two `cannot prove expression
  is not nil: v`. `test_semantics.nim` was replaced by it.
- `fix_message.diff` (regenerated against 358b9bc, same change):
  `repro_template_call.nim` reports `cannot prove expression is not nil:
  item[key]`. Golden test `test/tnotnil_temp_name.{nim,msgs}` for
  `tests/nimony/errmsgs/`.
- `hastur test` with `fix.diff` and `fix_message.diff` applied passes on
  `tests/nimony/{notnil, basics, basicarith, errmsgs, stdlib, cps, passive,
  exceptions, misc, casestmt, iter, closures, object, borrows, templates,
  sysbasics, strings, async}`, `tests/contracts` and `tests/controlflow`.

These are two upstream changes: the xelim fix (issue + PR), and the message
fix as a second, independent PR.
