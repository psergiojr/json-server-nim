proc count(): int {.passive.} =
  result = 0
  {.cast(noSideEffect).}:
    inc result
    inc result
