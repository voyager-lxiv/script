#!/usr/bin/env bash
# stream_convert_m4a.sh - Converts flac/wv files to M4A/AAC based on quality from tracks_isrc table.

set -euo pipefail

# SAFETY
[[ "$(basename "$PWD")" != "Music" ]] && {
    echo "[ERROR] Run from Music directory"
    exit 1
}

# CONFIG
INPUT_ROOT_FLAC="./export/tag/flac"
INPUT_ROOT_WV="./export/tag/wv"
OUTPUT_ROOT="./export/tag/m4a"
DATABASE_FILE="./playlist/music_metadata.db"
TABLE_NAME_2="tracks_isrc"
ISRC_REGEX='\[([A-Za-z0-9]+)\]'
CURRENT_TMP=""

# HELPERS
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; exit 1; }

# TRAP: remove temp file if interrupted mid-conversion
cleanup() {
    if [[ -n "$CURRENT_TMP" && -f "$CURRENT_TMP" ]]; then
        echo "[ABORT] Removing incomplete file: $CURRENT_TMP"
        rm -f "$CURRENT_TMP"
    fi
}
trap cleanup EXIT INT TERM

# PRE-FLIGHT
command -v sqlite3 &>/dev/null || err "sqlite3 is not installed."
command -v ffmpeg  &>/dev/null || err "ffmpeg is not installed."
command -v python3 &>/dev/null || err "python3 is not installed."
[[ -f "$DATABASE_FILE" ]]      || err "Database not found: $DATABASE_FILE"

# QUALITY → BITRATE
get_bitrate() {
    case "$1" in
        q1) echo "320k" ;;
        q2) echo "256k" ;;
        q3) echo "192k" ;;
        q4) echo "160k" ;;
        q5) echo "128k" ;;
        q6) echo "96k"  ;;
        q7) echo "64k"  ;;
        *)  echo "320k" ;;
    esac
}

usage() {
    echo "Usage: $0 [--dynamic] [--debug]"
    echo ""
    echo "  --dynamic   Get quality per-track from tracks_isrc table"
    echo "  --debug     Show extra output"
    exit 0
}

# PARSE ARGS
DYNAMIC=0
DEBUG=0
for arg in "$@"; do
    case "$arg" in
        --dynamic) DYNAMIC=1 ;;
        --debug)   DEBUG=1 ;;
        --help|-h) usage ;;
        *) err "Unknown option: $arg" ;;
    esac
done

# CONVERT
count_converted=0
count_skipped=0
count_removed=0
count_no_entry=0

if [[ "$DEBUG" -eq 1 ]]; then
    total_flac=$(find "$INPUT_ROOT_FLAC" -type f -iname "*.flac" 2>/dev/null | wc -l)
    total_wv=$(find "$INPUT_ROOT_WV"     -type f -iname "*.wv"   2>/dev/null | wc -l)
    log "DEBUG: INPUT_ROOT_FLAC=$INPUT_ROOT_FLAC (flac files: $total_flac)"
    log "DEBUG: INPUT_ROOT_WV=$INPUT_ROOT_WV (wv files: $total_wv)"
fi

while IFS= read -r -d '' INPUT; do

    FILE="$(basename "$INPUT")"

    # extract ISRC from filename
    if [[ "$FILE" =~ $ISRC_REGEX ]]; then
        ISRC="${BASH_REMATCH[1]}"
    else
        [[ "$DEBUG" -eq 1 ]] && echo "[SKIP] no ISRC in filename: $FILE"
        continue
    fi

    # get quality
    if [[ "$DYNAMIC" -eq 1 ]]; then
        QTAG=$(sqlite3 -noheader "$DATABASE_FILE" \
            "SELECT quality FROM $TABLE_NAME_2 WHERE isrc='$ISRC' LIMIT 1;")
        if [[ -z "$QTAG" ]]; then
            [[ "$DEBUG" -eq 1 ]] && echo "[NO ENTRY] $ISRC | $FILE"
            ((count_no_entry++)) || true
            continue
        fi
    fi

    # relative path from input root, strip any leading q-folder
    if [[ "$INPUT" == "$INPUT_ROOT_FLAC"* ]]; then
        REL="${INPUT#"$INPUT_ROOT_FLAC"/}"
    else
        REL="${INPUT#"$INPUT_ROOT_WV"/}"
    fi

    # extract q-folder from input path
    INPUT_Q="$(echo "$REL" | cut -d'/' -f1)"
    while [[ "$REL" =~ ^q[^/]+/ ]]; do
        REL="${REL#*/}"
    done
    BASENAME_NOEXT="${REL%.*}"

    # static: use q-folder from input; dynamic: use quality from DB
    if [[ "$DYNAMIC" -eq 0 ]]; then
        QTAG="$INPUT_Q"
    fi

    BITRATE="$(get_bitrate "$QTAG")"
    OUTPUT_PATH="$OUTPUT_ROOT/$QTAG/$BASENAME_NOEXT.m4a"
    OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"

    # check for existing m4a under any quality folder
    EXISTING_FILE=""
    EXISTING_Q=""
    for q in qx q0 q1 q2 q3 q4 q5 q6 q7; do
        CANDIDATE="$OUTPUT_ROOT/$q/$BASENAME_NOEXT.m4a"
        if [[ -f "$CANDIDATE" ]]; then
            EXISTING_FILE="$CANDIDATE"
            EXISTING_Q="$q"
            break
        fi
    done

    # same quality and file exists — skip
    if [[ -n "$EXISTING_FILE" && "$EXISTING_Q" == "$QTAG" ]]; then
        ((count_skipped++)) || true
        continue
    fi

    # quality changed — remove old file
    if [[ -n "$EXISTING_FILE" && "$EXISTING_Q" != "$QTAG" ]]; then
        echo "[QUALITY CHANGED] $EXISTING_Q → $QTAG | $FILE"
        rm -f "$EXISTING_FILE"
        ((count_removed++)) || true
    fi

    echo "[CONVERT] ${QTAG} (${BITRATE}) | $FILE"
    mkdir -p "$OUTPUT_DIR"

    # encode to temp file first — moved to final path only on full success
    CURRENT_TMP="${OUTPUT_PATH}.tmp"

    ffmpeg -nostdin -y -hide_banner -loglevel error \
        -i "$INPUT" \
        -map 0:a \
        -map 0:v? \
        -c:a aac \
        -b:a "$BITRATE" \
        -c:v copy \
        -disposition:v attached_pic \
        -map_metadata 0 \
        -movflags +faststart \
        -f mp4 \
        "$CURRENT_TMP"

    # embed artwork via mutagen
    COVER_TMP="$(mktemp /tmp/cover_XXXXXX.jpg)"
    ffmpeg -nostdin -y -hide_banner -loglevel error \
        -i "$INPUT" -an -c:v mjpeg "$COVER_TMP" 2>/dev/null || true

    if [[ -s "$COVER_TMP" ]]; then
python3 <<PYEOF
from mutagen.mp4 import MP4, MP4Cover
with open(r"""$COVER_TMP""", "rb") as f:
    cover_data = f.read()
audio = MP4(r"""$CURRENT_TMP""")
audio["covr"] = [MP4Cover(cover_data, imageformat=MP4Cover.FORMAT_JPEG)]
audio.save()
PYEOF
    fi
    rm -f "$COVER_TMP"

    # atomic move: only place final file if everything succeeded
    mv "$CURRENT_TMP" "$OUTPUT_PATH"
    CURRENT_TMP=""

    ((count_converted++)) || true

done < <(
    { [[ -d "$INPUT_ROOT_FLAC" ]] && find "$INPUT_ROOT_FLAC" -type f -iname "*.flac" -print0; } 2>/dev/null
    { [[ -d "$INPUT_ROOT_WV"   ]] && find "$INPUT_ROOT_WV"   -type f -iname "*.wv"   -print0; } 2>/dev/null
)

log "Done. Converted: $count_converted | Skipped: $count_skipped | Removed old: $count_removed | No entry: $count_no_entry"
