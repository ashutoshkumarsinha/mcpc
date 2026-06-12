#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -x "$ROOT/.build/debug/mcpc-gui" ]]; then
  swift build --product mcpc-gui
fi

exec "$ROOT/.build/debug/mcpc-gui"
