#!/usr/bin/env bash
# Run unit tests and all integration suites (CLI, SSE, GUI model).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== swift test (unit + GUI integration) =="
swift test

echo ""
echo "== CLI integration (stdio) =="
"$ROOT/scripts/test_swift_client.sh"

echo ""
echo "== CLI extended =="
"$ROOT/scripts/test_cli.sh"

echo ""
echo "== SSE integration =="
"$ROOT/scripts/test_sse_client.sh"

echo ""
echo "All tests passed."
