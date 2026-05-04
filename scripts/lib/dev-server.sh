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
  local url healthy_url="" pane_count
  pane_count=$(count_alive "dev-server")
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    if curl -fsS --max-time 1 "$url" >/dev/null 2>&1; then
      healthy_url="$url"
      break
    fi
  done < <(candidate_dev_urls)

  jq -n \
    --argjson pane_count "$pane_count" \
    --arg url "$healthy_url" \
    --arg ts "$(date '+%H:%M:%S')" \
    '{
      pane_count: $pane_count,
      healthy: ($url != ""),
      url: $url,
      ts: $ts
    }' > "$DEV_HEALTH_FILE"
}

dev_health_json() {
  if [ -f "$DEV_HEALTH_FILE" ]; then
    cat "$DEV_HEALTH_FILE"
  else
    jq -n '{pane_count: 0, healthy: false, url: "", ts: ""}'
  fi
}
