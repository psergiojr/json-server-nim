---
id: 0006
title: A passive call inside `{.keepOverflowFlag.}:` in a `.passive` proc compiles, then hangs at run time
date: 2026-10-27
component: nimony
version: nimony 0305d6c (re-checked 2026-11-10); written against 0.6.3 @ 358b9bce4dd855453f57a80a0c499b0b2e27d7ee
severity: hang
status: reported
upstream: #2968 (issue only; PR waits for upstream's choice of fix)
---

## What I was doing

Re-checking friction/0001 at 358b9bc. Upstream fixed 0001 independently
(#2569). Its fix differs from ours in one case: a suspension point inside a
pragma block that is not a `cast`. Our `fix.diff` reported a `bug` there, and
#2569 keeps the block. This report is that case, run.

## Expected

`repro.nim` prints `0`. `{.keepOverflowFlag.}:` only changes how arithmetic in
its body is checked, so a passive call inside it should behave as it does
outside it, and as it does inside `{.cast(noSideEffect).}:` (which prints the
right value at 358b9bc).

## Actual

It compiles without a message and then hangs. Run under `timeout 10`, it exits
124 with no output.

| body of the pragma block in a `.passive` proc | 358b9bc |
|---|---|
| `discard six()` under `keepOverflowFlag` (`repro.nim`) | hangs |
| `result += six()` under `keepOverflowFlag` | hangs |
| the same, followed by a statement after the block | hangs |
| `result += six()` twice under `cast(noSideEffect)` | `12` |
| the same under `cast(uncheckedAssign)` | `12` |
| the same in a plain `block:` | `12` |
| `keepOverflowFlag` with no passive call inside | correct |

## Minimal repro

See `repro.nim`.

```
nimony c repro.nim && timeout 10 nimcache/c/<hash>/repro; echo $?   # 124
```

## Notes / suspected cause

Observed in the generated C for `repro.nim`: `p`'s resume state after `six()`
returns is empty, and it returns an uninitialised continuation.

```c
Continuation_0_sysvq0asl p7X60Qs1_0_kQ_dhd6hfq1(p7X60Qcoro_0_kQ_dhd6hfq1* X60Qthis_0){
  Continuation_0_sysvq0asl result_0;
  return result_0;}
```

The code that should run after the call (handing control back to the caller)
is in state 0, after its `return`, where nothing can reach it.

Cause, verified by the fix below. In `coro_transform.trGoto`, the `PragmaxS`
arm added by #2569 handles two cases:

- A suspending `cast` block is flattened, because the state labels in it have
  to reach the top level.
- Every other pragma block, suspending or not, keeps its wrapper and goes
  through `trGotoScoped`.

For a suspending `keepOverflowFlag` block, the second case leaves the state
label `(lab <int>)` nested inside the `pragmax`. The state machine only cuts at
top-level state labels. #2569's comment states the constraint ("its state
labels belong at the top level") but applies it only to `cast`, because a
`cast` block "means nothing at run time". `keepOverflowFlag` does mean
something, but only at compile time: `constparams.trPragmaBlock` drops the
wrapper after setting a flag for the arithmetic inside it. So the wrapper does
not need to stay in one piece.

## Proposed fix

`fix.diff` (`src/hexer/coro_transform.nim`, +30 lines): for a suspending pragma
block other than `cast`, flatten the body as for `cast`. Then cut it at each
state label and wrap every piece in the original `(pragmax (pragmas …)
(stmts …))`. The labels reach the top level, and `constparams` still sees the
pragma on every statement that was inside the block. The `cast` path and the
non-suspending path are unchanged.

Test `test/tpassive_keepoverflow_suspend.nim` (for `tests/nimony/cps/`): a
discarded passive call in the block, plus overflowing additions before and
after a suspension point, with `overflowFlag()` checked on both sides. Output
`1 / true / true / 12`. On stock 358b9bc it compiles and hangs.

Tested in a scratch worktree of 358b9bc: every row of the table above gives the
expected value. `hastur test` passes on `tests/nimony/{cps, passive,
basicarith, opt, async, iter, closures, exceptions, basics, stdlib, streams,
http, threads, ioringepoll}`.

Not covered: `keepOverflowFlag` with two chained operations (`a + b + 1`)
fails in lengc whether or not the proc is passive. That is friction/0008, and
it is why the test uses one operation per statement.

## Re-check at 0305d6c (2026-11-10)

Still hangs: `repro.nim` and every `keepOverflowFlag` row of the table time
out (exit 124) on stock 0305d6c, as does the new test. No matching issue or PR
upstream (searched "passive hang", "coro_transform", "keepOverflowFlag
passive", "pragma block passive"). #2960 (open) touches `keepOverflowFlag` in
`constparams`, not `coro_transform`.

`fix.diff` still applies; it is regenerated against 0305d6c (same lines, hunk
moved by 10). Built in a scratch clone of 0305d6c:

- `repro.nim` prints `0`. The table's rows print `6 7 12 12 12 true` (same
  order as the table, last one the block with no passive call).
- `test/tpassive_keepoverflow_suspend.nim` prints its `.output`. It reads
  `overflowFlag()` right after an overflowing `a + b`, so the now non-sticky
  flag (#2881, see friction/0008) doesn't change it.
- `hastur test` passes on `tests/nimony/{cps (66/66, with the new test),
  passive, basicarith, opt, async, iter, closures, exceptions, basics, stdlib,
  streams, http, threads, ioringepoll}`. `basicarith` now includes upstream's
  `toverflowflag_nested`.

friction/0008 is fixed (#2950), so the PR draft no longer says why the test
uses one operation per statement.


### With the fix, the flag does not survive a suspension point

Found on 2026-11-10 while preparing the issue. `repro_flag_across_suspend.nim`,
with `fix.diff` applied: an overflowing `a + b` in the block, then
`overflowFlag()`:

| between the overflow and `overflowFlag()` | with the fix |
|---|---|
| nothing | `true` |
| a plain call (`nop()`) | `true` |
| a passive call (`discard six()`) | **`false`** |

Expected `true` in all three: `doc/language.md` says the flag reports the last
signed `+`, `-` or `*`, and a call is none of those. So `fix.diff` turns the
hang into a silently wrong flag. The test misses it because it reads the flag
right after each addition. Presumably the flag is a C local, which a resumed
state doesn't carry over; I didn't verify that in the generated C.

So the fix is not ready as a PR without a design decision. Possible directions:

1. `fix.diff` as is: split the block at its state labels, re-wrap each piece,
   and document that a suspension point resets the flag.
2. The same, plus keeping the flag in the coroutine's frame across a
   suspension point.
3. Reject a suspension point inside `{.keepOverflowFlag.}` with an error.
   The flag is about the arithmetic next to it, and #2569's comment already
   says the block's state labels "belong at the top level".

Plan (owner, 2026-11-10): file the issue alone, with these options, and wait
for upstream's preference before opening a PR.
