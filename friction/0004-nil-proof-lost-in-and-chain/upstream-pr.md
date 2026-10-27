**Title:** fixes #NNNN; xelim: compile the left spine of a value-position `and`/`or` to jumps

**Files:** `fix.diff` (`src/hexer/xelim.nim`), plus `test/tnil_and_chain.nim`
and `.output` → `tests/nimony/notnil/`.

---

Fixes #NNNN.

- `xelim.trAnd`/`trOr`: when the left operand of a value-position `and`/`or`
  is itself a short-circuit spine (and the goal is not `LowerCasts`), call the
  new `trShortCircuitViaCx`. It compiles the left spine against jump targets
  with `trExprToLabel`, the same machinery `trIfFlat` uses for conditions, so
  the right operand is evaluated on the path where every conjunct held:
  `(var tmp) (scope Cjmp(a)(Lf) tmp = b) (jmp Lend) (lab Lf) tmp = false (lab Lend)`.
- Everything else keeps the existing temp-plus-`ite` lowering.

The test covers `and`, `or` and `not` chains with nil guards, checked as truth
tables, plus a call count (18) showing that evaluation still short-circuits
left to right. Without the change it fails to compile with two `cannot prove
expression is not nil: v`.

`hastur test` passes on `tests/nimony/{notnil, basics, basicarith, errmsgs,
stdlib, cps, passive, exceptions, misc, casestmt, iter, closures, object,
borrows, templates, sysbasics, strings, async}`, `tests/contracts` and
`tests/controlflow`.

**Not covered:** a short-circuit nested inside another expression, e.g.
`f(a and b)`, still goes through a temp.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
