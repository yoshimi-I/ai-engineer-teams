#!/usr/bin/env bash
# Common helpers shared by orchestrator, agents, and control scripts.
#
# Exposes:
#   atomic_write <path> [mode]        — write stdin to <path> atomically via rename
#   atomic_write_json <path> <jq-expr> [args...] — build JSON with jq and write atomically
#   atomic_append <path> <line>       — append a line atomically (loss-free for concurrent writers)
#   safe_tmp <path>                   — mktemp a sibling of <path> (same filesystem → atomic rename works)
#   die <msg>                         — log to stderr and exit 1
#   log <level> <msg>                 — structured log line to stderr
#   trap_errors                       — install an ERR trap that prints location + exit code
#
# Design notes:
#   • rename(2) on the same filesystem is atomic on POSIX. We intentionally avoid
#     `flock`/`fcntl` for macOS portability.
#   • All writers go through atomic_write so concurrent readers never observe
#     partial files (e.g. half-written JSON that would break `jq` on consumers).

# Prevent double-sourcing.
if [ "${__KIRO_COMMON_SH_LOADED:-0}" = "1" ]; then
  return 0
fi
__KIRO_COMMON_SH_LOADED=1

# ── logging ─────────────────────────────────────────────────────────────────

log() {
  local level="$1"; shift
  local ts
  ts=$(date '+%Y-%m-%dT%H:%M:%S')
  printf '[%s] %s %s\n' "$ts" "$level" "$*" >&2
}

die() {
  log "ERROR" "$*"
  exit 1
}

# ── atomic file writes ──────────────────────────────────────────────────────

# safe_tmp <path> → echo a tempfile that lives next to <path> (same fs).
# The parent directory must exist or this function exits non-zero.
safe_tmp() {
  local target="$1"
  [ -n "$target" ] || return 1
  local dir base tmp
  dir=$(dirname -- "$target")
  base=$(basename -- "$target")
  [ -d "$dir" ] || return 1
  tmp=$(mktemp "${dir}/.${base}.XXXXXX") || return 1
  printf '%s' "$tmp"
}

# atomic_write <path> [mode]
# Reads stdin into a sibling tempfile, then renames into place.
# The rename is atomic on the same filesystem, so concurrent readers
# either see the old full contents or the new full contents — never a
# truncated partial write.
atomic_write() {
  local target="$1"
  local mode="${2:-}"
  [ -n "$target" ] || {
    log "ERROR" "atomic_write: missing target"
    return 1
  }
  local tmp
  tmp=$(safe_tmp "$target") || {
    log "ERROR" "atomic_write: safe_tmp failed for $target"
    return 1
  }
  # Arrange cleanup on any failure path.
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN
  if ! cat > "$tmp"; then
    rm -f "$tmp"
    trap - RETURN
    return 1
  fi
  if [ -n "$mode" ]; then
    chmod "$mode" "$tmp" 2>/dev/null || true
  fi
  if ! mv -f "$tmp" "$target"; then
    rm -f "$tmp"
    trap - RETURN
    return 1
  fi
  trap - RETURN
}

# atomic_write_json <path> <jq-expr> [jq-args...]
# Builds a JSON document via `jq -n` and writes it atomically. On jq failure,
# the target file is left untouched.
atomic_write_json() {
  local target="$1"; shift
  local expr="$1"; shift
  [ -n "$target" ] || { log "ERROR" "atomic_write_json: missing target"; return 1; }
  [ -n "$expr" ] || { log "ERROR" "atomic_write_json: missing jq expression"; return 1; }
  local tmp
  tmp=$(safe_tmp "$target") || return 1
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN
  if ! jq -n "$@" "$expr" > "$tmp"; then
    log "ERROR" "atomic_write_json: jq failed for $target"
    rm -f "$tmp"
    trap - RETURN
    return 1
  fi
  if ! mv -f "$tmp" "$target"; then
    rm -f "$tmp"
    trap - RETURN
    return 1
  fi
  trap - RETURN
}

# atomic_append <path> <line>
# Creates the target's parent directory if needed. Uses shell `>>` which is
# single-write for short lines on POSIX, so concurrent appenders will not
# interleave characters within a single line. For correctness across writers,
# ensure each call writes exactly one line.
atomic_append() {
  local target="$1"
  local line="$2"
  [ -n "$target" ] || return 1
  local dir
  dir=$(dirname -- "$target")
  [ -d "$dir" ] || mkdir -p "$dir"
  printf '%s\n' "$line" >> "$target"
}

# ── error traps ─────────────────────────────────────────────────────────────

# trap_errors
# Installs an ERR trap that emits the failed command, its location, and exit
# code before returning. Callers still need `set -e` for automatic propagation.
trap_errors() {
  # shellcheck disable=SC2154
  trap 'rc=$?; log "ERROR" "failed: cmd=\"${BASH_COMMAND}\" at ${BASH_SOURCE[0]}:${LINENO} rc=${rc}"; exit $rc' ERR
}
