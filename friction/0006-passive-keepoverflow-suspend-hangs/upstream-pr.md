**Title:** coro_transform: a suspending `keepOverflowFlag` block is split at its state labels (fixes #2968)

**Branch:** `keepoverflow-suspend-split` in `~/lab/contrib/nimony`, on
4ba90a7. Its commit is `fix.diff` (`src/hexer/coro_transform.nim`) plus
`test/tpassive_keepoverflow_suspend.nim` and `.output` → `tests/nimony/cps/`.

---

Fixes #2968, as option 1 there.

A suspending pragma block other than `cast` kept its wrapper, so its resume
label stayed nested in the `pragmax`, and the program hung. Its body is now
flattened like a `cast` block's, cut at each state label, and every piece is
wrapped in the original pragmas again. `constparams` only needs the wrapper to
know which arithmetic to check. The `cast` path and the non-suspending path are
unchanged.

As noted in the issue, the flag does not survive a suspension point.

Test `tpassive_keepoverflow_suspend`: a discarded passive call in the block,
and overflowing additions on both sides of a suspension point, with
`overflowFlag()` read right after each. Without the change it hangs.

`hastur test` passes on `tests/nimony/{cps, passive, basicarith, opt, async,
iter, closures, exceptions, basics, stdlib, streams, http, threads,
ioringepoll}`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
