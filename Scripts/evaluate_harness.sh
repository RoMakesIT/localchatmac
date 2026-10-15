#!/bin/zsh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVAL_DIR="$(mktemp -d "${TMPDIR:-/tmp/}lantern-evaluation.XXXXXX")"
trap 'rm -rf "$EVAL_DIR"' EXIT
export CLANG_MODULE_CACHE_PATH="$EVAL_DIR/ModuleCache"
export SWIFT_MODULECACHE_PATH="$EVAL_DIR/ModuleCache"
swiftc -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -target "$(uname -m)-apple-macosx15.0" \
  -D LANTERN_TESTING -parse-as-library \
  "$ROOT"/Sources/*.swift "$ROOT/Evaluations/HarnessEvaluation.swift" \
  -o "$EVAL_DIR/HarnessEvaluation"
if [[ "${1:-}" == "--compile-only" ]]; then
  echo "Harness evaluation compiled successfully."
  exit 0
fi
cd "$ROOT"
"$EVAL_DIR/HarnessEvaluation" "$@"
