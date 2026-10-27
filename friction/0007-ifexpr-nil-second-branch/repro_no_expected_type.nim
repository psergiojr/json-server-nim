# `nil` first, with no destination type for it (a call argument).
# Expected: compiles. Actual at 358b9bc: "wanted: (nilt)".
type
  Obj = ref object
    k: int

proc take(o: nil Obj) = discard

proc g(b: bool; o: Obj) = take(if b: nil else: o)
