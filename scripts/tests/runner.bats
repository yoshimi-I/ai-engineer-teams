#!/usr/bin/env bats
# shellcheck disable=SC1091,SC2016
# Tests for scripts/lib/runner.sh.

load helpers

setup() {
  ts_setup
}

teardown() {
  ts_teardown
}

source_runner_with() {
  local runner="$1"
  AI_RUNNER="$runner" KIRO_AI_RUNNER="" bash -c 'source "$1"; ai_runner_binary' _ "${TS_LIB_DIR}/runner.sh"
}

@test "ai_runner_binary maps codex to Codex CLI" {
  run source_runner_with codex
  [ "$status" -eq 0 ]
  [ "$output" = "codex" ]
}

@test "ai_run_oneshot uses codex exec for Codex CLI" {
  mkdir -p "${TS_ROOT}/bin"
  cat > "${TS_ROOT}/bin/codex" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CODEX_ARGS_FILE"
SH
  chmod +x "${TS_ROOT}/bin/codex"
  export PATH="${TS_ROOT}/bin:${PATH}"
  export CODEX_ARGS_FILE="${TS_ROOT}/codex-args.txt"

  run env AI_RUNNER=codex bash -c 'source "$1"; ai_run_oneshot "build the thing"' _ "${TS_LIB_DIR}/runner.sh"
  [ "$status" -eq 0 ]
  run cat "$CODEX_ARGS_FILE"
  [ "$output" = "exec --ask-for-approval never --sandbox danger-full-access build the thing" ]
}
