---
id: NNNN
title: <one line, the symptom, not the guess>
date: YYYY-MM-DD
component: nimony | nim2 | nimsuggest | nimlangserver | stdlib | atlas | <library>
version: <tag or commit sha — the thing upstream needs to reproduce>
severity: crash | hang | wrong-behavior | bad-message | missing-docs | ergonomics
status: open
upstream:
---

## What I was doing

<The Summer feature being built, in a sentence or two. Context for why anyone would
hit this.>

## Expected

<Write this BEFORE diagnosing. What did you assume would happen, and why? Name the
docs, the analogous API, or the intuition that produced the assumption.>

## Actual

<What happened. Paste the exact output — full error text, exit code, or a description
of the hang. Verbatim, not summarized.>

## Minimal repro

See `repro.nim`.

```
<exact command, e.g. nim c repro.nim>
```

<If it could not be minimized, say so here and explain what the minimization attempts
ruled out.>

## Notes / suspected cause

<Optional. Anything learned while digging. Clearly separate what was observed from
what is guessed.>

## Proposed fix

<Optional but valuable. A better error message written out in full, an API shape, or
a pointer at the code. "What to do", not just "it's wrong" — the same standard we
hold ourselves to.>
