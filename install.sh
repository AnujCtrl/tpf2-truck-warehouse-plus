#!/usr/bin/env bash
# Install this fork into Transport Fever 2's local mods folder as truck_warehouse_plus_1.
# Override the destination root with TPF2_LOCAL_MODS=/path/to/local/mods.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODS="${TPF2_LOCAL_MODS:-$HOME/.local/share/Steam/userdata/204184616/1066780/local/mods}"
DEST="$MODS/truck_warehouse_plus_1"
if pgrep -x TransportFever2 >/dev/null; then
  echo "Transport Fever 2 is running; close it first (it caches mod files)." >&2
  exit 1
fi
mkdir -p "$DEST"
rsync -a --delete \
  --exclude .git --exclude .gitignore --exclude test --exclude tools \
  --exclude install.sh --exclude README.md \
  "$SRC/" "$DEST/"
echo "installed to $DEST"
