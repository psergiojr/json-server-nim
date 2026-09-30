# Upstream text for 0002

Derived from `report.md`. Replace `<permalink>` with a commit permalink to
`report.md` once the repo is public.

---

## Issue

**Title:** `if`/`case` expression with a `nil` branch: hexer crash (`isTrivial: (nilt)`) or spurious "cannot prove not nil"

```nim
type
  Obj = ref object
    k: int

proc pick(b: bool; o: Obj): nil Obj =
  result = if b: nil else: o

discard pick(true, Obj(k: 1))
```

**Actual:** sema accepts it, then hexer crashes with no source location:

```
isTrivial: (nilt)
[Bug] bug in isTrival computation
```

**Expected:** compiles, and the if-expression is typed `nil Obj` from `result`.

Related forms that also fail (same cause):

- `result = if b: Obj(k: 2) else: o` with `o: nil Obj` gives `Error: cannot prove expression is not nil: o`
- `result = if b: o else: nil` gives `Error: expected non-nil value`
- the same forms as a `case` expression, or as `let x: nil Obj = if …`

**Cause:** sema types the expression correctly, but that type isn't stored.
Later passes recompute it with `typenav.getTypeImpl`, which takes the *first*
branch's type (`IfS` ~391, `CaseS` ~414). `xelim.declareTemp` then declares
the temp as `(nilt)` or as `Obj notnil`.

A related case with no expected type is rejected in sema itself, by
`semStmtBranch`'s `AutoT` arm:
`take(if b: nil else: o)` gives `type mismatch: got: ref Obj not nil but wanted: (nilt)`.

A partial fix is in #NN. Full write-up with the variants I tried and the
generated NIF: <permalink>

<sub>Found while porting json-server to nimony with an AI coding assistant;
repros and diagnosis verified by hand at b2c2df7.</sub>

---

## PR

**Title:** Type if/case expressions from all branches, so a `nil` branch doesn't pin the type

Fixes #NN.

- `typenav.nim`: compute the if/case type from all branches.
  - Void, `auto` and `nilt` branches don't pick the type.
  - If any branch is `nil`, a `notnil` pointer-like result becomes nilable.
  - `CaseS` now walks every branch instead of only the first `of`.
- `sem.nim` `semStmtBranch`: after a `nil` branch, sem the next branch with
  `auto` and adopt its type if it is pointer-like. Otherwise keep the usual
  `commonType` error.

Adds `tests/nimony/notnil/tifexpr_nil_branch.nim` covering the nine variants
from the issue.

Ran `hastur test` on `notnil, contracts, casestmt, basics, errmsgs, misc,
object, closures, exceptions, types, stdlib`: all pass.

**Not covered:** `if b: nil else: nil` still crashes, because no branch gives a
type. The more robust fix would be for sema to write its type into the tree
(e.g. a typed `(nil T)`), so that no later pass re-derives it. I went with the
narrower patch, but I'm happy to rework it that way if you prefer.
