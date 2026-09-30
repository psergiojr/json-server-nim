proc count(s: seq[int]): int {.passive.} =
  result = 0
  {.cast(noSideEffect).}:
    for x in s: inc result
