#!/usr/bin/env bash
# Run every tests/test_*.sh file.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0

shopt -s nullglob
tests=("${root}"/tests/test_*.sh)
if [[ ${#tests[@]} -eq 0 ]]; then
  echo "No tests found." >&2
  exit 1
fi

for test_file in "${tests[@]}"; do
  echo "=== $(basename "$test_file") ==="
  if ! bash "$test_file"; then
    failed=1
  fi
  echo
done

if [[ "$failed" -ne 0 ]]; then
  echo "Tests failed." >&2
  exit 1
fi

echo "All tests passed."
