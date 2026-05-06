#!/usr/bin/env bash
set -euo pipefail

INTEGRATION_BRANCH="${KIRO_INTEGRATION_BRANCH:-develop}"
STABLE_BRANCH="${KIRO_STABLE_BRANCH:-main}"
failures=0
warnings=0

ok() { printf '  \033[32m✔\033[0m %s\n' "$1"; }
warn() { warnings=$((warnings + 1)); printf '  \033[33m⚠\033[0m %s\n' "$1"; }
fail() { failures=$((failures + 1)); printf '  \033[31m✘\033[0m %s\n' "$1"; }

version_ge() {
  local version="$1" minimum="$2"
  awk -v version="$version" -v minimum="$minimum" '
    BEGIN {
      split(version, v, ".")
      split(minimum, m, ".")
      for (i = 1; i <= 3; i++) {
        vi = v[i] + 0
        mi = m[i] + 0
        if (vi > mi) exit 0
        if (vi < mi) exit 1
      }
      exit 0
    }'
}

echo "🔎 Preflight"

for cmd in git gh jq zellij kiro-cli; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd found"
  else
    fail "$cmd is required"
  fi
done

if command -v zellij >/dev/null 2>&1; then
  zellij_version=$(zellij --version 2>/dev/null | awk '{print $2}')
  if version_ge "${zellij_version:-0.0.0}" "0.44.1"; then
    ok "zellij >= 0.44.1 (${zellij_version})"
  else
    fail "zellij >= 0.44.1 is required (found ${zellij_version:-unknown})"
  fi
fi

if gh auth status >/dev/null 2>&1; then
  ok "gh authenticated"
else
  fail "gh is not authenticated. Run: gh auth login"
fi

if git remote get-url origin >/dev/null 2>&1; then
  ok "git origin configured"
else
  fail "git remote origin is not configured"
fi

if gh repo view --json nameWithOwner >/dev/null 2>&1; then
  default_branch=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "")
  if [ "$default_branch" = "$STABLE_BRANCH" ]; then
    ok "default branch is ${STABLE_BRANCH}"
  else
    warn "default branch is ${default_branch:-unknown}; expected ${STABLE_BRANCH}"
  fi

  if git ls-remote --exit-code --heads origin "$INTEGRATION_BRANCH" >/dev/null 2>&1; then
    ok "integration branch exists: ${INTEGRATION_BRANCH}"
  else
    warn "integration branch missing: ${INTEGRATION_BRANCH}; start-pipeline will create it from ${STABLE_BRANCH}"
  fi

  if gh secret list 2>/dev/null | grep -q '^KIRO_API_KEY'; then
    ok "GitHub secret KIRO_API_KEY exists"
  else
    warn "GitHub secret KIRO_API_KEY is missing; kiro review action cannot run"
  fi

  if gh workflow view kiro-review.yml >/dev/null 2>&1; then
    ok "kiro-review workflow is installed"
  else
    warn "kiro-review workflow is missing"
  fi

  if gh workflow view promote-main.yml >/dev/null 2>&1; then
    ok "promote-main workflow is installed"
  else
    warn "promote-main workflow is missing"
  fi

  actions_permission=$(gh api "repos/{owner}/{repo}/actions/permissions/workflow" --jq '.default_workflow_permissions' 2>/dev/null || echo "")
  if [ "$actions_permission" = "write" ]; then
    ok "GitHub Actions workflow permissions are write"
  elif [ -n "$actions_permission" ]; then
    warn "GitHub Actions workflow permissions are ${actions_permission}; PR merge/promotion may fail"
  else
    warn "could not read GitHub Actions workflow permissions"
  fi
fi

if [ -n "${KIRO_E2E_COMMAND:-}" ]; then
  ok "KIRO_E2E_COMMAND is configured"
elif [ -f justfile ] && command -v just >/dev/null 2>&1 && just --list 2>/dev/null | grep -q '^    e2e'; then
  ok "just e2e detected"
elif [ -f package.json ] && jq -e '.scripts.e2e' package.json >/dev/null 2>&1; then
  ok "package.json e2e script detected"
else
  warn "no E2E command detected; main promotion will fail until KIRO_E2E_COMMAND, just e2e, or package.json e2e is configured"
fi

echo ""
if [ "$failures" -gt 0 ]; then
  echo "Preflight failed: ${failures} error(s), ${warnings} warning(s)."
  exit 1
fi

echo "Preflight passed: ${warnings} warning(s)."
