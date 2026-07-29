#!/usr/bin/env bash

set -euo pipefail

readonly SAFE_DIRECTORY="/workspaces/Coralie-Collection"
readonly UV_BIN_DIRECTORY="${HOME}/.local/bin"

npm install --global @openai/codex

if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh |
    env UV_INSTALL_DIR="${UV_BIN_DIRECTORY}" UV_NO_MODIFY_PATH=1 sh
fi

export PATH="${UV_BIN_DIRECTORY}:${PATH}"

uv tool install --python 3.13 serena-agent
serena init
serena setup codex

if codex mcp get github >/dev/null 2>&1; then
  codex mcp remove github
fi

codex mcp add github \
  --url https://api.githubcopilot.com/mcp/ \
  --bearer-token-env-var GITHUB_PAT_TOKEN

if ! git config --global --get-all safe.directory |
  grep -Fxq "${SAFE_DIRECTORY}"; then
  git config --global --add safe.directory "${SAFE_DIRECTORY}"
fi
