#!/bin/zsh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp/}lantern-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export CLANG_MODULE_CACHE_PATH="$TEST_DIR/ModuleCache"
export SWIFT_MODULECACHE_PATH="$TEST_DIR/ModuleCache"
swiftc -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -target "$(uname -m)-apple-macosx15.0" \
  -D LANTERN_TESTING -parse-as-library \
  "$ROOT"/Sources/*.swift "$ROOT"/Tests/*.swift \
  -o "$TEST_DIR/AgentProfilesTests"
"$TEST_DIR/AgentProfilesTests"
