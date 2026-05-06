#!/usr/bin/env bash
# TUI Control Panel for Kiro Pipeline
# Displays agent status and allows stop/restart operations
set -euo pipefail

STATUS_DIR=".agent-status"
PANE_REGISTRY="${STATUS_DIR}/.panes"
REFRESH=60

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Colors
R='\033[0m'
DIM='\033[2m'
BOLD='\033[1m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
WHITE='\033[97m'

icon_for() {
  case "$1" in
    dev-server)   echo "🖥️ " ;;
    implement)    echo "🔨" ;;
    review)       echo "🔍" ;;
    fix-review)   echo "🔧" ;;
    watch-main)   echo "👀" ;;
    e2e-bug-hunt) echo "🧪" ;;
    ui-audit)     echo "🎨" ;;
    improve)      echo "💡" ;;
    idle)         echo "💤" ;;
    *)            echo "⚙️ " ;;
  esac
}

state_color() {
  case "$1" in
    *running*)  echo -e "${CYAN}" ;;
    *done*)     echo -e "${GREEN}" ;;
    *error*)    echo -e "${RED}" ;;
    *dead*)     echo -e "${RED}${BOLD}" ;;
    *waiting*)  echo -e "${YELLOW}" ;;
    *sleeping*) echo -e "${MAGENTA}" ;;
    *idle*)     echo -e "${DIM}" ;;
    *finished*) echo -e "${GREEN}" ;;
    *)          echo -e "${DIM}" ;;
  esac
}

discover_agents() {
  local files=("$STATUS_DIR"/*.json)
  [[ -e "${files[0]}" ]] || return
  for f in "${files[@]}"; do
    basename "$f" .json
  done | sort
}

pane_for_agent() {
  local agent="$1"
  [[ -f "$PANE_REGISTRY" ]] || return 1
  awk -F'|' -v agent="$agent" '$1 == agent { print $3; exit }' "$PANE_REGISTRY"
}

pane_exists() {
  local pane="$1"
  local id="${pane#terminal_}"
  [[ -n "$pane" ]] && zellij action list-panes --json 2>/dev/null \
    | jq -e --argjson id "$id" '.[] | select(.id == $id and (.exited | not))' >/dev/null 2>&1
}

record_pane() {
  local agent="$1" prompt="$2" pane="$3" state="$4"
  local tmp
  tmp=$(mktemp "${PANE_REGISTRY}.XXXXXX")
  grep -v "^${agent}|" "$PANE_REGISTRY" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$PANE_REGISTRY"
  echo "${agent}|${prompt}|${pane}|${state}" >> "$PANE_REGISTRY"
}

pipeline_tab_id() {
  zellij action list-tabs --json 2>/dev/null \
    | jq -r '.[] | select(.name == "Pipeline") | .tab_id' 2>/dev/null \
    | head -n 1
}

agents_tab_id() {
  zellij action list-tabs --json 2>/dev/null \
    | jq -r '.[] | select(.name == "Agents") | .tab_id' 2>/dev/null \
    | head -n 1
}

open_agent_pane() {
  local selection="$1" prompt="$2"
  local tab_id pane
  tab_id=$(agents_tab_id)
  if [[ -n "$tab_id" && "$tab_id" != "null" ]]; then
    pane=$(zellij action new-pane --tab-id "$tab_id" --name "$selection" --cwd "$(pwd)" \
      -- bash -lc "AGENT_ID='${selection}' AGENT_ONCE=true AGENT_INTERVAL=10 ./scripts/agent.sh '${prompt}'")
  else
    pane=$(zellij action new-pane --name "$selection" --cwd "$(pwd)" \
      -- bash -lc "AGENT_ID='${selection}' AGENT_ONCE=true AGENT_INTERVAL=10 ./scripts/agent.sh '${prompt}'")
  fi
  zellij action rename-pane --pane-id "$pane" "$selection" 2>/dev/null || true
  echo "$pane"
}

show_panel() {
  clear
  AGENTS=(); while IFS= read -r _a; do AGENTS+=("$_a"); done < <(discover_agents)
  # Header
  echo -e "${BOLD}${CYAN}"
  echo "  ╔══════════════════════════════════════════════════════════════════╗"
  echo "  ║          🎛️  K I R O   C O N T R O L   P A N E L  🎛️          ║"
  echo "  ╚══════════════════════════════════════════════════════════════════╝${R}"
  echo ""

  # Stats
  local total=0 running=0 errors=0 idle=0
  for id in "${AGENTS[@]}"; do
    f="${STATUS_DIR}/${id}.json"
    [[ -f "$f" ]] || continue
    total=$((total + 1))
    state=$(jq -r '.state // ""' "$f" 2>/dev/null || true)
    case "$state" in
      *running*) running=$((running + 1)) ;;
      *error*|*dead*) errors=$((errors + 1)) ;;
      *idle*) idle=$((idle + 1)) ;;
    esac
  done
  echo -e "  ${DIM}$(date '+%H:%M:%S')${R}  ${WHITE}Total: ${total}${R}  ${CYAN}▶ ${running}${R}  ${RED}✕ ${errors}${R}  ${DIM}💤 ${idle}${R}"
  echo ""

  # Agent list
  echo -e "  ${DIM}┌─────┬──────────────────┬──────────────┬──────────────────────────────────────┐${R}"
  printf "  ${DIM}│${R} ${BOLD} # ${R} ${DIM}│${R} ${BOLD}%-16s${R} ${DIM}│${R} ${BOLD}%-12s${R} ${DIM}│${R} ${BOLD}%-36s${R} ${DIM}│${R}\n" "Agent" "State" "Detail"
  echo -e "  ${DIM}├─────┼──────────────────┼──────────────┼──────────────────────────────────────┤${R}"

  local i=0
  for id in "${AGENTS[@]}"; do
    f="${STATUS_DIR}/${id}.json"
    [[ -f "$f" ]] || continue
    i=$((i + 1))

    prompt=$(jq -r '.prompt // ""' "$f" 2>/dev/null || echo "")
    state=$(jq -r '.state // "?"' "$f" 2>/dev/null || echo "?")
    detail=$(jq -r '.detail // ""' "$f" 2>/dev/null || echo "")
    cycle=$(jq -r '.cycle // 0' "$f" 2>/dev/null || echo "0")
    icon="$(icon_for "$prompt")"
    sc=$(state_color "$state")

    # Truncate detail
    [[ ${#detail} -gt 34 ]] && detail="${detail:0:33}…"

    printf "  ${DIM}│${R} %2d  ${DIM}│${R} %s %-14s ${DIM}│${R} ${sc}%-12s${R} ${DIM}│${R} %-36s ${DIM}│${R}\n" \
      "$i" "$icon" "$id" "$state" "${detail:-cycle #${cycle}}"
  done

  echo -e "  ${DIM}└─────┴──────────────────┴──────────────┴──────────────────────────────────────┘${R}"
  echo ""

  # Actions
  echo -e "  ${BOLD}⌨️  Actions${R}"
  echo -e "  ${DIM}─────────────────────────────────────────────────────────────────────${R}"
  echo -e "  ${CYAN}[s]${R} Stop agent    ${CYAN}[r]${R} Restart agent    ${CYAN}[a]${R} Stop all"
  echo -e "  ${CYAN}[l]${R} View log      ${CYAN}[o]${R} Orchestrator     ${CYAN}[q]${R} Quit panel"
  echo ""

  # Current work (cached)
  local cache_file="${STATUS_DIR}/.cache/work_summary"
  local cache_ttl=15
  if [[ ! -f "$cache_file" ]] || [[ $(($(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || echo 0))) -ge $cache_ttl ]]; then
    mkdir -p "${STATUS_DIR}/.cache"
    {
      echo "issues:"
      gh issue list --state open --limit 500 --json number,title,assignees --jq '.[] | select(.assignees | length > 0) | "  #\(.number) \(.title[:40]) ← \(.assignees[0].login)"' 2>/dev/null || true
      echo "prs:"
      gh pr list --limit 500 --json number,title,headRefName,author,reviewDecision --jq '.[] | "  #\(.number) [\(.reviewDecision // "PENDING")] \(.title[:40]) ← \(.author.login)"' 2>/dev/null || true
    } > "$cache_file" 2>/dev/null
  fi

  echo -e "  ${BOLD}📋 Current Work${R}"
  echo -e "  ${DIM}─────────────────────────────────────────────────────────────────────${R}"
  if [[ -f "$cache_file" ]]; then
    local section=""
    while IFS= read -r line; do
      case "$line" in
        "issues:") section="issues"; echo -e "  ${YELLOW}Issues (in progress):${R}" ;;
        "prs:")    section="prs";    echo -e "  ${CYAN}Pull Requests:${R}" ;;
        "  #"*)
          if [[ "$section" == "issues" ]]; then
            echo -e "    ${GREEN}${line}${R}"
          else
            if [[ "$line" == *"APPROVED"* ]]; then
              echo -e "    ${GREEN}${line}${R}"
            elif [[ "$line" == *"CHANGES_REQUESTED"* ]]; then
              echo -e "    ${RED}${line}${R}"
            else
              echo -e "    ${YELLOW}${line}${R}"
            fi
          fi
          ;;
      esac
    done < "$cache_file"
  fi
  echo ""
}

stop_agent() {
  AGENTS=(); while IFS= read -r _a; do AGENTS+=("$_a"); done < <(discover_agents)
  local selection
  selection=$(printf '%s\n' "${AGENTS[@]}" | gum choose --header "Select agent to stop:")
  [[ -z "$selection" ]] && return

  local f="${STATUS_DIR}/${selection}.json"
  local pane
  pane=$(pane_for_agent "$selection" || true)
  if pane_exists "$pane"; then
    zellij action close-pane --pane-id "$pane" 2>/dev/null || true
  fi
  record_pane "$selection" "idle" "$pane" "stopped"
  # shellcheck disable=SC2016
  atomic_write_json "$f" \
    '{
      agent: $agent,
      prompt: "idle",
      state: "⏹️ stopped",
      detail: "manually stopped",
      cycle: 0,
      errors: 0,
      ts: $ts
    }' \
    --arg agent "$selection" \
    --arg ts "$(date '+%H:%M:%S')"
  echo -e "  ${RED}⏹️  Stopped ${selection}${R}"
  sleep 1
}

restart_agent() {
  AGENTS=(); while IFS= read -r _a; do AGENTS+=("$_a"); done < <(discover_agents)
  local selection
  selection=$(printf '%s\n' "${AGENTS[@]}" | gum choose --header "Select agent to restart:")
  [[ -z "$selection" ]] && return

  local prompt
  prompt=$(jq -r '.prompt // "idle"' "${STATUS_DIR}/${selection}.json" 2>/dev/null || echo "idle")

  if [[ "$prompt" == "idle" ]]; then
    prompt=$(gum choose --header "Select role:" implement review fix-review watch-main e2e-bug-hunt ui-audit improve dev-server)
    [[ -z "$prompt" ]] && return
  fi

  local pane
  pane=$(pane_for_agent "$selection" || true)
  if pane_exists "$pane"; then
    zellij action close-pane --pane-id "$pane" 2>/dev/null || true
  fi
  pane=$(open_agent_pane "$selection" "$prompt")
  record_pane "$selection" "$prompt" "$pane" "alive"

  echo -e "  ${GREEN}▶ Restarted ${selection} as ${prompt}${R}"
  sleep 1
}

stop_all() {
  if gum confirm "Stop all agents?"; then
    AGENTS=(); while IFS= read -r _a; do AGENTS+=("$_a"); done < <(discover_agents)
    for id in "${AGENTS[@]}"; do
      local pane
      pane=$(pane_for_agent "$id" || true)
      if pane_exists "$pane"; then
        zellij action close-pane --pane-id "$pane" 2>/dev/null || true
      fi
      record_pane "$id" "idle" "$pane" "stopped"
      local f="${STATUS_DIR}/${id}.json"
      # shellcheck disable=SC2016
      atomic_write_json "$f" \
        '{
          agent: $agent,
          prompt: "idle",
          state: "⏹️ stopped",
          detail: "manually stopped",
          cycle: 0,
          errors: 0,
          ts: $ts
        }' \
        --arg agent "$id" \
        --arg ts "$(date '+%H:%M:%S')"
    done
    echo -e "  ${RED}⏹️  All agents stopped${R}"
    sleep 1
  fi
}

view_log() {
  AGENTS=(); while IFS= read -r _a; do AGENTS+=("$_a"); done < <(discover_agents)
  local selection
  selection=$(printf '%s\n' "${AGENTS[@]}" | gum choose --header "Select agent log:")
  [[ -z "$selection" ]] && return

  local logfile=".agent-logs/${selection}.log"
  if [[ -f "$logfile" ]]; then
    gum pager < "$logfile"
  else
    echo -e "  ${DIM}No log file for ${selection}${R}"
    sleep 1
  fi
}

toggle_orchestrator() {
  local tab_id
  tab_id=$(pipeline_tab_id)
  if [[ -n "$tab_id" && "$tab_id" != "null" ]]; then
    zellij action new-pane --tab-id "$tab_id" --name "Orchestrator" --cwd "$(pwd)" \
      -- bash -lc "./scripts/orchestrator.sh" >/dev/null
  else
    zellij action new-pane --name "Orchestrator" --cwd "$(pwd)" \
      -- bash -lc "./scripts/orchestrator.sh" >/dev/null
  fi
  echo -e "  ${GREEN}▶ Orchestrator pane started${R}"
  sleep 1
}

STALL_THRESHOLD="${CTRL_STALL_THRESHOLD:-600}"
OPERATOR_REQUEST="${STATUS_DIR}/operator-request.json"

check_stalled_agents() {
  local now stalled_list=""
  now=$(date +%s)
  AGENTS=(); while IFS= read -r _a; do AGENTS+=("$_a"); done < <(discover_agents)
  for id in "${AGENTS[@]}"; do
    local f="${STATUS_DIR}/${id}.json"
    [ -f "$f" ] || continue
    local epoch state
    epoch=$(jq -r '.epoch // 0' "$f" 2>/dev/null || echo 0)
    state=$(jq -r '.state // ""' "$f" 2>/dev/null || echo "")
    [ "$epoch" -gt 0 ] || continue
    local age=$(( now - epoch ))
    if [ "$age" -ge "$STALL_THRESHOLD" ] && [[ "$state" == *running* ]]; then
      stalled_list="${stalled_list}${id}(${age}s) "
    fi
  done
  if [ -n "$stalled_list" ]; then
    local cur_status
    cur_status=$(jq -r '.status // "empty"' "$OPERATOR_REQUEST" 2>/dev/null || echo empty)
    if [ "$cur_status" != "open" ]; then
      # shellcheck disable=SC2016
      atomic_write_json "$OPERATOR_REQUEST" \
        '{status:"open",ts:$ts,request:$request,intent:"general",target:"",priority:"high"}' \
        --arg ts "$(date '+%H:%M:%S')" \
        --arg request "STALL DETECTED: ${stalled_list}— auto-reported by control panel"
    fi
  fi
}

# Main loop
while true; do
  show_panel
  check_stalled_agents

  # Read single key with timeout
  if read -rsn1 -t "$REFRESH" key; then
    case "$key" in
      s) stop_agent ;;
      r) restart_agent ;;
      a) stop_all ;;
      l) view_log ;;
      o) toggle_orchestrator ;;
      q) exit 0 ;;
    esac
  fi
done
