#!/usr/bin/env bash
# stream_convert_m4a.sh - Converts flac files to M4A/AAC.
# Input:  ./export/tag/flac
# Output: ./export/tag/m4a
# Default: qx/256k; --dynamic: quality per-track from tracks_isrc table

set -euo pipefail

# SAFETY
[[ "$(basename "$PWD")" != "Music" ]] && {
    echo "[ERROR] Run from Music directory"
    exit 1
}

# CONFIG
INPUT_ROOT="./export/tag/flac"
OUTPUT_ROOT="./export/tag/m4a"
DATABASE_FILE="./playlist/music_metadata.db"
TABLE_ISRC="tracks_isrc"
ISRC_REGEX='\[([A-Za-z0-9]+)\]'

# HELPERS
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; exit 1; }

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
        qx) echo "256k" ;;
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

# PRE-FLIGHT
command -v sqlite3 &>/dev/null || err "sqlite3 is not installed."
command -v ffmpeg  &>/dev/null || err "ffmpeg is not installed."
command -v python3 &>/dev/null || err "python3 is not installed."
[[ -d "$INPUT_ROOT" ]] || err "Input directory not found: $INPUT_ROOT"
if [[ "$DYNAMIC" -eq 1 ]]; then
    [[ -f "$DATABASE_FILE" ]] || err "Database not found: $DATABASE_FILE"
fi

if [[ "$DYNAMIC" -eq 1 ]]; then
    log "Mode: dynamic (quality from DB)"
else
    log "Mode: static (qx / 256k)"
fi

count_converted=0
count_skipped=0
count_removed=0
count_no_entry=0

while IFS= read -r -d '' INPUT; do

    FILE="$(basename "$INPUT")"

    # strip input root, then strip leading q-folder
    REL="${INPUT#"$INPUT_ROOT"/}"
    REL="${REL#*/}"
    BASENAME_NOEXT="${REL%.*}"

    # determine quality
    if [[ "$DYNAMIC" -eq 1 ]]; then
        if [[ "$FILE" =~ $ISRC_REGEX ]]; then
            ISRC="${BASH_REMATCH[1]}"
        else
            [[ "$DEBUG" -eq 1 ]] && echo "[SKIP] no ISRC in filename: $FILE"
            ((count_no_entry++)) || true
            continue
        fi

        QTAG=$(sqlite3 -noheader "$DATABASE_FILE" \
            "PRAGMA busy_timeout=5000;" \
            "SELECT quality FROM $TABLE_ISRC WHERE isrc='$ISRC' LIMIT 1;")

        if [[ -z "$QTAG" ]]; then
            [[ "$DEBUG" -eq 1 ]] && echo "[NO ENTRY] $ISRC | $FILE"
            ((count_no_entry++)) || true
            continue
        fi
    else
        QTAG="qx"
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
        [[ "$DEBUG" -eq 1 ]] && echo "[SKIP] $FILE"
        ((count_skipped++)) || true
        continue
    fi

    # quality changed — remove old file
    if [[ -n "$EXISTING_FILE" && "$EXISTING_Q" != "$QTAG" ]]; then
        echo "[QUALITY CHANGED] $EXISTING_Q → $QTAG | $FILE"
        rm -f "$EXISTING_FILE"
        ((count_removed++)) || true
    fi

    echo "[CONVERT] $QTAG ($BITRATE) | $FILE"
    mkdir -p "$OUTPUT_DIR"

    # encode M4A
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
        "$OUTPUT_PATH"

    # embed artwork via mutagen
    COVER_TMP="$(mktemp /tmp/cover_XXXXXX.jpg)"
    ffmpeg -nostdin -y -hide_banner -loglevel error \
        -i "$INPUT" -an -c:v mjpeg "$COVER_TMP" 2>/dev/null || true

    if [[ -s "$COVER_TMP" ]]; then
        python3 << PYEOF
from mutagen.mp4 import MP4, MP4Cover
with open(r"""$COVER_TMP""", "rb") as f:
    cover_data = f.read()
audio = MP4(r"""$OUTPUT_PATH""")
audio["covr"] = [MP4Cover(cover_data, imageformat=MP4Cover.FORMAT_JPEG)]
audio.save()
PYEOF
    fi
    rm -f "$COVER_TMP"

    ((count_converted++)) || true

done < <(find "$INPUT_ROOT" -type f -iname "*.flac" -print0 2>/dev/null)

log "Done. Converted: $count_converted | Skipped: $count_skipped | Removed old: $count_removed | No entry: $count_no_entry"
