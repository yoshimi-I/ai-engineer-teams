#!/usr/bin/env bash
# Usage: ./scripts/start-server.sh
# Starts the project's dev server using the best available local command.

set -euo pipefail

copy_env_examples() {
  local dir
  for dir in . packages/*; do
    [ -d "$dir" ] || continue
    if [ -f "${dir}/.env.example" ] && [ ! -f "${dir}/.env" ]; then
      cp "${dir}/.env.example" "${dir}/.env"
      echo "Created ${dir}/.env from ${dir}/.env.example"
    fi
  done
}

project_references() {
  local pattern="$1"
  if command -v rg >/dev/null 2>&1; then
    rg -q "$pattern" . \
      -g '!node_modules' \
      -g '!dist' \
      -g '!build' \
      -g '!.git' \
      -g '!.agent-logs' \
      -g '!.agent-status' 2>/dev/null
  else
    grep -R -q "$pattern" . \
      --exclude-dir=node_modules \
      --exclude-dir=dist \
      --exclude-dir=build \
      --exclude-dir=.git \
      --exclude-dir=.agent-logs \
      --exclude-dir=.agent-status 2>/dev/null
  fi
}

export_common_dev_defaults() {
  if [ -z "${DATABASE_URL:-}" ] && project_references "DATABASE_URL"; then
    export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/postgres"
    echo "Using local default DATABASE_URL=${DATABASE_URL}"
  fi
}

package_has_dev_script() {
  [ -f package.json ] && grep -Eq '"dev"[[:space:]]*:' package.json
}

run_package_dev() {
  if [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then
    exec pnpm dev
  fi
  if [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then
    exec yarn dev
  fi
  if [ -f bun.lockb ] && command -v bun >/dev/null 2>&1; then
    exec bun run dev
  fi
  if command -v npm >/dev/null 2>&1; then
    exec npm run dev
  fi
  echo "❌ package.json has a dev script, but no supported package manager was found."
  exit 1
}

copy_env_examples
export_common_dev_defaults

if command -v just >/dev/null 2>&1 && grep -Eq '^[[:space:]]*dev:' justfile 2>/dev/null; then
  exec just dev
fi

if package_has_dev_script; then
  run_package_dev
fi

if [ -f pyproject.toml ] && command -v uv >/dev/null 2>&1; then
  exec uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
fi

if [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
  exec cargo run
fi

if [ -f go.mod ] && command -v go >/dev/null 2>&1; then
  exec go run ./...
fi

echo "❌ No dev server command found."
echo "   Add a justfile 'dev' recipe or a package.json 'dev' script."
exit 1
