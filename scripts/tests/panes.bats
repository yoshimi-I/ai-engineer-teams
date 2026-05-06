#!/usr/bin/env bats
# Tests for scripts/lib/panes.sh pure registry operations.
#
# We test the parts that don't touch zellij: registry parsing, counting,
# name/role classification, and write_pane_status_file atomic writes.

load helpers

setup() {
  ts_setup
  ts_load_common
  # shellcheck source=../lib/panes.sh
  source "${TS_LIB_DIR}/panes.sh"
}

teardown() {
  ts_teardown
}

# ── singleton_role ──────────────────────────────────────────────────────────

@test "singleton_role recognises the singleton roles" {
  for role in dev-server e2e e2e-bug-hunt ui-audit watch-main improve feature-discovery create-issue; do
    run singleton_role "$role"
    [ "$status" -eq 0 ] || { echo "$role should be singleton"; return 1; }
  done
}

@test "singleton_role rejects multi-instance roles" {
  for role in implement review fix-review; do
    run singleton_role "$role"
    [ "$status" -ne 0 ] || { echo "$role should not be singleton"; return 1; }
  done
}

# ── role_from_name ──────────────────────────────────────────────────────────

@test "role_from_name maps canonical names" {
  run role_from_name "dev-server"
  [ "$output" = "dev-server" ]
  run role_from_name "review"
  [ "$output" = "review" ]
  run role_from_name "review-pr-42"
  [ "$output" = "review" ]
  run role_from_name "fix-review"
  [ "$output" = "fix-review" ]
  run role_from_name "fix-review-pr-99"
  [ "$output" = "fix-review" ]
  run role_from_name "implement-issue-10"
  [ "$output" = "implement" ]
  run role_from_name "implement-1"
  [ "$output" = "implement" ]
  run role_from_name "e2e-hunt"
  [ "$output" = "e2e-bug-hunt" ]
  run role_from_name "ui-audit"
  [ "$output" = "ui-audit" ]
}

@test "role_from_name returns empty for unknown names" {
  run role_from_name "definitely-not-a-role"
  [ "$output" = "" ]
}

# ── count_alive / total_alive / role_active ─────────────────────────────────

@test "count_alive counts only alive entries for a role" {
  ts_seed_registry \
    "dev-server|dev-server|terminal_1|alive" \
    "implement-issue-1|implement|terminal_2|alive" \
    "implement-issue-2|implement|terminal_3|alive" \
    "implement-issue-3|implement|terminal_4|stopped" \
    "review-pr-10|review|terminal_5|alive"
  run count_alive "implement"
  [ "$output" = "2" ]
  run count_alive "review"
  [ "$output" = "1" ]
  run count_alive "dev-server"
  [ "$output" = "1" ]
  run count_alive "fix-review"
  [ "$output" = "0" ]
}

@test "total_alive counts all alive rows across all roles" {
  ts_seed_registry \
    "a|implement|terminal_1|alive" \
    "b|implement|terminal_2|alive" \
    "c|review|terminal_3|stopped" \
    "d|dev-server|terminal_4|alive"
  run total_alive
  [ "$output" = "3" ]
}

@test "total_alive returns nothing meaningful when registry is empty" {
  : > "$PANE_REGISTRY"
  run total_alive
  # grep returns empty or 0 depending on version; acceptable is "" or "0".
  [ "$output" = "0" ] || [ "$output" = "" ]
}

@test "role_active is true iff count_alive > 0" {
  ts_seed_registry "dev-server|dev-server|terminal_1|alive"
  run role_active "dev-server"
  [ "$status" -eq 0 ]
  run role_active "implement"
  [ "$status" -ne 0 ]
}

# ── pane_name_active ────────────────────────────────────────────────────────

@test "pane_name_active matches on name + alive status" {
  ts_seed_registry \
    "impl-1|implement|terminal_1|alive" \
    "impl-2|implement|terminal_2|stopped"
  run pane_name_active "impl-1"
  [ "$status" -eq 0 ]
  run pane_name_active "impl-2"
  [ "$status" -ne 0 ]
  run pane_name_active "nonexistent"
  [ "$status" -ne 0 ]
}

@test "pane_name_active distinguishes similar prefixes" {
  # "implement-issue-1" must not match "implement-issue-10"
  ts_seed_registry "implement-issue-1|implement|terminal_1|alive"
  run pane_name_active "implement-issue-1"
  [ "$status" -eq 0 ]
  run pane_name_active "implement-issue-10"
  [ "$status" -ne 0 ]
}

# ── write_pane_status_file ──────────────────────────────────────────────────

@test "write_pane_status_file writes a valid JSON status file atomically" {
  local f="${STATUS_DIR}/test-agent.json"
  write_pane_status_file "$f" "test-agent" "implement" "🔄 running" "cycle #1" "" "#42"
  [ -f "$f" ]
  run jq -r '.agent' "$f"
  [ "$output" = "test-agent" ]
  run jq -r '.prompt' "$f"
  [ "$output" = "implement" ]
  run jq -r '.state' "$f"
  [ "$output" = "🔄 running" ]
  run jq -r '.detail' "$f"
  [ "$output" = "cycle #1" ]
  run jq -r '.issue' "$f"
  [ "$output" = "#42" ]
  run jq -r '.cycle' "$f"
  [ "$output" = "0" ]
}

@test "write_pane_status_file uses epoch=now when not specified" {
  local f="${STATUS_DIR}/ep.json"
  local before after
  before=$(date +%s)
  write_pane_status_file "$f" "a" "implement" "state" "detail"
  after=$(date +%s)
  local epoch
  epoch=$(jq -r '.epoch' "$f")
  # epoch should be between before and after
  [ "$epoch" -ge "$before" ]
  [ "$epoch" -le "$after" ]
}

@test "write_pane_status_file honours an explicit epoch" {
  local f="${STATUS_DIR}/ep2.json"
  write_pane_status_file "$f" "a" "implement" "state" "detail" "" "" "" 5 2 1700000000
  run jq -r '.epoch' "$f"
  [ "$output" = "1700000000" ]
  run jq -r '.cycle' "$f"
  [ "$output" = "5" ]
  run jq -r '.errors' "$f"
  [ "$output" = "2" ]
}

# ── active_panes_json ───────────────────────────────────────────────────────

@test "active_panes_json emits well-formed JSON from the registry" {
  ts_seed_registry \
    "dev-server|dev-server|terminal_1|alive" \
    "impl-1|implement|terminal_2|alive"
  run active_panes_json
  [ "$status" -eq 0 ]
  run jq 'length' <<< "$output"
  [ "$output" = "2" ]
}

@test "active_panes_json returns empty array for empty registry" {
  : > "$PANE_REGISTRY"
  run active_panes_json
  [ "$status" -eq 0 ]
  run jq 'length' <<< "$output"
  [ "$output" = "0" ]
}

# ── record_registry_entry ───────────────────────────────────────────────────

@test "record_registry_entry replaces existing row with same name" {
  ts_seed_registry "dev-server|dev-server|terminal_1|alive"
  record_registry_entry "dev-server" "dev-server" "terminal_9" "alive"
  run grep -c '^dev-server|' "$PANE_REGISTRY"
  [ "$output" = "1" ]
  run grep '^dev-server|' "$PANE_REGISTRY"
  [ "$output" = "dev-server|dev-server|terminal_9|alive" ]
}

@test "record_registry_entry adds a new row when name is new" {
  : > "$PANE_REGISTRY"
  record_registry_entry "impl-1" "implement" "terminal_2" "alive"
  record_registry_entry "impl-2" "implement" "terminal_3" "alive"
  run wc -l < "$PANE_REGISTRY"
  [ "$(echo "$output" | tr -d ' ')" = "2" ]
}
