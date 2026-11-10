**Title:** A passive call inside `{.keepOverflowFlag.}:` in a `.passive` proc compiles, then hangs

---

```nim
import std/syncio

proc six(): int {.passive.} = 6

proc p(): int {.passive.} =
  result = 0
  {.keepOverflowFlag.}:
    discard six()

proc main() {.passive.} = echo p()
main()
```

**Actual** at 0305d6c: compiles without a message, then hangs (no output).
`result += six()` in the block hangs the same way.

**Expected:** prints `0`, as it does with `{.cast(noSideEffect).}:` or a plain
`block:` in place of `keepOverflowFlag`. With `result += six()` twice, those
give `12`. So does `{.cast(uncheckedAssign).}:`.

**Cause:** the `PragmaxS` arm in `coro_transform.trGoto`, added by #2569, says
that a suspending body "must be flattened all the same — its state labels
belong at the top level — and only a `cast` block can give up its wrapper for
that". Every other pragma block keeps its wrapper and goes through
`trGotoScoped`. For `keepOverflowFlag`, that leaves the resume label nested
inside the `pragmax`. In the generated C, `p`'s resume state is empty and
returns an uninitialised continuation. The code after the call sits in state 0,
after its `return`.

**Which way to fix it?** I'd like your preference before opening a PR:

1. Flatten the block like a `cast` block, cut it at each state label, and
   re-wrap every piece in the original `pragmax`. `constparams` only needs the
   wrapper to know which arithmetic to check. I have this working, with a
   test. But the flag doesn't survive a suspension point:

   ```nim
   {.keepOverflowFlag.}:
     let x = a + b          # overflows
     discard six()          # a passive call
     echo overflowFlag()    # false; true with a plain call in place of six()
   ```

2. The same, plus keeping the flag in the coroutine's frame, so that it
   survives resumption.
3. Reject a suspension point inside `{.keepOverflowFlag.}` with an error. The
   flag is about the arithmetic right next to it.

<sub>Found while re-checking a json-server port to nimony with an AI coding
assistant; repro, cause and the options checked at 0305d6c.</sub>
