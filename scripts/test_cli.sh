#!/usr/bin/env bash
# CLI integration and error-path tests.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MCPC="${MCPC_BIN:-$ROOT/.build/debug/mcpc}"
CONFIG_FILE="$(mktemp -t mcpc-cli-test.XXXXXX.toml)"

cleanup() {
  rm -f "$CONFIG_FILE"
}
trap cleanup EXIT

if [[ ! -x "$MCPC" ]]; then
  swift build --product mcpc
fi

cat >"$CONFIG_FILE" <<EOF
[app]
name = "mcpc"
version = "1.0.0"

[client]
default_server = "test-server"
protocol_version = "2024-11-05"
request_timeout_seconds = 120

[logging]
level = "none"
destination = "none"

[[servers]]
name = "test-server"
transport = "stdio"
command = "uv"
args = ["run", "--directory", "test-server", "python", "server.py"]
env = { PYTHONUNBUFFERED = "1" }
EOF

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "error: $label — expected output to contain: $needle" >&2
    echo "got: $haystack" >&2
    exit 1
  fi
}

echo "== help =="
HELP_OUTPUT="$("$MCPC" --help)"
assert_contains "$HELP_OUTPUT" "list-tools" "help"

echo ""
echo "== list-servers with custom config =="
LIST_OUTPUT="$("$MCPC" -c "$CONFIG_FILE" list-servers)"
assert_contains "$LIST_OUTPUT" "test-server" "list-servers"

echo ""
echo "== list-resources =="
RES_OUTPUT="$("$MCPC" -c "$CONFIG_FILE" -s test-server list-resources)"
assert_contains "$RES_OUTPUT" "test://info" "list-resources"

echo ""
echo "== list-prompts =="
PROMPT_LIST="$("$MCPC" -c "$CONFIG_FILE" -s test-server list-prompts)"
assert_contains "$PROMPT_LIST" "greet" "list-prompts"

echo ""
echo "== call-tool server_info =="
INFO_OUTPUT="$("$MCPC" -c "$CONFIG_FILE" -s test-server call-tool server_info)"
assert_contains "$INFO_OUTPUT" "MCPC Test Server" "server_info tool"

echo ""
echo "== missing command error =="
set +e
MISSING_OUTPUT="$("$MCPC" 2>&1)"
MISSING_STATUS=$?
set -e
if [[ $MISSING_STATUS -eq 0 ]]; then
  echo "error: expected non-zero exit for missing command" >&2
  exit 1
fi
assert_contains "$MISSING_OUTPUT" "Missing command" "missing command"

echo ""
echo "== unknown server error =="
set +e
UNKNOWN_OUTPUT="$("$MCPC" -c "$CONFIG_FILE" -s missing-server ping 2>&1)"
UNKNOWN_STATUS=$?
set -e
if [[ $UNKNOWN_STATUS -eq 0 ]]; then
  echo "error: expected non-zero exit for unknown server" >&2
  exit 1
fi
assert_contains "$UNKNOWN_OUTPUT" "not found" "unknown server"

echo ""
echo "All CLI checks passed."
