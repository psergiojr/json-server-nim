type
  Obj = ref object
    k: int
proc take(o: nil Obj) = discard
proc g(b: bool; o: Obj) = take(if b: nil else: o)
