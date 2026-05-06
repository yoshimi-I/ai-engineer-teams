#!/usr/bin/env bash
# Reset project state: close PRs, delete branches, unassign issues, fix labels
set -euo pipefail

REPO="yoshimi-I/video-english-learn"

echo "🔄 Project Reset: $REPO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Close all open PRs
echo ""
echo "📌 Step 1: Close all open PRs"
prs=$(gh pr list --repo "$REPO" --state open --json number --jq '.[].number')
if [ -z "$prs" ]; then
  echo "  No open PRs."
else
  for pr in $prs; do
    echo "  Closing PR #$pr..."
    gh pr close "$pr" --repo "$REPO" --delete-branch 2>/dev/null || true
  done
fi

# 2. Delete remaining remote feature branches (keep main only)
echo ""
echo "🌿 Step 2: Delete remote feature branches"
branches=$(git ls-remote --heads origin 2>/dev/null | awk '{print $2}' | sed 's|refs/heads/||' | grep -v '^main$' || true)
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
git checkout main 2>/dev/null || true
git pull --rebase 2>/dev/null || true
local_branches=$(git branch | grep -v '^\*' | grep -v 'main' | tr -d ' ' || true)
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
assigned=$(gh issue list --repo "$REPO" --state open --json number,assignees \
  --jq '.[] | select(.assignees | length > 0) | .number')
if [ -z "$assigned" ]; then
  echo "  No assigned issues."
else
  for issue in $assigned; do
    echo "  Unassigning issue #$issue..."
    gh issue edit "$issue" --repo "$REPO" --remove-assignee yoshimi-I 2>/dev/null || true
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
