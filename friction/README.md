# Friction log — json-server-nim

Rules: `~/lab/summer-playbook/friction/README.md`. New reports come from
`~/lab/summer-playbook/friction/_template`; this repository keeps no copy.

Deltas for this project:

- **The log is the product** (playbook §1). A toolchain blocker is a reason to
  stop and minimize, not to fall back.
- **Components it stresses:** nimony's sema and nil checking (`nil T`
  everywhere in the JSON value type), the CPS/`.passive` lowering (the HTTP
  server), and the young stdlib (`std/json`, `std/httpserver`, `parseopt`,
  `algorithm`).
- **Tags:** only `[agent]`.

Scoreboard: `INDEX.generated.md`, from report frontmatter:

    ~/lab/summer-playbook/bin/frictionindex            # from the repo root

`INDEX.md` holds the hand-written history: the upstream re-checks.

## Each report directory

- `report.md`: the full report (frontmatter, Expected, Actual, repro, cause,
  fix, and a dated section for every re-check).
- `repro*.nim`: fails on a clean checkout of the `version` in the frontmatter.
- `upstream-issue.md`: the issue to open, title first, then the body. Short on
  purpose; the report is the long version.
- `upstream-pr.md` (and `upstream-pr-message.md` for 0004's second fix): the
  PR, where there is a fix. Title, which files go where, then the body.
  `#NNNN` is the issue's number, to fill in once it exists; `<permalink>` is a
  link to `report.md` once this repository is public (or drop the sentence).
  The bodies end with a "Generated with Claude Code" line; drop it if you'd
  rather not have it.
- `fix.diff`: `git apply fix.diff` from the nimony root, at the `version`.
- `test/`: the regression test and its golden file, for the tests directory
  the PR names.

`all-fixes.diff` is the fixes for 0004–0007 together (source only; the tests are in each `test/`), the tree that was tested as a whole.

Reports that upstream fixed before they were filed keep their `fix.diff` as a
record. It no longer applies.

## Filing

Open the issues first, then each PR with "Fixes #<issue>" filled in. The PRs
are independent of each other and apply together. Once filed, set
`status: reported` and `upstream: #NNNN` in `report.md`, then rerun
`frictionindex`.

Open at the last re-check (358b9bc): 0004 (issue + 2 PRs), 0005, 0006, 0007
(issue + PR each), 0008 (issue only). 0006's PR mentions 0008's issue number.
