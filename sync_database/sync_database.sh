#!/usr/bin/env bash
# sync_database.sh - Sync and manage the music metadata database.
# Usage: ./sync_database.sh --create | --scan | --scan_trash | --sync_isrc | --help

set -euo pipefail

# CONFIG
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INITIALIZE_SCRIPT="$SCRIPT_DIR/initialize.sh"
SCAN_SCRIPT="$SCRIPT_DIR/scan_filesystem.sh"
SCAN_DELETE_SCRIPT="$SCRIPT_DIR/scan_filesystem_trash.sh"
SYNC_ISRC_SCRIPT="$SCRIPT_DIR/sync_database_isrc.sh"
SORT_QX_SCRIPT="$SCRIPT_DIR/sort_qx_map.sh"
STREAM_CONVERT_SCRIPT="$SCRIPT_DIR/stream_convert.sh"
STREAM_IMPORT_SCRIPT="$SCRIPT_DIR/stream_import.sh"
SYNC_PLAYLIST_SCRIPT="$SCRIPT_DIR/sync_playlist.sh"

# HELPERS
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; exit 1; }

usage() {
    echo "Usage: $0 [OPTION] [PATH]"
    echo ""
    echo "Options:"
    echo "  --create                    Initialize the database and tables"
    echo "  --scan [PATH]               Scan audio files and sync to database (default: current dir)"
    echo "  --scan_trash                Mark missing files in DB with ./trash/ prefix"
    echo "  --sync_isrc                 Sync ISRC table from tracks and update audio_data status"
    echo "  --sort_qx                   Sort ./export files into quality folders from tracks_isrc"
    echo "  --stream_convert [--lowpass] [--debug]  Convert flac to opus using quality from tracks_isrc"
    echo "  --stream_import  [--hybrid]  [--debug]  Convert files to WavPack in ./import/raw"
    echo "  --sync_playlist                         Generate M3U8 playlist files from tracks_isrc"
    echo "  --help                      Show this help message"
    exit 0
}

# ARGUMENT PARSING
[[ $# -eq 0 ]] && { err "No argument provided. Use --create, --scan, --scan_trash, --sync_isrc, --sort_qx, --stream_convert, --stream_import, --sync_playlist, or --help."; }

case "$1" in
    --create)
        [[ -f "$INITIALIZE_SCRIPT" ]] || err "initialize.sh not found at: $INITIALIZE_SCRIPT"
        log "Running database initialization..."
        bash "$INITIALIZE_SCRIPT"
        ;;
    --scan)
        [[ -f "$SCAN_SCRIPT" ]] || err "scan_filesystem.sh not found at: $SCAN_SCRIPT"
        SCAN_DIR="${2:-.}"
        log "Running filesystem scan on: $SCAN_DIR"
        bash "$SCAN_SCRIPT" "$SCAN_DIR"
        ;;
    --scan_trash)
        [[ -f "$SCAN_DELETE_SCRIPT" ]] || err "scan_filesystem_trash.sh not found at: $SCAN_DELETE_SCRIPT"
        log "Running missing file check..."
        bash "$SCAN_DELETE_SCRIPT"
        ;;
    --sync_isrc)
        [[ -f "$SYNC_ISRC_SCRIPT" ]] || err "sync_database_isrc.sh not found at: $SYNC_ISRC_SCRIPT"
        log "Running ISRC sync..."
        bash "$SYNC_ISRC_SCRIPT"
        ;;
    --sort_qx)
        [[ -f "$SORT_QX_SCRIPT" ]] || err "sort_qx_map.sh not found at: $SORT_QX_SCRIPT"
        log "Running quality sort..."
        bash "$SORT_QX_SCRIPT" --sort
        ;;
    --stream_convert)
        [[ -f "$STREAM_CONVERT_SCRIPT" ]] || err "stream_convert.sh not found at: $STREAM_CONVERT_SCRIPT"
        log "Running stream convert..."
        bash "$STREAM_CONVERT_SCRIPT" "${@:2}"
        ;;
    --stream_import)
        [[ -f "$STREAM_IMPORT_SCRIPT" ]] || err "stream_import.sh not found at: $STREAM_IMPORT_SCRIPT"
        log "Running stream import..."
        bash "$STREAM_IMPORT_SCRIPT" "${@:2}"
        ;;
    --sync_playlist)
        [[ -f "$SYNC_PLAYLIST_SCRIPT" ]] || err "sync_playlist.sh not found at: $SYNC_PLAYLIST_SCRIPT"
        log "Running playlist sync..."
        bash "$SYNC_PLAYLIST_SCRIPT" "${@:2}"
        ;;
    --help|-h)
        usage
        ;;
    *)
        err "Unknown option: '$1'. Use --create, --scan, --scan_trash, --sync_isrc, --sort_qx, --stream_convert, --stream_import, --sync_playlist, or --help."
        ;;
esac
