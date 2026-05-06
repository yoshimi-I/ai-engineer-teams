#!/usr/bin/env bash

render() {
  clear
  echo -e "\033[1m\033[36m"
  echo "  ╔══════════════════════════════════════════════════════════════╗"
  echo "  ║            🎭  O R C H E S T R A T O R  🎭                ║"
  echo "  ╚══════════════════════════════════════════════════════════════╝"
  echo -e "\033[0m"

  local alive; alive=$(total_alive)
  local total; total=$(wc -l < "$PANE_REGISTRY" | tr -d ' ')
  echo -e "  \033[2m$(date '+%H:%M:%S')\033[0m  \033[32m▶ ${alive} 稼働\033[0m / ${total} 合計  📋 ready: \033[33m${READY_ISSUES:-?}\033[0m / open: \033[33m${ISSUES:-?}\033[0m  🔧 fixable: \033[31m${FIX_REVIEW_READY:-?}\033[0m / requested: \033[31m${CHANGES_REQ:-?}\033[0m  🔀 merge: $(if ${HAS_MERGES:-false}; then echo -e '\033[32m✓\033[0m'; else echo -e '\033[2m-\033[0m'; fi)"
  if [ -f "$DEV_HEALTH_FILE" ]; then
    local dev_ok dev_url dev_panes dev_port_only dev_pane_ids
    dev_ok=$(jq -r '.healthy // false' "$DEV_HEALTH_FILE" 2>/dev/null || echo false)
    dev_url=$(jq -r '.url // ""' "$DEV_HEALTH_FILE" 2>/dev/null || echo "")
    dev_panes=$(jq -r '.pane_count // 0' "$DEV_HEALTH_FILE" 2>/dev/null || echo 0)
    dev_port_only=$(jq -r '.port_only // false' "$DEV_HEALTH_FILE" 2>/dev/null || echo false)
    dev_pane_ids=$(jq -r '[.pane_ids[]?] | join(",")' "$DEV_HEALTH_FILE" 2>/dev/null || echo "")
    if [ "$dev_ok" = "true" ]; then
      echo -e "  🖥️  dev-server: \033[32mhealthy\033[0m ${dev_url}  panes:${dev_panes}${dev_pane_ids:+ (${dev_pane_ids})}"
    elif [ "$dev_port_only" = "true" ]; then
      echo -e "  🖥️  dev-server: \033[33mport only\033[0m ${dev_url}  panes:${dev_panes}  \033[2m古いサーバーが残っている可能性\033[0m"
    else
      echo -e "  🖥️  dev-server: \033[33mnot ready\033[0m  panes:${dev_panes}"
    fi
  fi
  local gh_err
  gh_err=$(find "$CACHE_DIR" -maxdepth 1 -name '*.err' -type f -print -quit 2>/dev/null)
  if [ -n "$gh_err" ]; then
    local gh_msg
    gh_msg=$(tr '\n' ' ' < "$gh_err" | sed 's/[[:space:]][[:space:]]*/ /g' | cut -c1-140)
    echo -e "  \033[33m⚠ github:\033[0m \033[2m${gh_msg}\033[0m"
  fi
  if [ -f "${OPERATOR_REQUEST_FILE:-}" ]; then
    local op_status op_request op_target
    op_status=$(jq -r '.status // "empty"' "$OPERATOR_REQUEST_FILE" 2>/dev/null || echo invalid)
    if [ "$op_status" = "open" ]; then
      op_request=$(jq -r '.request // ""' "$OPERATOR_REQUEST_FILE" 2>/dev/null || echo "")
      op_target=$(jq -r '.target // ""' "$OPERATOR_REQUEST_FILE" 2>/dev/null || echo "")
      echo -e "  \033[35m💬 operator:\033[0m \033[2m${op_target:+${op_target} }${op_request:0:120}\033[0m"
    fi
  fi
  if [ -n "${STALLED_PANES:-}" ]; then
    echo -e "  \033[31m⚠ STALLED (auto-killed):\033[0m \033[2m${STALLED_PANES# }\033[0m"
  fi
  echo ""

  local cols detail_width
  cols=$(tput cols 2>/dev/null || echo 120)
  detail_width=$((cols - 58))
  [ "$detail_width" -lt 24 ] && detail_width=24
  [ "$detail_width" -gt 80 ] && detail_width=80

  echo -e "  \033[1mAgents\033[0m"
  printf "  \033[2m%-22s %-13s %-8s %s\033[0m\n" "Name" "Role" "State" "Detail"
  printf "  \033[2m%-22s %-13s %-8s %s\033[0m\n" "----------------------" "-------------" "--------" "------------------------------"

  while IFS='|' read -r name role _pane status; do
    [ -z "$name" ] && continue

    local state_str="" issue_str="" pr_str="" branch_str="" detail=""
    if [ -f "${STATUS_DIR}/${name}.json" ]; then
      state_str=$(jq -r '.state // ""' "${STATUS_DIR}/${name}.json" 2>/dev/null || echo "")
      issue_str=$(jq -r '.issue // ""' "${STATUS_DIR}/${name}.json" 2>/dev/null || echo "")
      pr_str=$(jq -r '.pr // ""' "${STATUS_DIR}/${name}.json" 2>/dev/null || echo "")
      branch_str=$(jq -r '.branch // ""' "${STATUS_DIR}/${name}.json" 2>/dev/null || echo "")
      detail=$(jq -r '.detail // ""' "${STATUS_DIR}/${name}.json" 2>/dev/null || echo "")
    fi

    local rich_detail=""
    [ -n "$state_str" ] && rich_detail="${state_str}"
    [ -n "$issue_str" ] && rich_detail="${rich_detail} 📋${issue_str}"
    [ -n "$pr_str" ] && rich_detail="${rich_detail} 🔗${pr_str}"
    [ -n "$branch_str" ] && rich_detail="${rich_detail} 🌿${branch_str}"
    [ -n "$detail" ] && [ "$detail" != "$state_str" ] && rich_detail="${rich_detail} ${detail}"
    if [ ${#rich_detail} -gt "$detail_width" ]; then
      rich_detail="${rich_detail:0:$((detail_width - 1))}…"
    fi

    local state_label state_color
    if [ "$status" = "alive" ]; then
      state_label="running"
      state_color="\033[32m"
    else
      state_label="stopped"
      state_color="\033[31m"
    fi

    local color
    case "$role" in
      implement)    color="\033[33m" ;;
      fix-review)   color="\033[31m" ;;
      dev-server)   color="\033[32m" ;;
      watch-main)   color="\033[35m" ;;
      e2e)           color="\033[36m" ;;
      e2e-bug-hunt) color="\033[36m" ;;
      improve)      color="\033[34m" ;;
      *)            color="\033[2m" ;;
    esac

    local name_out="$name" role_out="$role"
    [ ${#name_out} -gt 22 ] && name_out="${name_out:0:21}…"
    [ ${#role_out} -gt 13 ] && role_out="${role_out:0:12}…"
    printf "  ${color}%-22s\033[0m %-13s ${state_color}%-8s\033[0m %s\n" "$name_out" "$role_out" "$state_label" "$rich_detail"
  done < "$PANE_REGISTRY"

  if [ "$(wc -l < "$PANE_REGISTRY" | tr -d ' ')" -eq 0 ]; then
    printf "  \033[2m%-22s %-13s %-8s %s\033[0m\n" "(起動中...)" "" "" ""
  fi
  echo ""

  local summary_file="${CACHE_DIR}/work_summary"
  local summary_age=999
  [ -f "$summary_file" ] && summary_age=$(( $(date +%s) - $(stat -f%m "$summary_file" 2>/dev/null || stat -c%Y "$summary_file" 2>/dev/null || echo 0) ))

  if [ "$summary_age" -ge "$CACHE_TTL" ]; then
    {
      echo "ISSUES_IN_PROGRESS:"
      gh issue list --state open --json number,title,assignees \
        --jq '.[] | select(.assignees | length > 0) | "  #\(.number) \(.title) ← \(.assignees[0].login)"' 2>/dev/null || true
      echo "OPEN_PRS:"
      gh pr list --json number,title,headRefName,reviewDecision \
        --jq '.[] | "  #\(.number) [\(.reviewDecision // "PENDING" | if . == "CHANGES_REQUESTED" then "修正必須" elif . == "APPROVED" then "承認済み" elif . == "REVIEW_REQUIRED" then "レビュー待ち" else "未レビュー" end)] \(.title) (\(.headRefName))"' 2>/dev/null || true
    } > "$summary_file" 2>/dev/null || true
  fi

  if [ -f "$summary_file" ]; then
    echo -e "  \033[1m📋 Current Work\033[0m"
    while IFS= read -r line; do
      case "$line" in
        "ISSUES_IN_PROGRESS:") echo -e "  \033[33mIssues (着手中):\033[0m" ;;
        "OPEN_PRS:") echo -e "  \033[36mPull Requests:\033[0m" ;;
        *)
          [ -n "$line" ] && echo -e "  \033[2m${line}\033[0m"
          ;;
      esac
    done < "$summary_file"
    echo ""
  fi

  local plan_source_label="${LAST_PLAN_SOURCE:-none}"
  case "$plan_source_label" in
    fallback|operator) plan_source_label="ユーザーからの命令" ;;
    ai) plan_source_label="AI planner" ;;
    guard) plan_source_label="ガード" ;;
  esac

  if [ -f "$AI_PLAN_FILE" ]; then
    echo -e "  \033[1m🧭 オーケストレーション方針\033[0m"
    echo -e "  \033[35m判断元:\033[0m \033[2m${plan_source_label}\033[0m"
    echo -e "  \033[32m判断:\033[0m \033[2m${LAST_DECISION_SUMMARY} ${LAST_DECISION_DETAIL} (${LAST_DECISION_TS:---:--:--}) next:${TICK_INTERVAL}s\033[0m"
    local actions stops skips
    actions=$(jq -r '
      def role_label:
        if . == "dev-server" then "開発サーバー"
        elif . == "implement" then "実装"
        elif . == "review" then "レビュー"
        elif . == "fix-review" then "レビュー修正"
        elif . == "e2e" then "E2E"
        elif . == "e2e-bug-hunt" then "E2E巡回"
        elif . == "watch-main" then "develop監視"
        elif . == "improve" then "改善提案"
        else . end;
      [.actions[]? | "  - " + ((.name // .role) | tostring) + "（" + (.role | role_label) + "）を作成: " + (.reason // "理由なし")]
      | .[]?
    ' "$AI_PLAN_FILE" 2>/dev/null)
    stops=$(jq -r '
      def role_label:
        if . == "dev-server" then "開発サーバー"
        elif . == "implement" then "実装"
        elif . == "review" then "レビュー"
        elif . == "fix-review" then "レビュー修正"
        elif . == "e2e" then "E2E"
        elif . == "e2e-bug-hunt" then "E2E巡回"
        elif . == "watch-main" then "develop監視"
        elif . == "improve" then "改善提案"
        else . end;
      [.stop[]? | "  - " + (.role | role_label) + "を停止: " + (.reason // "理由なし")]
      | .[]?
    ' "$AI_PLAN_FILE" 2>/dev/null)
    skips=$(jq -r '
      def role_label:
        if . == "dev-server" then "開発サーバー"
        elif . == "implement" then "実装"
        elif . == "review" then "レビュー"
        elif . == "fix-review" then "レビュー修正"
        elif . == "e2e" then "E2E"
        elif . == "e2e-bug-hunt" then "E2E巡回"
        elif . == "watch-main" then "develop監視"
        elif . == "improve" then "改善提案"
        else . end;
      [.skip[]? | "  - " + (.role | role_label) + "を見送り: " + (.reason // "理由なし")]
      | .[]?
    ' "$AI_PLAN_FILE" 2>/dev/null)
    echo -e "  \033[32m作成するpane:\033[0m"
    if [ -n "$actions" ]; then echo -e "\033[2m${actions}\033[0m"; else echo -e "  \033[2m- なし\033[0m"; fi
    echo -e "  \033[31m閉じるpane:\033[0m"
    if [ -n "$stops" ]; then echo -e "\033[2m${stops}\033[0m"; else echo -e "  \033[2m- なし\033[0m"; fi
    echo -e "  \033[33m見送り:\033[0m"
    if [ -n "$skips" ]; then echo -e "\033[2m${skips}\033[0m"; else echo -e "  \033[2m- なし\033[0m"; fi
    echo ""
  elif [ -f "${CACHE_DIR}/orchestrator_plan.raw" ] || [ -f "$DECISION_FILE" ]; then
    echo -e "  \033[1m🧭 オーケストレーション方針\033[0m"
    echo -e "  \033[35m判断元:\033[0m \033[2m${plan_source_label}\033[0m"
    echo -e "  \033[32m判断:\033[0m \033[2m${LAST_DECISION_SUMMARY} ${LAST_DECISION_DETAIL} (${LAST_DECISION_TS:---:--:--}) next:${TICK_INTERVAL}s\033[0m"
    if [ -f "${CACHE_DIR}/orchestrator_plan.raw" ]; then
      local raw_preview
      raw_preview=$(tr '\n' ' ' < "${CACHE_DIR}/orchestrator_plan.raw" | sed 's/[[:space:]][[:space:]]*/ /g')
      [ -n "$raw_preview" ] || raw_preview="empty response from AI planner"
      echo -e "  \033[33mAI応答:\033[0m \033[2m$(echo "$raw_preview" | fold -s -w $((cols - 4)))\033[0m"
    fi
    echo ""
  fi
}
