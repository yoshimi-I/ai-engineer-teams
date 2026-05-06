# kiro-engineer-teams

# Install prerequisites (kiro-cli, zellij, gh, gum, jq)
setup:
    ./scripts/setup.sh

# Upgrade all tools to latest versions
upgrade:
    @echo "⬆️  Upgrading tools..."
    @brew upgrade zellij gh just gum jq fswatch 2>/dev/null || true
    @echo "✅ Done. Run 'zellij --version' to verify."

# Run local checks for pipeline scripts
check:
    ./scripts/check.sh

# Diagnose local/GitHub prerequisites before starting the pipeline
preflight:
    ./scripts/preflight.sh

# Update to latest version
update:
    ./scripts/update.sh

# Continue pipeline from existing INCEPTION artifacts when present
start:
    ./scripts/start-pipeline.sh

# Launch pipeline directly (skip INCEPTION, use when steering is already configured)
pipeline:
    @LAYOUT_TMP=$(mktemp /tmp/pipeline-XXXXXX.kdl) && \
    sed "s|__PROJECT_CWD__|$(pwd)|g" scripts/pipeline.kdl > "$$LAYOUT_TMP" && \
    zellij --layout "$$LAYOUT_TMP"; \
    rm -f "$$LAYOUT_TMP"

# Restart pipeline from the first post-INCEPTION cycle
restart:
    ./scripts/restart-pipeline.sh

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
