proc zero(): int {.raises.} = raise Failure
proc one(x: int): int {.raises.} = raise Failure

proc a(): int = zero()
proc b(): int = one(1)
