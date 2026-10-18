#!/usr/bin/env bash
# Dev container / Codespaces: the tools the lint gates use (AGENTS.md, Commands).
# Docker + Compose come from the docker-in-docker feature.
set -euo pipefail

sudo apt-get update -qq
sudo apt-get install -y -qq shellcheck jq
# Same actionlint version CI uses (.github/workflows/lint.yml).
curl -sSfL https://raw.githubusercontent.com/rhysd/actionlint/v1.7.12/scripts/download-actionlint.bash \
  | sudo bash -s -- 1.7.12 /usr/local/bin

# Localhost defaults; the stack itself is started by hand (it needs ~5 GB).
[ -f .env ] || cp .env.example .env
echo "Ready. Gates: see AGENTS.md → Commands. Stack: docker compose up -d --wait && ./bootstrap.sh && ./verify.sh"
