import std/syncio

proc f(s: string): tuple[a, b: string] = (s, s)

let (x, y) = f(undeclaredThing("abc"))
echo x
