type
  Obj = ref object
    k: int

proc pick(b: bool; o: nil Obj): nil Obj =
  result = if b: Obj(k: 2) else: o

discard pick(true, Obj(k: 1))
