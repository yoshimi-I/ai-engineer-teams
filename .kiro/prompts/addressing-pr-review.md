---
name: addressing-pr-review
description: GitHub PR のレビューコメントに対応する: 各コメントを読み、修正、再push、解決マークまで実行する。
---
# PRレビュー対応

## Overview

Fetch PR review comments, implement fixes, commit with clear messages, and reply to each review thread.

**Core principle:** Fix → Commit with context → Reply to reviewer. Every comment gets a response.

## Process

### Step 1: Fetch Review Comments

```bash
# Get PR number (from current branch or ask user)
PR_NUMBER=$(gh pr view --json number -q .number)

# Get all review comments
gh pr view $PR_NUMBER --comments

# Get inline review comments with diff context
gh api repos/{owner}/{repo}/pulls/$PR_NUMBER/comments --jq '.[] | {id, path, line: .original_line, body, in_reply_to_id}'
```

Filter to unresolved/actionable comments only. Group by file.

### Step 2: Evaluate Each Comment

For each comment, determine:

```
1. AGREE → implement fix
2. DISAGREE → prepare technical reasoning
3. UNCLEAR → ask for clarification before touching code
```

**If any comment is unclear, ask before implementing anything.** Comments may be related.

### Step 3: Implement Fixes

Fix one comment (or related group) at a time:

```bash
# Make the code change
# Run tests to verify no regression
<project test command>

# Commit with review context
git commit -m "fix: <what changed> (PR review)

Addresses review comment: <brief summary of feedback>"
```

**Commit message rules:**
- Reference what the reviewer asked for
- Keep it concise but traceable
- Group related fixes into one commit if they touch the same logic

### Step 4: Reply to Review Threads

After committing each fix, reply in the GitHub comment thread:

```bash
# Reply to inline review comment thread
gh api repos/{owner}/{repo}/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies \
  -f body="Fixed in <commit-sha-short>. <brief description of what changed>"
```

**Reply format:**
- For fixes: `"Fixed in abc1234. <what changed>"`
- For disagreements: Technical reasoning with code references
- For clarifications: Ask the specific question

### Step 5: Push and Notify

```bash
git push origin <branch>

# Optional: leave a top-level PR comment summarizing all changes
gh pr comment $PR_NUMBER --body "Addressed review feedback:
- <summary of fix 1>
- <summary of fix 2>
..."
```

## Quick Reference

| Situation | Action |
|-----------|--------|
| Clear fix needed | Implement → commit → reply with commit SHA |
| Disagree with suggestion | Reply with technical reasoning |
| Unclear feedback | Ask before implementing anything |
| Multiple related comments | Group into one commit, reply to each |
| Comment already resolved | Skip |

## Common Mistakes

**Implementing without understanding**
- Fix: Read ALL comments first. Ask about unclear ones before starting.

**One giant commit for all fixes**
- Fix: Separate commits per comment/group. Makes review easier.

**Forgetting to reply to threads**
- Fix: Reply to EVERY actionable comment. Reviewers need to know it's addressed.

**Replying without commit reference**
- Fix: Always include the short SHA so reviewer can verify.

## Integration

**Pairs with:**
- **receiving-code-review** - For evaluating feedback quality
- **verification-before-completion** - Run tests before claiming fixes are done
- **finishing-a-development-branch** - After all review comments are addressed
