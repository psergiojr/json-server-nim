import std/syncio
type
  Obj = ref object
    k: int
  Maybe = nil Obj

var calls = 0
proc f(v: Obj): bool =
  inc calls
  v.k > 0
proc t(x: bool): bool =
  inc calls
  x

proc b(v: Maybe): bool = v != nil and true and f(v)
proc b2(v: Maybe; p: bool): bool = v != nil and p and f(v)
proc o(v: Maybe; p: bool): bool = (v == nil or p) or f(v)
proc o2(v: Maybe): bool = (v == nil or false) or f(v)
proc n3(v: Maybe; p: bool): bool = not (v == nil or not p) and f(v)
proc mix(a, b2, c: bool): bool = (t(a) or t(b2)) and t(c)

echo b(nil), " ", b(Obj(k: 1)), " ", b(Obj(k: 0))
echo b2(nil, true), " ", b2(Obj(k: 1), false), " ", b2(Obj(k: 1), true)
echo o(nil, false), " ", o(Obj(k: 0), true), " ", o(Obj(k: 1), false), " ", o(Obj(k: 0), false)
echo o2(nil), " ", o2(Obj(k: 1))
echo n3(nil, true), " ", n3(Obj(k: 1), false), " ", n3(Obj(k: 1), true)
calls = 0
for a in [false, true]:
  for bb in [false, true]:
    for c in [false, true]:
      stdout.write $mix(a, bb, c) & " "
echo ""
echo calls
let x = true and true and true
let y = false or false or true
echo x, " ", y
