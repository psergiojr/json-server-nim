# `if b: o else: nil` with a not-nil `o`, assigned to a nilable result.
# Expected: compiles. Actual at 358b9bc: "expected non-nil value".
type
  Obj = ref object
    k: int

proc pick(b: bool; o: Obj): nil Obj =
  result = if b: o else: nil

discard pick(true, Obj(k: 1))
