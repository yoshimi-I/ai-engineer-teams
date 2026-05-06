#!/usr/bin/env bash
# Pre-commit gate. Fails the process when any of the three checks fail.
# BATS and shellcheck are required locally as well as in CI to keep
# developer machines at CI parity — a silent skip lets regressions through.
# If a tool is missing, `just setup` installs it.
set -euo pipefail

# Syntax check.
find scripts -name '*.sh' -print0 | xargs -0 -n1 bash -n

# Style/lint.
if ! command -v shellcheck >/dev/null 2>&1; then
  echo "error: shellcheck is required. Run 'just setup' or install via your package manager." >&2
  exit 1
fi
shellcheck -x -P scripts scripts/*.sh scripts/lib/*.sh

# Unit tests.
if ! command -v bats >/dev/null 2>&1; then
  echo "error: bats is required. Run 'just setup' or 'brew install bats-core'." >&2
  exit 1
fi
bats scripts/tests/*.bats
