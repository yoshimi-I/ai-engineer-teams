#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# Tests for GitHub CLI authentication recovery helpers.

load helpers

setup() {
  ts_setup
  mkdir -p "${TS_ROOT}/bin"
  PATH="${TS_ROOT}/bin:/usr/bin:/bin"
  export PATH
}

teardown() {
  ts_teardown
}

write_fake_gh_env_token_bad_keychain_good() {
  cat > "${TS_ROOT}/bin/gh" <<'SH'
#!/usr/bin/env bash
if [ "$1 $2" = "auth status" ]; then
  [ -z "${GITHUB_TOKEN:-}" ]
  exit $?
fi
exit 1
SH
  chmod +x "${TS_ROOT}/bin/gh"
}

write_fake_gh_all_auth_bad() {
  cat > "${TS_ROOT}/bin/gh" <<'SH'
#!/usr/bin/env bash
if [ "$1 $2" = "auth status" ]; then
  exit 1
fi
exit 1
SH
  chmod +x "${TS_ROOT}/bin/gh"
}

@test "recover_gh_auth_from_env_token unsets invalid GITHUB_TOKEN when keychain auth works" {
  write_fake_gh_env_token_bad_keychain_good
  export GITHUB_TOKEN=bad-token
  # shellcheck disable=SC1091
  source "${TS_LIB_DIR}/github-auth.sh"

  run bash -c 'source "$1"; export GITHUB_TOKEN=bad-token; recover_gh_auth_from_env_token; [ -z "${GITHUB_TOKEN:-}" ]' _ "${TS_LIB_DIR}/github-auth.sh"
  [ "$status" -eq 0 ]
}

@test "recover_gh_auth_from_env_token fails when keychain auth also fails" {
  write_fake_gh_all_auth_bad
  export GITHUB_TOKEN=bad-token
  # shellcheck disable=SC1091
  source "${TS_LIB_DIR}/github-auth.sh"

  run recover_gh_auth_from_env_token
  [ "$status" -ne 0 ]
  [ "${GITHUB_TOKEN}" = "bad-token" ]
}
