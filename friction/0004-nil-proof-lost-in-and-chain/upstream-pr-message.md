**Title:** "cannot prove expression is not nil" names the expression behind a compiler temp, not `` `x ``

**Files:** `fix_message.diff` (`src/nimony/contracts_fir.nim`), plus
`test/tnotnil_temp_name.nim` and `.msgs` → `tests/nimony/errmsgs/`.

Independent of the xelim PR. No issue of its own; the issue for the `and`
chain mentions it.

---

```nim
template isNull(v: Maybe): bool = v != nil and v.k == 0
proc g(item: Maybe; key: string): bool = not item[key].isNull
```

reports `cannot prove expression is not nil: `` `x ``. The check is right: the
template evaluates `item[key]` twice, and the two results are different values.
But `` `x `` is the basename of xelim's temp `` `x.N ``, which appears nowhere
in the source.

- `wantNotNil`: when the expression is a symbol whose name starts with a
  backtick, render the temp's initializer instead (`renderForNilMsg`).
- `traverseLocal`: register each local together with its initializer, so the
  initializer can be found.

The message becomes `cannot prove expression is not nil: item[key]`.

`hastur test` passes on `tests/nimony/{notnil, errmsgs, basics, stdlib}` and
`tests/contracts`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
