# kiro-engineer-teams

# Install prerequisites (kiro-cli, tmux, gh, gum, jq)
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
    ./scripts/tmux-layout.sh

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
