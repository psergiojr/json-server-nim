# A tuple unpacking whose value already failed reports that failure, not
# "expected tuple for tuple unpacking".

proc f(s: string): tuple[a, b: string] = (s, s)

let (x, y) = f(undeclaredThing("abc"))

let (u, v) = 3
