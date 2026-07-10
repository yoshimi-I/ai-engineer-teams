#!/usr/bin/env bash

if [ "${__GITHUB_AUTH_SH_LOADED:-0}" = "1" ]; then
  return 0
fi
__GITHUB_AUTH_SH_LOADED=1

gh_auth_status() {
  gh auth status >/dev/null 2>&1
}

gh_auth_status_without_env_token() {
  env -u GITHUB_TOKEN gh auth status >/dev/null 2>&1
}

recover_gh_auth_from_env_token() {
  [ -n "${GITHUB_TOKEN:-}" ] || return 1
  gh_auth_status_without_env_token || return 1
  unset GITHUB_TOKEN
}
