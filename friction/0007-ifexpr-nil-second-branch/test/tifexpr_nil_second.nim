# An if/case expression with a `nil` branch is typed from all branches: a
# not-nil branch before the `nil` (#2605 covered `nil` first), and a `nil`
# with no destination type to take its type from.
import std/syncio

type
  Obj = ref object
    k: int

proc swapped(b: bool; o: Obj): nil Obj =
  result = if b: o else: nil

proc swappedCase(k: int; o: Obj): nil Obj =
  result = case k
    of 1: o
    else: nil

proc letSwapped(b: bool; o: Obj): bool =
  let x: nil Obj = if b: o else: nil
  result = x == nil

proc take(o: nil Obj): bool = o == nil

proc callArg(b: bool; o: Obj): bool = take(if b: nil else: o)

proc trailing(b: bool; o: Obj): nil Obj =
  if b: nil else: o

let o = Obj(k: 1)
echo swapped(true, o) == nil, " ", swapped(false, o) == nil
echo swappedCase(1, o) == nil, " ", swappedCase(2, o) == nil
echo letSwapped(true, o), " ", letSwapped(false, o)
echo callArg(true, o), " ", callArg(false, o)
echo trailing(true, o) == nil, " ", trailing(false, o) == nil
