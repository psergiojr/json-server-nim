# Two chained operations inside `{.keepOverflowFlag.}:`.
# Expected: prints true. Actual at 358b9bc: lengc "expected expression".
import std/syncio

proc p(a, b: int) =
  {.keepOverflowFlag.}:
    let y = a + b + 1
    echo overflowFlag()

p(1, high(int))
