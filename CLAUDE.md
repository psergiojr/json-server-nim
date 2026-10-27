# json-server-nim — working agreement

A reimplementation of [typicode/json-server](https://github.com/typicode/json-server)
v1 (1.0.0-beta.15) on **nimony**, run the same way as `~/lab/summer`: the server is
the instrument, **the friction log is the product.**

Follows `~/lab/summer-playbook/PLAYBOOK.md`; this file states the deltas.
Playbook: summer-playbook@2fd3d35

## Log friction. Do not silently work around it.

When you hit a compiler/tooling/library crash or hang, a vague or misplaced error
message, an API that only worked on the second try, docs that contradict behavior,
an undocumented expectation you had to infer, or a fight with the memory model:
append one line to `friction/INBOX.md` **before continuing**, then work around it.
Tag `[agent]` for friction specific to working without an IDE. Promote lines to
reports with `~/lab/summer-playbook/friction/_template` (rules in
`~/lab/summer-playbook/friction/README.md`).

## Toolchain

Nimony at `~/lab/nimony`, binaries in `~/lab/nimony/bin` (put it on `PATH`).
Nim 2 is a comparison baseline only; nothing here has to compile under it.

    ./tests/run.sh            # build + run every tests/t*.nim
    nimony c src/jsonserver.nim   # binary lands in nimcache/<hash>/jsonserver

## Porting stance

Behavior follows the upstream TypeScript source and tests (`src/*.ts`,
`src/*.test.ts` at 1.0.0-beta.15). npm dependencies are ported to the extent
json-server uses them (inflection, sort-on, dot-prop, cors); every intentional
divergence is listed in README.md.
