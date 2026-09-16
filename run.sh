#!/bin/bash
# Build caliper and launch it as a minimal .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "› building"
swift build --package-path "$ROOT" -c debug --product caliper

"$ROOT/bundle.sh" debug

pkill -x caliper 2>/dev/null || true
open -n "$ROOT/.build/Caliper.app"
