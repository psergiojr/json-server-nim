# Friction index

The scoreboard and the list of reports are generated from report frontmatter
into `INDEX.generated.md` (`~/lab/summer-playbook/bin/frictionindex`, from the
repository root). Do not maintain them here.

`repros/` holds the raw minimal files as captured, including ones never
promoted.

## Upstream re-checks

| date | nimony | result |
|---|---|---|
| 2026-09-23 | 0e1761f → b2c2df7 (upstream HEAD, 4 commits incl. #2575) | all six repros reproduce unchanged |
| 2026-09-25 | b2c2df7 | causes of 0001, 0002, 0004 verified in the source; tested `fix.diff` for 0001–0004 |
| 2026-10-27 | b2c2df7 → 358b9bc (159 commits; `~/lab/nimony` HEAD, upstream HEAD on 2026-10-26) | **0001 fixed** by #2569 and **0003 fixed** by #2695, independently. **0002's crash fixed**: someone else reported it as #2605, fixed by #2611; its other forms → new 0007. **0004, 0005 reproduce.** New: 0006 (a hang in #2569's fix, found by re-running 0001's variants), 0007, 0008 (found while testing 0006). Fixes for 0004–0007 tested on 358b9bc, each alone and all together (see below). Unpromoted inbox lines re-checked: see INBOX, 2026-10-27. |

### 2026-10-27, how it was checked

- `~/lab/nimony/bin` was built at 358b9bc on 2026-10-26, except a stale
  `bin/hexer` (2026-09-24). At 358b9bc hexer is part of `shoggoth`, and
  nothing calls the old binary. A scratch rebuild of 358b9bc came out with
  byte-identical sizes.
- Every repro was run with that toolchain in a fresh directory.
- Fixes were built in scratch worktrees of 358b9bc with `nim c -d:release` and
  an explicit `--nimcache` per worktree. `hastur build` uses Nim's shared
  default nimcache (see INBOX, 2026-09-25).
- Each `fix.diff` applies alone to a clean 358b9bc (`git apply --check`), and
  each new test fails on stock 358b9bc.
- Each fix alone: the suites named in its report.
- All four together, with all new tests: `tests/nimony/{notnil, errmsgs, cps,
  passive, basics, basicarith, stdlib, sysbasics, misc, casestmt, iter,
  closures, object, borrows, templates, generics, types, lookups, scopes,
  strings, exceptions, async, streams, http, opt, const, consteval, enums,
  overload, modules, sets, when, macros, plugins, arc, orc, mm, threads,
  ioringepoll}`, `tests/contracts`, `tests/controlflow`.
- Not run: the whole `hastur all`, Windows, valgrind.
- Duplicates: GitHub issue search on 2026-10-27 (unauthenticated, until the
  rate limit), and `git log -S`/`-G` over b2c2df7..358b9bc for the code each
  report names. That is how #2569, #2605/#2611 and #2695 were found.
