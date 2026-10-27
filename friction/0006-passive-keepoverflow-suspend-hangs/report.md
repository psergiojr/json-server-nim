---
id: 0006
title: A passive call inside `{.keepOverflowFlag.}:` in a `.passive` proc compiles, then hangs at run time
date: 2026-10-27
component: nimony
version: nimony 0.6.3 @ 358b9bce4dd855453f57a80a0c499b0b2e27d7ee
severity: hang
status: open
upstream:
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
