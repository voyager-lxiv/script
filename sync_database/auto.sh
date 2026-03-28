#!/usr/bin/env bash
# auto.sh - Interactive music database management menu

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

STAT_PATTERN='^\[INFO\] [A-Za-z].+: [0-9]'
TMPDIR_AUTO=$(mktemp -d)
trap 'rm -rf "$TMPDIR_AUTO"' EXIT

run_step() {
    local label="$1" collect="$2"; shift 2
    local statfile="$TMPDIR_AUTO/step.stat"
    log "$label"
    bash "$@" 2>&1 | tee "$statfile" | grep -vE "$STAT_PATTERN" || true
    if [[ "$collect" == "1" ]]; then
        local stat
        stat=$(grep -E "$STAT_PATTERN" "$statfile" | tail -n1 || true)
        if [[ -n "$stat" ]]; then
            local clean="${stat#\[INFO\] }"
            clean="${clean#Done\. }"
            log "$clean"
        fi
    fi
    echo ""
}

# ── MENU ──────────────────────────────────────────────────────────────────────
print_menu() {
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║           Music Database Manager         ║"
    echo "╠══════════════════════════════════════════╣"
    echo "║  1) Initialize database                  ║"
    echo "║  2) Import to WavPack                    ║"
    echo "║  3) Scan filesystem                      ║"
    echo "║  4) Sync ISRC table                      ║"
    echo "║  5) Convert streams (opus)               ║"
    echo "║  6) Convert streams (m4a)                ║"
    echo "║  7) Convert streams (mp3)                ║"
    echo "║  8) Sort quality folders                 ║"
    echo "║  9) Scan trash                           ║"
    echo "║ 10) Sync playlists                       ║"
    echo "║ 11) Run full auto sequence               ║"
    echo "║  q) Quit                                 ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    printf "Choose action: "
}

run_full_sequence() {
    log "Starting full auto sequence..."
    echo ""

    if [[ ! -f "$DATABASE_FILE" ]]; then
        log "Database not found — initializing..."
        bash "$SYNC" --create
        echo ""
    else
        log "Database exists — skipping init."
        echo ""
    fi

    run_step "Importing to WavPack..."    1  "$SYNC" --stream_import
    run_step "Scanning filesystem..."     1  "$SYNC" --scan .
    run_step "Syncing ISRC table..."      1  "$SYNC" --sync_isrc
    run_step "Converting streams (opus)..." 1  "$SYNC" --stream_convert
    run_step "Sorting quality folders..." 0  "$SYNC" --sort_qx
    run_step "Scanning trash..."          1  "$SYNC" --scan_trash
    run_step "Syncing playlists..."       1  "$SYNC" --sync_playlist

    log "Full sequence complete."
}

# ── MAIN LOOP ─────────────────────────────────────────────────────────────────
while true; do
    print_menu
    read -r CHOICE

    case "$CHOICE" in
        1)
            echo ""
            if [[ -f "$DATABASE_FILE" ]]; then
                printf "Database already exists. Reinitialize? [y/N]: "
                read -r CONFIRM
                [[ "${CONFIRM,,}" == "y" ]] || { echo "Cancelled."; continue; }
            fi
            bash "$SYNC" --create
            echo ""
            ;;
        2)
            echo ""
            printf "Use hybrid mode? [y/N]: "
            read -r HYB
            ARGS=""
            [[ "${HYB,,}" == "y" ]] && ARGS="--hybrid"
            run_step "Importing to WavPack..." 1 "$SYNC" --stream_import $ARGS
            ;;
        3)
            echo ""
            printf "Scan path [default: .]: "
            read -r SPATH
            SPATH="${SPATH:-.}"
            run_step "Scanning filesystem..." 1 "$SYNC" --scan "$SPATH"
            ;;
        4)
            echo ""
            run_step "Syncing ISRC table..." 1 "$SYNC" --sync_isrc
            ;;
        5)
            echo ""
            printf "Use lowpass filter? [y/N]: "
            read -r LP
            ARGS=""
            [[ "${LP,,}" == "y" ]] && ARGS="--lowpass"
            run_step "Converting streams (opus)..." 1 "$SYNC" --stream_convert $ARGS
            ;;
        6)
            echo ""
            printf "Quality [-q q1-q7/qx, default qx]: "
            read -r QQ
            ARGS=""
            [[ -n "$QQ" ]] && ARGS="-q $QQ"
            run_step "Converting streams (m4a)..." 1 "$SYNC" --stream_convert -f m4a $ARGS
            ;;
        7)
            echo ""
            printf "Quality [-q q1-q7/qx, default qx]: "
            read -r QQ
            ARGS=""
            [[ -n "$QQ" ]] && ARGS="-q $QQ"
            run_step "Converting streams (mp3)..." 1 "$SYNC" --stream_convert -f mp3 $ARGS
            ;;
        8)
            echo ""
            run_step "Sorting quality folders..." 0 "$SYNC" --sort_qx
            ;;
        9)
            echo ""
            run_step "Scanning trash..." 1 "$SYNC" --scan_trash
            ;;
        10)
            echo ""
            run_step "Syncing playlists..." 1 "$SYNC" --sync_playlist
            ;;
        11)
            echo ""
            run_full_sequence
            ;;
        q|Q)
            echo ""
            log "Bye."
            exit 0
            ;;
        *)
            echo ""
            echo "[ERROR] Invalid choice: '$CHOICE'"
            ;;
    esac
done
