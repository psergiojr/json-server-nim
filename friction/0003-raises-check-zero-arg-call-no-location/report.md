---
id: 0003
title: "cannot call a routine marked as .raises" is reported at `???` for a call without arguments
date: 2026-09-23
component: nimony
version: nimony @ b2c2df77bf8f08f0c17ce4ed678d2495dc3f4f62 (2026-09-23); first seen at 0e1761f
severity: bad-message
status: fixed
upstream: #2695 (fixed independently on 2026-10-16; never filed)
---

## What I was doing

Resolving relative static-file directories in a non-raising constructor:
`getCurrentDir() & "/" & dir`. `getCurrentDir` is `{.raises.}`.

## Expected

The error, at the call:

```
app.nim(<line>, <col>) Error: cannot call a routine marked as `.raises` outside of a `try`..`except` block
```

## Actual

```
??? Error: cannot call a routine marked as `.raises` outside of a `try`..`except` block
```

No file, no line, in a 300-line module. I found the call by bisecting.

## Minimal repro

`repro.nim`:

```nim
proc zero(): int {.raises.} = raise Failure
proc one(x: int): int {.raises.} = raise Failure

proc a(): int = zero()
proc b(): int = one(1)
```

```
$ nimony c repro.nim
??? Error: cannot call a routine marked as `.raises` outside of a `try`..`except` block
repro.nim(5, 21) Error: cannot call a routine marked as `.raises` outside of a `try`..`except` block
```

The one-argument call is located, but at column 21, which is the *argument*
`1` and not the call.

## Cause

`derefs.trCallArgs` takes the location for this error from `n.endInfo`, and
its own comment says what that is: "`n` sits at the first arg — or already at
the call's (possibly elided) close when there are none". For a zero-argument
call that close has no position. The caller, `trCall`, already holds the call's
own position (`let info = n.info`) and does not pass it down.

This is the same pattern as Summer's friction/0002 (a zero-argument plugin call
anchored at `args.endInfo` in `templates.expandPlugin`): position taken from
"where the arguments are", which is nowhere when there are none.

## Proposed fix

`fix.diff`: pass `trCall`'s `info` into `trCallArgs` and use it for the
error. Tested at b2c2df7:

```
repro.nim(4, 21) Error: cannot call a routine marked as `.raises` outside of a `try`..`except` block
repro.nim(5, 20) Error: cannot call a routine marked as `.raises` outside of a `try`..`except` block
```

Both calls are now located at the call itself. The one existing golden with
this message (`tests/nimony/exceptions/traise_through_finally.msgs`, 13:14)
is byte-identical. `hastur tests/nimony/{exceptions,errmsgs,notnil,contracts}`
all SUCCESS. `repro.nim` is a new golden candidate for `tests/nimony/errmsgs`.

## Re-check at 358b9bc (2026-10-27)

**Fixed upstream, independently:** #2695 (159960c, 2026-10-16,
"Exceptions: only `ErrorCode` and `ref` objects are raised, and raises are
checked at calls") rewrote the raises check in `derefs` and passes `trCall`'s
`info` into `trCallArgs`, which is what `fix.diff` did. `repro.nim` now prints
exactly the output given under "Proposed fix" above:

```
repro.nim(4, 21) Error: cannot call a routine marked as `.raises` outside of a `try`..`except` block
repro.nim(5, 20) Error: cannot call a routine marked as `.raises` outside of a `try`..`except` block
```

Never filed. `fix.diff` no longer applies and is kept as a record.
