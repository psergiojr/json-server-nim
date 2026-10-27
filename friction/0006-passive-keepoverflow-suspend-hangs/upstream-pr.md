**Title:** fixes #NNNN; split a suspending `keepOverflowFlag` block at its state labels

**Files:** `fix.diff` (`src/hexer/coro_transform.nim`), plus
`test/tpassive_keepoverflow_suspend.nim` and `.output` → `tests/nimony/cps/`.

---

Fixes #NNNN.

`keepOverflowFlag` can't lose its wrapper the way a `cast` block does, but it
doesn't need the wrapper in one piece either: `constparams` only uses it to
switch overflow checking for the arithmetic inside. So a suspending pragma
block other than `cast` is now flattened like `cast`, then cut at each state
label, and every piece is re-wrapped in the original `(pragmax (pragmas …)
(stmts …))`. The `cast` path and the non-suspending path are unchanged.

The test has a discarded passive call in the block, and overflowing additions
on both sides of a suspension point, with `overflowFlag()` checked after each.
Without the change it compiles and hangs.

`hastur test` passes on `tests/nimony/{cps, passive, basicarith, opt, async,
iter, closures, exceptions, basics, stdlib, streams, http, threads,
ioringepoll}`.

**Not covered:** `a + b + 1` inside `keepOverflowFlag` fails in lengc with or
without `.passive` (#NNNN, the separate issue), so the test uses one operation
per statement.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
