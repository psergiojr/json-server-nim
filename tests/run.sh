#!/usr/bin/env bash
# Build and run every tests/t*.nim with nimony. Run from anywhere; tests run
# from the repo root (tapp.nim serves ./public).
set -u
cd "$(dirname "$0")/.."
export PATH="${NIMONY_BIN:-$HOME/lab/nimony/bin}:$PATH"
failed=()
for t in tests/t*.nim; do
  name=$(basename "$t" .nim)
  out=$(nimony c -r "$t" 2>&1)
  status=$?
  summary=$(printf '%s\n' "$out" | grep '^# pass' | tail -1)
  if [ $status -eq 0 ]; then
    printf '%-22s %s\n' "$name" "${summary:-ok}"
  else
    printf '%-22s FAILED (exit %d)\n' "$name" "$status"
    printf '%s\n' "$out" | grep -v 'warning:\|^ *[0-9]* |\|^ *|\|In function' | tail -20 | sed 's/^/    /'
    failed+=("$name")
  fi
done
if [ ${#failed[@]} -gt 0 ]; then
  echo "failed: ${failed[*]}"
  exit 1
fi
echo "all passed"
