#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VENV="$ROOT/.venv-memory"
PYTHON_BIN="${PYTHON_BIN:-python3}"

mkdir -p "$ROOT"

if [ ! -d "$VENV" ]; then
  "$PYTHON_BIN" -m venv "$VENV"
fi

source "$VENV/bin/activate"

if ! python -c "import chromadb, fastapi, sentence_transformers, uvicorn" >/dev/null 2>&1; then
  pip install -r "$ROOT/requirements.txt"
fi

exec uvicorn app:app --app-dir "$ROOT" --host 127.0.0.1 --port 8765
