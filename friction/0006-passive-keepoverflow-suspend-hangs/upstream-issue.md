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

**Actual** at 358b9bc: compiles without a message, then hangs (no output).

**Expected:** prints `0`, as it does with `{.cast(noSideEffect).}:` or a plain
`block:` in place of `keepOverflowFlag`.

**Cause:** #2569's `PragmaxS` arm in `coro_transform.trGoto` flattens a
suspending `cast` block, because its state labels must reach the top level.
Every other pragma block keeps its wrapper and goes through `trGotoScoped`.
For `keepOverflowFlag` that leaves the resume label nested inside the
`pragmax`. In the generated C, `p`'s resume state is empty and returns an
uninitialised continuation. The code after the call sits in state 0, after its
`return`.

PR with a fix and a test follows.

<sub>Found while re-checking a json-server port to nimony with an AI coding
assistant; repro and diagnosis checked by hand at 358b9bc.</sub>
