#!/usr/bin/env bash
# Integration test: mcpc against the bundled test MCP server over SSE transport.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MCPC="${MCPC_BIN:-$ROOT/.build/debug/mcpc}"
PORT="${MCP_SSE_PORT:-8765}"
SSE_URL="http://127.0.0.1:${PORT}/sse"
CONFIG_FILE="$(mktemp -t mcpc-sse-test.XXXXXX.toml)"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$CONFIG_FILE"
}
trap cleanup EXIT

if [[ ! -x "$MCPC" ]]; then
  echo "Building mcpc..."
  swift build
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "error: uv is required to run the test server (https://docs.astral.sh/uv/)" >&2
  exit 1
fi

cat >"$CONFIG_FILE" <<EOF
[app]
name = "mcpc"
version = "1.0.0"

[client]
default_server = "test-sse"
protocol_version = "2024-11-05"
request_timeout_seconds = 120
log_server_stderr = false

[logging]
level = "warning"
destination = "stderr"

[[servers]]
name = "test-sse"
transport = "sse"
url = "$SSE_URL"
trust_self_signed_certificates = false
connection_timeout_seconds = 30
max_reconnect_attempts = 3
reconnect_base_delay_seconds = 1.0
EOF

echo "Starting test MCP server (SSE on port $PORT)..."
uv run --directory test-server python server.py --transport sse --host 127.0.0.1 --port "$PORT" &
SERVER_PID=$!

echo "Waiting for SSE endpoint..."
for _ in $(seq 1 40); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "error: test server exited before SSE endpoint became ready" >&2
    exit 1
  fi
  if nc -z 127.0.0.1 "$PORT" 2>/dev/null; then
    sleep 0.5
    break
  fi
  sleep 0.25
done

echo ""
echo "== ping (SSE) =="
"$MCPC" -c "$CONFIG_FILE" ping

echo ""
echo "== list-tools (SSE) =="
"$MCPC" -c "$CONFIG_FILE" list-tools

echo ""
echo "== call-tool echo (SSE) =="
"$MCPC" -c "$CONFIG_FILE" call-tool echo --message "hello over sse"

echo ""
echo "All SSE integration checks passed."
