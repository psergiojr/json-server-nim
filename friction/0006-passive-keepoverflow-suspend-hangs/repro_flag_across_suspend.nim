# With fix.diff applied: the overflow flag does not survive a suspension point.
# Expected (as in the other two procs): true. Actual with the fix: false.
# On stock 0305d6c, p hangs (this report's bug).
import std/syncio
proc six(): int {.passive.} = 6
proc nop() = discard
proc p(a, b: int) {.passive.} =
  {.keepOverflowFlag.}:
    let x = a + b
    discard six()
    echo "passive call between:     ", overflowFlag()
proc q(a, b: int) {.passive.} =
  {.keepOverflowFlag.}:
    let x = a + b
    nop()
    echo "plain call between:       ", overflowFlag()
proc r(a, b: int) {.passive.} =
  {.keepOverflowFlag.}:
    let x = a + b
    echo "nothing between:          ", overflowFlag()
proc main() {.passive.} =
  p(1, high(int)); q(1, high(int)); r(1, high(int))
main()
