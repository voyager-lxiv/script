#!/usr/bin/env bash
# auto.sh - Runs the full sync sequence via sync_database.sh

set -euo pipefail

# SAFETY
[[ "$(basename "$PWD")" != "Music" ]] && {
    echo "[ERROR] Run from Music directory"
    exit 1
}

# CONFIG
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC="$SCRIPT_DIR/sync_database.sh"
DATABASE_FILE="./playlist/music_metadata.db"

# HELPERS
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; exit 1; }

[[ -f "$SYNC" ]] || err "sync_database.sh not found at: $SYNC"

declare -a STATS=()
STAT_PATTERN='^\[INFO\] [A-Za-z].+: [0-9]'
TMPDIR_AUTO=$(mktemp -d)
trap 'rm -rf "$TMPDIR_AUTO"' EXIT

run_step() {
    local step="$1" label="$2" collect="$3"; shift 3
    local statfile="$TMPDIR_AUTO/${step//\//}.stat"
    log "$step $label"
    # stream output live, tee to file, filter stat lines from terminal
    bash "$@" 2>&1 | tee "$statfile" | grep -vE "$STAT_PATTERN" || true
    if [[ "$collect" == "1" ]]; then
        local stat
        stat=$(grep -E "$STAT_PATTERN" "$statfile" | tail -n1 || true)
        if [[ -n "$stat" ]]; then
            local clean="${stat#\[INFO\] }"
            clean="${clean#Done\. }"
            STATS+=("[INFO] $step $clean")
        fi
    fi
    echo ""
}

log "Starting auto sequence..."
echo ""

# STEP 1
if [[ ! -f "$DATABASE_FILE" ]]; then
    log "[1/7] Database not found — initializing..."
    bash "$SYNC" --create
    echo ""
else
    log "[1/7] Database exists — skipping."
    echo ""
fi

# STEP 2
run_step "[2/7]" "Importing to WavPack..."    1  "$SYNC" --stream_import

# STEP 3
run_step "[3/7]" "Scanning filesystem..."     1  "$SYNC" --scan .

# STEP 4
run_step "[4/7]" "Syncing ISRC table..."      1  "$SYNC" --sync_isrc

# STEP 5
run_step "[5/7]" "Converting streams..."      1  "$SYNC" --stream_convert

# STEP 6 — no stat
run_step "[6/7]" "Sorting quality folders..." 0  "$SYNC" --sort_qx

# STEP 7
run_step "[7/7]" "Scanning trash..."          1  "$SYNC" --scan_trash

# FINAL STATS
for s in "${STATS[@]}"; do
    echo "$s"
done
