#!/usr/bin/env bash
set -uo pipefail

REFRESH="${REPORT_REFRESH:-60}"
BOLD="\033[1m" DIM="\033[2m" R="\033[0m"
GREEN="\033[32m" YELLOW="\033[33m" RED="\033[31m" CYAN="\033[36m" MAGENTA="\033[35m"

render() {
  clear
  echo -e "${BOLD}${CYAN}"
  echo "  ╔════════════════════════════════════════════╗"
  echo "  ║       📊  P R O G R E S S  R E P O R T    ║"
  echo "  ╚════════════════════════════════════════════╝${R}"
  echo ""

  # Issues
  local open closed total pct
  open=$(gh issue list --state open --json number --jq 'length' 2>/dev/null || echo 0)
  closed=$(gh issue list --state closed --json number --jq 'length' 2>/dev/null || echo 0)
  total=$((open + closed))
  pct=0; [ "$total" -gt 0 ] && pct=$((closed * 100 / total))

  echo -e "  ${BOLD}📋 Issues${R}"
  echo -e "    Total: ${total}  ${GREEN}Closed: ${closed}${R}  ${YELLOW}Open: ${open}${R}  完了率: ${BOLD}${pct}%${R}"

  # Progress bar
  local bar_len=30 filled empty
  filled=$((pct * bar_len / 100))
  empty=$((bar_len - filled))
  printf "    ["
  printf "${GREEN}"; printf '█%.0s' $(seq 1 $filled 2>/dev/null) || true; printf "${R}"
  printf "${DIM}"; printf '░%.0s' $(seq 1 $empty 2>/dev/null) || true; printf "${R}"
  echo "]"
  echo ""

  # In-progress issues
  local in_progress
  in_progress=$(gh issue list --state open --json number,title,assignees \
    --jq '.[] | select(.assignees | length > 0) | "    #\(.number) \(.title) ← \(.assignees[0].login)"' 2>/dev/null || true)
  if [ -n "$in_progress" ]; then
    echo -e "  ${BOLD}🔨 着手中${R}"
    echo -e "${DIM}${in_progress}${R}"
    echo ""
  fi

  local unassigned
  unassigned=$(gh issue list --state open --json number,title,assignees \
    --jq '.[] | select(.assignees | length == 0) | "    #\(.number) \(.title)"' 2>/dev/null || true)
  if [ -n "$unassigned" ]; then
    echo -e "  ${BOLD}📭 未着手${R}"
    echo -e "${DIM}${unassigned}${R}"
    echo ""
  fi

  # PRs
  local pr_open pr_merged pr_total
  pr_open=$(gh pr list --state open --json number --jq 'length' 2>/dev/null || echo 0)
  pr_merged=$(gh pr list --state merged --json number --jq 'length' 2>/dev/null || echo 0)
  pr_total=$((pr_open + pr_merged))

  echo -e "  ${BOLD}🔀 Pull Requests${R}"
  echo -e "    Total: ${pr_total}  ${GREEN}Merged: ${pr_merged}${R}  ${YELLOW}Open: ${pr_open}${R}"
  echo ""

  # Open PR details
  local pr_details
  pr_details=$(gh pr list --json number,title,reviewDecision,headRefName \
    --jq '.[] | "    #\(.number) [\(.reviewDecision // "PENDING")] \(.title)"' 2>/dev/null || true)
  if [ -n "$pr_details" ]; then
    echo -e "  ${BOLD}📝 Open PRs${R}"
    echo -e "${DIM}${pr_details}${R}"
    echo ""
  fi

  # Recent merges
  local recent
  recent=$(gh pr list --state merged --limit 5 --json number,title,mergedAt \
    --jq '.[] | "    #\(.number) \(.title) (\(.mergedAt | split("T")[0]))"' 2>/dev/null || true)
  if [ -n "$recent" ]; then
    echo -e "  ${BOLD}✅ 直近のマージ${R}"
    echo -e "${DIM}${recent}${R}"
    echo ""
  fi

  echo -e "  ${DIM}Updated: $(date '+%H:%M:%S')  Refresh: ${REFRESH}s${R}"
}

while true; do
  render
  sleep "$REFRESH"
done
