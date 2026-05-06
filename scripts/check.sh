#!/usr/bin/env bash
set -euo pipefail

# Syntax check.
find scripts -name '*.sh' -print0 | xargs -0 -n1 bash -n

# Style/lint.
shellcheck -x -P scripts scripts/*.sh scripts/lib/*.sh

# Unit tests. Skip gracefully if BATS is not installed locally; CI installs it
# explicitly. Developers without BATS still get the syntax + shellcheck gate.
if command -v bats >/dev/null 2>&1; then
  bats scripts/tests/*.bats
else
  echo "skip: bats not installed (brew install bats-core to enable unit tests)" >&2
fi
