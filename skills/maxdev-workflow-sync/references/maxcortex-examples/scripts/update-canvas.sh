#!/bin/bash
# update-canvas.sh — Wrapper para update_canvas.py
# Invocado pelo close-change.sh após criar spec mirror notes.
# Regenera o Knowledge Graph canvas do projeto para refletir
# o estado atual do knowledge graph.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Auto-detect Python: uv > python3 > python
if command -v uv &>/dev/null; then
    PYTHON="uv run python"
elif command -v python3 &>/dev/null; then
    PYTHON="python3"
else
    PYTHON="python"
fi

if [[ "${1:-}" == "--dry-run" ]]; then
    $PYTHON scripts/update_canvas.py --dry-run
else
    $PYTHON scripts/update_canvas.py
fi
