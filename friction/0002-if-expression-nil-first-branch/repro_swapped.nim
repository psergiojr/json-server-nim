type
  Obj = ref object
    k: int
proc pick(b: bool; o: Obj): nil Obj =
  result = if b: o else: nil
discard pick(true, Obj(k: 1))
