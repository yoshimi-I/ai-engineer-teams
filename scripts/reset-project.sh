#!/usr/bin/env bash
# Reset project state: close PRs, delete branches, unassign issues, fix labels.
#
# Operates on the current repository (resolved via `gh repo view`) and the
# currently authenticated user (resolved via `gh api user`). This script
# never targets a hard-coded repo or username, so running it in the wrong
# clone cannot accidentally delete branches in someone else's project.
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "❌ gh (GitHub CLI) is required" >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "❌ gh is not authenticated. Run: gh auth login" >&2
  exit 1
fi

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")
if [ -z "$REPO" ]; then
  echo "❌ Could not resolve current repo. Run this from inside a git repo whose origin is on GitHub." >&2
  exit 1
fi

GH_USER=$(gh api user --jq .login 2>/dev/null || echo "")
if [ -z "$GH_USER" ]; then
  echo "❌ Could not resolve gh user via 'gh api user'." >&2
  exit 1
fi

read -r -p "About to reset $REPO (close PRs, delete feature branches, unassign $GH_USER from issues). Continue? (y/N) → " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

STABLE_BRANCH="${AI_STABLE_BRANCH:-${KIRO_STABLE_BRANCH:-main}}"

echo "🔄 Project Reset: $REPO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Close all open PRs
echo ""
echo "📌 Step 1: Close all open PRs"
prs=$(gh pr list --repo "$REPO" --state open --limit 500 --json number --jq '.[].number')
if [ -z "$prs" ]; then
  echo "  No open PRs."
else
  for pr in $prs; do
    echo "  Closing PR #$pr..."
    gh pr close "$pr" --repo "$REPO" --delete-branch 2>/dev/null || true
  done
fi

# 2. Delete remaining remote feature branches (keep stable branch only)
echo ""
echo "🌿 Step 2: Delete remote feature branches"
branches=$(git ls-remote --heads origin 2>/dev/null | awk '{print $2}' | sed 's|refs/heads/||' | grep -v "^${STABLE_BRANCH}$" || true)
if [ -z "$branches" ]; then
  echo "  No feature branches."
else
  for branch in $branches; do
    echo "  Deleting origin/$branch..."
    git push origin --delete "$branch" --no-verify 2>/dev/null || true
  done
fi

# 3. Delete local feature branches
echo ""
echo "🧹 Step 3: Delete local feature branches"
git checkout "$STABLE_BRANCH" 2>/dev/null || true
git pull --rebase 2>/dev/null || true
local_branches=$(git branch | grep -v '^\*' | grep -v "^[[:space:]]*${STABLE_BRANCH}$" | tr -d ' ' || true)
if [ -z "$local_branches" ]; then
  echo "  No local feature branches."
else
  for branch in $local_branches; do
    echo "  Deleting $branch..."
    git branch -D "$branch" 2>/dev/null || true
  done
fi

# 4. Unassign all open issues
echo ""
echo "👤 Step 4: Unassign all open issues"
assigned=$(gh issue list --repo "$REPO" --state open --limit 500 --json number,assignees \
  --jq '.[] | select(.assignees | length > 0) | .number')
if [ -z "$assigned" ]; then
  echo "  No assigned issues."
else
  for issue in $assigned; do
    echo "  Unassigning issue #$issue..."
    gh issue edit "$issue" --repo "$REPO" --remove-assignee "$GH_USER" 2>/dev/null || true
  done
fi

# 5. Fix blocked labels (remove from issues whose deps are all closed)
echo ""
echo "🏷️  Step 5: Fix blocked labels"
issues_json=$(gh issue list --repo "$REPO" --state open --limit 100 --json number,body,labels)
closed_json=$(gh issue list --repo "$REPO" --state closed --limit 100 --json number)
unblock=$(echo "$issues_json" | jq -r --argjson closed "$closed_json" '
  [$closed[].number] as $closed_nums
  | .[]
  | select([.labels[]?.name] | index("blocked"))
  | ((.body // "" | [scan("(?:depends-on|blocked-by): *#([0-9]+)") | .[0] | tonumber]) // []) as $deps
  | select(($deps | length) == 0 or ([$deps[] | select(. as $d | $closed_nums | index($d) | not)] | length) == 0)
  | .number
')
if [ -z "$unblock" ]; then
  echo "  No issues to unblock."
else
  for issue in $unblock; do
    echo "  Removing 'blocked' from issue #$issue..."
    gh issue edit "$issue" --repo "$REPO" --remove-label blocked 2>/dev/null || true
  done
fi

# 6. Clean agent status
echo ""
echo "🗑️  Step 6: Clean agent status files"
rm -rf .agent-status 2>/dev/null || true
echo "  Removed .agent-status/"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Reset complete!"
echo ""
echo "Summary:"
echo "  - All open PRs closed"
echo "  - All feature branches deleted (local + remote)"
echo "  - All issue assignees removed"
echo "  - Blocked labels fixed based on dependency state"
echo "  - Agent status files cleaned"
echo ""
echo "You can now restart the pipeline with: just start"
