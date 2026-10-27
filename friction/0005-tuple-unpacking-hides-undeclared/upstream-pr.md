**Title:** fixes #NNNN; tuple unpacking reports the value's own error

**Files:** `fix.diff` (`src/nimony/semdecls.nim`), plus
`test/ttupleunpack_failed_value.nim` and `.msgs` → `tests/nimony/errmsgs/`.

---

Fixes #NNNN.

`semUnpackDecl` now passes the semchecked value as `buildErr`'s origin, so a
value that already failed (an undeclared identifier) reports that error rather
than "expected tuple for tuple unpacking". A value that is simply not a tuple
(`let (u, v) = 3`) still gets the tuple message. The test covers both. Without
the change it prints "expected tuple for tuple unpacking" twice.

`hastur test` passes on `tests/nimony/{errmsgs, basics, stdlib, generics,
templates, iter, types, lookups, scopes, sysbasics, misc, object, notnil,
casestmt}` and `tests/contracts`.

**Not covered:** after a failed unpack, the unpacked names are not declared,
so each later use is another "undeclared identifier". That is true for any
failed unpack, before and after this change.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
