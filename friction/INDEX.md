# Friction index

Reports promoted from `INBOX.md`. Every repro re-checked against nimony
b2c2df7 (upstream HEAD, 2026-09-23) as well as 0e1761f.

| id | title | severity | status |
|---|---|---|---|
| 0001 | pragma block with 2+ statements in a `.passive` proc crashes hexer | crash | open (cause verified, fix tested) |
| 0002 | if-expression typed from its first branch: `if b: nil else: x` crashes hexer; nilable `else` fails the nil proof | crash | open (cause verified, partial fix tested) |
| 0003 | `.raises` check reports `???` for a zero-argument call | bad-message | open (fix tested) |
| 0004 | not-nil proof lost in a chained `and` | wrong-behavior | open (cause verified, fix tested) |
| 0005 | undeclared identifier in a tuple-unpacking `let` hidden behind "expected tuple" | bad-message | open |

`repros/` holds the raw minimal files as captured, including the ones not yet
promoted.
