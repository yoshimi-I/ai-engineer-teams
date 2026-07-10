#!/usr/bin/env bats
# shellcheck disable=SC2016
# Tests for scripts/preflight.sh runner-aware prerequisite checks.

load helpers

setup() {
  ts_setup
  mkdir -p "${TS_ROOT}/bin"
  PATH="${TS_ROOT}/bin:/usr/bin:/bin"
  export PATH
  write_fake_tools
}

teardown() {
  ts_teardown
}

write_executable() {
  local path="$1"
  shift
  printf '%s\n' "$@" > "$path"
  chmod +x "$path"
}

write_fake_tools() {
  write_executable "${TS_ROOT}/bin/claude" \
    '#!/usr/bin/env bash' \
    'exit 0'

  write_executable "${TS_ROOT}/bin/codex" \
    '#!/usr/bin/env bash' \
    'exit 0'

  write_executable "${TS_ROOT}/bin/jq" \
    '#!/usr/bin/env bash' \
    'exit 0'

  write_executable "${TS_ROOT}/bin/zellij" \
    '#!/usr/bin/env bash' \
    'if [ "${1:-}" = "--version" ]; then echo "zellij 0.44.3"; exit 0; fi' \
    'exit 0'

  write_executable "${TS_ROOT}/bin/git" \
    '#!/usr/bin/env bash' \
    'case "$*" in' \
    '  "remote get-url origin") exit 0 ;;' \
    '  "ls-remote --exit-code --heads origin develop") exit 1 ;;' \
    'esac' \
    'exit 0'

  write_executable "${TS_ROOT}/bin/gh" \
    '#!/usr/bin/env bash' \
    'case "$1 $2" in' \
    '  "auth status") exit 0 ;;' \
    '  "repo view")' \
    '    if [[ "$*" == *"defaultBranchRef"* ]]; then echo "main"; else echo "{\"nameWithOwner\":\"owner/repo\"}"; fi' \
    '    exit 0 ;;' \
    '  "secret list") echo "KIRO_API_KEY"; exit 0 ;;' \
    '  "workflow view") exit 0 ;;' \
    '  "api repos/{owner}/{repo}/actions/permissions/workflow") echo "write"; exit 0 ;;' \
    'esac' \
    'exit 0'
}

@test "preflight with AI_RUNNER=claude does not require kiro-cli" {
  run env AI_RUNNER=claude bash "${TS_REPO_ROOT}/scripts/preflight.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude found"* ]]
  [[ "$output" != *"kiro-cli is required"* ]]
}

@test "preflight with AI_RUNNER=kiro requires kiro-cli" {
  run env AI_RUNNER=kiro bash "${TS_REPO_ROOT}/scripts/preflight.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"kiro-cli is required"* ]]
}

@test "preflight with AI_RUNNER=codex uses Codex CLI" {
  run env AI_RUNNER=codex bash "${TS_REPO_ROOT}/scripts/preflight.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex found"* ]]
  [[ "$output" != *"kiro-cli is required"* ]]
}
