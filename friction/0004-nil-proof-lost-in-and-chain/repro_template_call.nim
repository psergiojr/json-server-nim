type
  Obj = ref object
    k: int
  Maybe = nil Obj

template isNull(v: Maybe): bool = v != nil and v.k == 0

proc `[]`(v: Maybe; key: string): Maybe = v

proc g(item: Maybe; key: string): bool =
  not item[key].isNull
