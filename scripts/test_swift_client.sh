#!/usr/bin/env bash
# Quick integration test: mcpc Swift client against the bundled test MCP server.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MCPC="${MCPC_BIN:-$ROOT/.build/debug/mcpc}"

if [[ ! -x "$MCPC" ]]; then
  echo "Building mcpc..."
  swift build
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "error: uv is required to run the test server (https://docs.astral.sh/uv/)" >&2
  exit 1
fi

echo "== list-servers =="
"$MCPC" list-servers

echo ""
echo "== ping =="
"$MCPC" -s test-server ping

echo ""
echo "== list-tools =="
"$MCPC" -s test-server list-tools

echo ""
echo "== call-tool echo =="
"$MCPC" -s test-server call-tool echo --message "hello from mcpc"

echo ""
echo "== call-tool add =="
"$MCPC" -s test-server call-tool add --a 2 --b 40

echo ""
echo "== read-resource =="
"$MCPC" -s test-server read-resource "test://info"

echo ""
echo "== list-resources =="
"$MCPC" -s test-server list-resources

echo ""
echo "== list-prompts =="
"$MCPC" -s test-server list-prompts

echo ""
echo "== get-prompt =="
"$MCPC" -s test-server get-prompt greet --name "Swift"

echo ""
echo "== call-tool server_info =="
"$MCPC" -s test-server call-tool server_info

echo ""
echo "All mcpc integration checks passed."
