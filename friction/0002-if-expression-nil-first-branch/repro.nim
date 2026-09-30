type
  Obj = ref object
    k: int

proc pick(b: bool; o: Obj): nil Obj =
  result = if b: nil else: o

discard pick(true, Obj(k: 1))
