#!/usr/bin/env bash
# scan_filesystem_trash.sh - Checks DB filepaths and marks missing files as trash.

set -euo pipefail

# CONFIG
DATABASE_FILE="playlist/music_metadata.db"
TABLE_NAME_1="tracks"

# HELPERS
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; exit 1; }
esc() { printf '%s' "$1" | sed "s/'/''/g"; }

# PRE-FLIGHT
command -v sqlite3 &>/dev/null || err "sqlite3 is not installed."
[[ -f "$DATABASE_FILE" ]]       || err "Database not found: $DATABASE_FILE — run initialize.sh first."

# SCAN
log "Verifying database filepaths..."

count_missing=0
count_duplicate=0
count_ok=0

while IFS='|' read -r id dbpath; do
    [[ -z "$dbpath" ]] && continue
    [[ -f "$dbpath" ]] && { ((count_ok++)) || true; continue; }
    [[ "$dbpath" == ./trash/* ]] && continue

    clean_path="${dbpath#./}"
    trash_path="./trash/$clean_path"

    echo "[MISSING] $dbpath"
    echo "       -> $trash_path"

    existing=$(sqlite3 -noheader "$DATABASE_FILE" \
        "SELECT id FROM $TABLE_NAME_1 WHERE filepath='$(esc "$trash_path")';")

    if [[ -n "$existing" ]]; then
        echo "[DUPLICATE] Removing ID $id (trash entry already exists)"
        sqlite3 "$DATABASE_FILE" "DELETE FROM $TABLE_NAME_1 WHERE id=$id;"
        ((count_duplicate++)) || true
    else
        sqlite3 "$DATABASE_FILE" <<EOF
UPDATE $TABLE_NAME_1
SET filepath='$(esc "$trash_path")'
WHERE id=$id;
EOF
        ((count_missing++)) || true
    fi

done < <(sqlite3 -noheader "$DATABASE_FILE" \
    "SELECT id, filepath FROM $TABLE_NAME_1;")

log "Done."
log "Files OK: $count_ok | Marked as trash: $count_missing | Duplicates removed: $count_duplicate"
