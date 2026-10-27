# A `.passive` call inside `{.keepOverflowFlag.}:` in a `.passive` proc.
# Expected: prints 0. Actual at 358b9bc: compiles, then hangs.
import std/syncio

proc six(): int {.passive.} = 6

proc p(): int {.passive.} =
  result = 0
  {.keepOverflowFlag.}:
    discard six()

proc main() {.passive.} = echo p()
main()
