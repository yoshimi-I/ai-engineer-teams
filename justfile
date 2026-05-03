# kiro-engineer-teams

# Install prerequisites (kiro-cli, zellij, gh, gum, jq)
setup:
    ./scripts/setup.sh

# Update to latest version
update:
    ./scripts/update.sh

# Initialize as your own private repo (run after git clone)
init:
    ./scripts/init.sh

# Start full pipeline (INCEPTION → orchestrated 12-agent pipeline)
start:
    ./scripts/start-pipeline.sh

# Launch pipeline directly (skip INCEPTION, use when steering is already configured)
pipeline:
    @LAYOUT_TMP=$(mktemp /tmp/pipeline-XXXXXX.kdl) && \
    sed "s|__PROJECT_CWD__|$(pwd)|g" scripts/pipeline.kdl > "$$LAYOUT_TMP" && \
    zellij --layout "$$LAYOUT_TMP"; \
    rm -f "$$LAYOUT_TMP"

# Restart from INCEPTION (clear previous artifacts and start fresh)
restart:
    rm -rf aidlc-docs/inception
    ./scripts/start-pipeline.sh

# Install into existing project (run from target project root)
install:
    bash <(curl -fsSL https://raw.githubusercontent.com/yoshimi-I/kiro-engineer-teams/main/scripts/install.sh)

# Switch to Japanese
ja:
    @scripts/sed-i.sh 's/Always respond to the user in English\./Always respond to the user in Japanese./' .kiro/steering/development-rules.md
    @scripts/sed-i.sh 's/Always respond in English\./Always respond in Japanese./' AGENTS.md
    @echo "✅ Switched to Japanese"

# Switch to English
en:
    @scripts/sed-i.sh 's/Always respond to the user in Japanese\./Always respond to the user in English./' .kiro/steering/development-rules.md
    @scripts/sed-i.sh 's/Always respond in Japanese\./Always respond in English./' AGENTS.md
    @echo "✅ Switched to English"

# Start all dev servers in background
dev:
    #!/usr/bin/env bash
    lsof -ti:3000 2>/dev/null | xargs -r kill -9 2>/dev/null || true
    lsof -ti:5173 2>/dev/null | xargs -r kill -9 2>/dev/null || true
    sleep 1
    cd api && nohup npm run dev > /tmp/dev-backend.log 2>&1 &
    cd web && nohup npm run dev > /tmp/dev-frontend.log 2>&1 &
    for i in $(seq 1 30); do
      if lsof -ti:3000 > /dev/null 2>&1 && lsof -ti:5173 > /dev/null 2>&1; then
        echo "✅ All servers ready"; exit 0
      fi
      sleep 2
    done
    echo "⚠️ Timeout"; exit 1

# Stop all dev servers
dev-stop:
    lsof -ti:3000 2>/dev/null | xargs -r kill -9 2>/dev/null || true
    lsof -ti:5173 2>/dev/null | xargs -r kill -9 2>/dev/null || true
    @echo "✅ Servers stopped"
