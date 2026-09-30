iterator items2(s: seq[int]): int =
  {.cast(noSideEffect).}:
    for x in s: yield x

proc count(s: seq[int]): int {.passive.} =
  result = 0
  for x in items2(s): inc result
