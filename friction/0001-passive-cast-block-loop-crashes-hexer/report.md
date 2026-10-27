---
id: 0001
title: A pragma block (`{.cast(...).}:`, `{.keepOverflowFlag.}:`) with two or more statements in a `.passive` proc crashes hexer with "into: body did not consume all children"
date: 2026-09-23
component: nimony
version: nimony @ b2c2df77bf8f08f0c17ce4ed678d2495dc3f4f62 (2026-09-23); first seen at 0e1761f
severity: crash
status: fixed
upstream: #2569 (fixed independently on 2026-09-26; never filed)
---

## What I was doing

Writing the per-connection handler of an HTTP server on `std/httpserver`, in
the shape its module doc shows: `proc handle(c: sink HttpConnection)
{.passive.} = while c.next(): ...`. The handler needed one request header that
has no tag (`Access-Control-Request-Headers`), so it looped over
`c.request.otherHeaders`.

## Expected

The loop compiles. `otherHeaders` is a public iterator of `std/http/httpmsg`,
and a `.passive` handler is the documented way to use `std/httpserver`. If
something about the combination were unsupported, I expected a sema error at
the loop.

## Actual

Sema accepts the program; the backend dies:

```
assertions.nim(38)       raiseAssert
Error: unhandled exception: nifcore.nim(1278, 3) `c.rem == 0` into: body did not consume all 176 children (left 144) [AssertionDefect]
nifmake: command failed (exit code 1): .../bin/hexer c --bits:64 --cpu:le --os:Linux --flags:br --isMain --app:console --outdir:nimcache/pasb3tkvo nimcache/pasb3tkvo.s.nif
```

No source location and no module name. In the real program the crash named
`nimcache/serhwyyjn1.s.nif`, which I mapped back to `server.nim` by hand, then
found the loop by deleting procs one at a time.

## Minimal repro

`repro.nim` (4 lines, no imports):

```nim
proc count(s: seq[int]): int {.passive.} =
  result = 0
  {.cast(noSideEffect).}:
    for x in s: inc result
```

```
nimony c repro.nim
```

`repro_iterator.nim` is the shape it was found in: an iterator whose body is a
cast block (as `httpmsg.otherHeaders`, `headers` and `headerNodes` are), used
in a `.passive` proc.

What does *not* crash, each a one-edit variant of the repro:

| variant | result |
|---|---|
| no `.passive` | compiles |
| cast block without the loop (`inc result` alone) | compiles |
| loop inside `block:` instead of the cast block | compiles |
| iterator without the cast block | compiles |

So it takes all three: a passive proc, a `(pragmax ...)` statement, and a loop
(an inlined iterator) inside it.

**Correction (2026-09-25, see Cause):** the loop is incidental. What matters is
a pragma-block body of two or more statements, which a loop lowers into.
`repro_two_stmts.nim` (two `inc result` in a cast block, no loop) crashes the
same way (`40 children (left 16)`). The row "cast block without the loop
compiles" holds only because that body is one statement.

## Notes / suspected cause

Observed: hexer's passive lowering is where it dies (sema is clean, the
failing command is `hexer c`).

Guessed: `coro_transform.trGoto` treats `PragmaxS` like a block and recurses
into every child with `trGoto` (`coro_transform.nim` ~1568). The first child
is the `(pragmas (cast ...))` node, which is not a statement. Whether that is
the walk that miscounts, or the `for` loop's lowering inside it, I did not
establish.

Verified against the source at b2c2df7 (follow-up, 2026-09-25). The guess is
half right. `coro_transform.trGoto` does build the bad node, but the
`(pragmas (cast ...))` child is not the problem. The assertion fires in a later
hexer pass.

- **Where it dies.** A `-d:debug --stacktrace:on` hexer on the repro's `.s.nif`:
  `pipeline.nim(140) transform → constparams.nim(316) injectConstParamDerefs →
  … → constparams.nim(199) trPragmaBlock → nifcore.nim(1278) leaveScope`. The
  pass is `constparams` (pass 10, after `cps`).
- **Why.** `constparams.trPragmaBlock` (`src/hexer/constparams.nim:198-214`)
  assumes `(pragmax (pragmas …) <one body>)`: it skips the pragmas and calls
  `tr` once. `xelim.nim:1233-1236` makes the same assumption.
- **Who breaks that shape.** The `cps` pass. Dumped per pass with
  `-d:logPasses`: the `destroyer` output (the input to cps) is
  `(pragmax (pragmas (cast …)) (stmts (let …) (scope …) (lab …)))`, one body
  child. After `cps` it is `(pragmax (pragmas (cast …)) (let …) (cursor …)
  (asgn …) (loop …) (lab …) (lab …))`, six. `PragmaxS` is in `trGoto`'s generic
  arm (`coro_transform.nim:1564-1579`), which copies the head and runs `trGoto`
  on each child. The body `(stmts …)` reaches the `StmtsS, ScopeS` arm
  (:1675-1687), which flattens on purpose: state labels must sit at the proc's
  top level. The body's statements therefore spill into the `pragmax`. The
  pragmas child comes through intact.
- **The numbers.** "176 children (left 144)" counts *tokens*: `bodyLen` is a
  `cursorJump` (`nifcore.nim:1263-1280`). The pragmax body is 176 tokens;
  `trPragmaBlock` consumes the pragmas and the first `let`, and 144 remain. That
  is a second, small friction item: the assertion message says "children".

Scope: every variant below is a `.passive` proc, built at b2c2df7.

| variant | result |
|---|---|
| for loop in cast block (`repro.nim`), `repro_iterator.nim` | crash |
| two statements in a cast block, no loop (`repro_two_stmts.nim`) | crash |
| while loop in cast block | crash |
| `{.keepOverflowFlag.}:` or `{.cast(uncheckedAssign).}:` with 2 statements | crash |
| a passive call (a suspension point) inside a cast block | crash |
| one statement in a cast block | compiles |

Closure iterators also go through `trGoto`, so they are likely affected too.
Not tested.


## Workaround

Read the headers in a non-passive proc and call that from the passive one
(`src/jsonserver/server.nim`, `otherHeaders`).

## Proposed fix

`fix.diff` (tested at b2c2df7) gives `PragmaxS` its own arm in `trGoto`:

- **No suspension point inside:** keep the `pragmax`, copy the pragmas, and
  emit the body through the existing `trGotoScoped`, which produces exactly one
  `(stmts …)`.
- **Suspension point inside a `cast` block:** drop the wrapper and lay the body
  out flat. The state labels must reach the top level, and `constparams`
  discards the cast wrapper anyway.
- **Suspension point inside any other pragma block (`keepOverflowFlag`):**
  report `bug "suspension point inside a pragma block"`. Dropping that wrapper
  would change the overflow semantics.

It also adds `tests/nimony/cps/tpassive_pragma_block.nim`. The test covers the
for loop, the iterator, a while loop, two statements, and a suspending call in
a cast block; its expected output is `3 4 2 2 12`.

Results:

- Every crashing variant above compiles.
- `hastur test tests/nimony/cps`: all pass, the new test included.
- `hastur all`: 903/904. The failure is `cps/tclosure_iter_sets.nim`
  (`undefined reference to __builtin_popcount` at C link time). It passes when
  run alone with the patch, so it looks order- or cache-dependent. It was not
  compared against an unpatched `all` run.

Beyond the patch, the original points still apply:

1. Whatever the cause, a pragma block has to be transparent to the passive
   lowering. The test is `repro.nim`, next to the existing passive tests.
2. hexer should never report a crash without the source position of the
   routine it was lowering. `into:`'s assertion knows only the cursor; the
   pass that calls it knows the proc. A `bug` with that info would have turned
   an hour of bisection into a single line.

## Re-check at 358b9bc (2026-10-27)

**Fixed upstream, independently, three days after this was written:**
#2569 (668eddd, 2026-09-26, "passive calls from regular procs run to
completion") gives `PragmaxS` its own arm in `coro_transform.trGoto`. It is
the same design as `fix.diff`: a body without a suspension point keeps its
wrapper and goes through `trGotoScoped`, and a suspending body in a `cast`
block loses the wrapper and is laid out flat. This report was never filed.

All three repros compile at 358b9bc. The variant table, run again in one
program (`for` loop, iterator, `while`, two statements, a suspending call in a
`cast` block, `keepOverflowFlag` with two statements), prints the expected
`3 4 2 2 12 2`.

The one place #2569 differs from `fix.diff`: a suspension point inside a
non-`cast` pragma block. `fix.diff` reported a `bug` there. #2569 keeps the
wrapper, the program compiles, and it hangs at run time. That is friction/0006.

`fix.diff` no longer applies and is kept as a record.
