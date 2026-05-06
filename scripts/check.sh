#!/usr/bin/env bash
set -euo pipefail

find scripts -name '*.sh' -print0 | xargs -0 -n1 bash -n
shellcheck -x -P scripts scripts/*.sh scripts/lib/*.sh
