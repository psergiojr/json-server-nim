type
  Obj = ref object
    k: int
  Maybe = nil Obj

proc f(v: Obj): bool = v.k > 0

proc a(v: Maybe): bool = v != nil and f(v)
proc b(v: Maybe): bool = v != nil and true and f(v)
proc c(v: Maybe): bool =
  if v != nil and true:
    result = f(v)
  else:
    result = false
