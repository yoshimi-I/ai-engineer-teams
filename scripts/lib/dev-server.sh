#!/usr/bin/env bash

has_dev_target() {
  [ -f "justfile" ] && grep -Eq '^[[:space:]]*dev:' justfile && return 0
  [ -f "package.json" ] && return 0
  [ -f "pyproject.toml" ] && return 0
  [ -f "Cargo.toml" ] && return 0
  [ -f "go.mod" ] && return 0
  return 1
}

candidate_dev_urls() {
  {
    grep -Eho 'https?://(localhost|127\.0\.0\.1):[0-9]+' .agent-logs/dev-server.log 2>/dev/null || true
    printf '%s\n' \
      "http://localhost:5173" \
      "http://localhost:3000" \
      "http://localhost:4173" \
      "http://localhost:8000" \
      "http://localhost:8080"
  } | awk '!seen[$0]++'
}

check_dev_server_health() {
  local url healthy_url="" pane_count pane_ids error_log=""
  pane_count=$(count_alive "dev-server")
  pane_ids=$(awk -F'|' '$2 == "dev-server" && $4 == "alive" {print $3}' "$PANE_REGISTRY" 2>/dev/null | paste -sd, -)
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    if curl -fsS --max-time 1 "$url" >/dev/null 2>&1; then
      healthy_url="$url"
      break
    fi
  done < <(candidate_dev_urls)

  # Capture recent error from dev-server status or log
  if [ -f "${STATUS_DIR}/dev-server.json" ]; then
    local ds_state
    ds_state=$(jq -r '.state // ""' "${STATUS_DIR}/dev-server.json" 2>/dev/null || echo "")
    if [[ "$ds_state" == *error* ]] || [[ "$ds_state" == *dead* ]] || [[ "$ds_state" == *failed* ]]; then
      error_log=$(jq -r '.detail // ""' "${STATUS_DIR}/dev-server.json" 2>/dev/null || echo "")
    fi
  fi
  if [ -z "$error_log" ] && [ -f ".agent-logs/dev-server.log" ]; then
    # Get last error-like lines from log
    error_log=$(grep -i "error\|failed\|not found\|ENOENT\|command not found" .agent-logs/dev-server.log 2>/dev/null | tail -5 | tr '\n' ' ' | cut -c1-300)
  fi

  jq -n \
    --argjson pane_count "$pane_count" \
    --arg pane_ids "$pane_ids" \
    --arg url "$healthy_url" \
    --arg error "$error_log" \
    --arg ts "$(date '+%H:%M:%S')" \
    '{
      pane_count: $pane_count,
      pane_ids: ($pane_ids | split(",") | map(select(length > 0))),
      healthy: ($pane_count > 0 and $url != ""),
      port_only: ($pane_count == 0 and $url != ""),
      url: $url,
      error: $error,
      ts: $ts
    }' | atomic_write "$DEV_HEALTH_FILE"
}

dev_health_json() {
  if [ -f "$DEV_HEALTH_FILE" ]; then
    cat "$DEV_HEALTH_FILE"
  else
    jq -n '{pane_count: 0, healthy: false, url: "", ts: ""}'
  fi
}
