#!/usr/bin/env bash
set -uo pipefail

REFRESH="${REPORT_REFRESH:-60}"
STATUS_DIR=".agent-status"
BOLD="\033[1m" DIM="\033[2m" R="\033[0m"
GREEN="\033[32m" YELLOW="\033[33m" RED="\033[31m" CYAN="\033[36m"

render() {
  clear
  echo -e "${BOLD}${CYAN}"
  echo "  ╔════════════════════════════════════════════╗"
  echo "  ║       📊  P R O G R E S S  R E P O R T    ║"
  echo "  ╚════════════════════════════════════════════╝${R}"
  echo ""

  # User attention items
  local attention_file="${STATUS_DIR}/user-attention.json"
  local items=""
  if [ -f "$attention_file" ]; then
    items=$(jq -r '.[] | "    ⚠️  [\(.from)] \(.message)"' "$attention_file" 2>/dev/null || true)
  fi
  echo -e "  ${BOLD}${RED}🚨 ユーザーに確認して欲しいこと${R}"
  if [ -n "$items" ]; then
    printf '%b\n' "${RED}${items}${R}"
  else
    echo -e "  ${DIM}なし${R}"
  fi
  echo ""

  # Issues
  # `gh issue list` defaults to 30 results, which silently capped the counter
  # at 30 even when the project had 40+ open issues. Always pass --limit with
  # a large ceiling so the totals match reality.
  local open closed total pct
  open=$(gh issue list --state open --limit 500 --json number --jq 'length' 2>/dev/null || echo 0)
  closed=$(gh issue list --state closed --limit 500 --json number --jq 'length' 2>/dev/null || echo 0)
  total=$((open + closed))
  pct=0; [ "$total" -gt 0 ] && pct=$((closed * 100 / total))

  echo -e "  ${BOLD}📋 Issues${R}"
  echo -e "    Total: ${total}  ${GREEN}Closed: ${closed}${R}  ${YELLOW}Open: ${open}${R}  完了率: ${BOLD}${pct}%${R}"

  # Progress bar
  local bar_len=30 filled empty
  filled=$((pct * bar_len / 100))
  empty=$((bar_len - filled))
  printf '    ['
  printf '%b' "${GREEN}"; printf '█%.0s' $(seq 1 "$filled" 2>/dev/null) || true; printf '%b' "${R}"
  printf '%b' "${DIM}"; printf '░%.0s' $(seq 1 "$empty" 2>/dev/null) || true; printf '%b' "${R}"
  printf ']\n'
  echo ""

  # In-progress issues
  local in_progress
  in_progress=$(gh issue list --state open --limit 500 --json number,title,assignees \
    --jq '.[] | select(.assignees | length > 0) | "    #\(.number) \(.title) ← \(.assignees[0].login)"' 2>/dev/null || true)
  if [ -n "$in_progress" ]; then
    echo -e "  ${BOLD}🔨 着手中${R}"
    echo -e "${DIM}${in_progress}${R}"
    echo ""
  fi

  local unassigned
  unassigned=$(gh issue list --state open --limit 500 --json number,title,assignees \
    --jq '.[] | select(.assignees | length == 0) | "    #\(.number) \(.title)"' 2>/dev/null || true)
  if [ -n "$unassigned" ]; then
    echo -e "  ${BOLD}📭 未着手${R}"
    echo -e "${DIM}${unassigned}${R}"
    echo ""
  fi

  # PRs
  local pr_open pr_merged pr_total
  pr_open=$(gh pr list --state open --limit 500 --json number --jq 'length' 2>/dev/null || echo 0)
  pr_merged=$(gh pr list --state merged --limit 500 --json number --jq 'length' 2>/dev/null || echo 0)
  pr_total=$((pr_open + pr_merged))

  echo -e "  ${BOLD}🔀 Pull Requests${R}"
  echo -e "    Total: ${pr_total}  ${GREEN}Merged: ${pr_merged}${R}  ${YELLOW}Open: ${pr_open}${R}"
  echo ""

  # Open PR details
  local pr_details
  pr_details=$(gh pr list --limit 500 --json number,title,reviewDecision \
    --jq '.[] | "    #\(.number) [\(.reviewDecision // "PENDING" | if . == "CHANGES_REQUESTED" then "修正必須" elif . == "APPROVED" then "承認済み" elif . == "REVIEW_REQUIRED" then "レビュー待ち" else "未レビュー" end)] \(.title)"' 2>/dev/null || true)
  if [ -n "$pr_details" ]; then
    echo -e "  ${BOLD}📝 Open PRs${R}"
    echo -e "${DIM}${pr_details}${R}"
    echo ""
  fi

  # Timeline: merged PRs with time, showing what feature was completed
  local timeline
  # shellcheck disable=SC2016
  timeline=$(gh pr list --state merged --limit 20 --json number,title,mergedAt,closingIssuesReferences \
    --jq '
      def jp_prefix:
        if startswith("feat") then "🆕 機能追加"
        elif startswith("fix") then "🐛 バグ修正"
        elif startswith("chore") then "🔧 整備"
        elif startswith("ci") then "⚙️ CI/CD"
        elif startswith("infra") then "☁️ インフラ"
        elif startswith("docs") then "📝 ドキュメント"
        elif startswith("refactor") then "♻️ リファクタ"
        elif startswith("test") then "🧪 テスト"
        elif startswith("style") then "🎨 スタイル"
        elif startswith("perf") then "⚡ 性能改善"
        else "📦 その他" end;
      def strip_prefix:
        capture("^[a-z]+(?:\\([^)]*\\))?[!]?:\\s*(?<rest>.+)") // {rest: .} | .rest;
      sort_by(.mergedAt) | reverse | .[] |
      (.mergedAt | split("T") | .[0] as $d | .[1] | split(".")[0] | "\($d) \(.)") as $time |
      (.closingIssuesReferences | map("#\(.number)") | join(",")) as $issues |
      (.title | jp_prefix) as $label |
      (.title | strip_prefix) as $desc |
      "    \($time)  \($label): \($desc)\(if $issues != "" then " (closes \($issues))" else "" end)"
    ' 2>/dev/null || true)
  if [ -n "$timeline" ]; then
    echo -e "  ${BOLD}📜 完了タイムライン${R}"
    echo -e "${DIM}${timeline}${R}"
    echo ""
  fi

  echo -e "  ${DIM}Updated: $(date '+%H:%M:%S')  Refresh: ${REFRESH}s${R}"
}

while true; do
  render
  sleep "$REFRESH"
done
