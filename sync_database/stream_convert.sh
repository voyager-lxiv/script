#!/usr/bin/env bash
# stream_convert.sh - Converts flac files to opus based on quality from tracks_isrc table.

set -euo pipefail

# SAFETY
[[ "$(basename "$PWD")" != "Music" ]] && {
    echo "[ERROR] Run from Music directory"
    exit 1
}

# CONFIG
MUSIC_ROOT="$PWD"
INPUT_ROOT_FLAC="./export/tag/flac"
INPUT_ROOT_WV="./export/tag/wv"
OUTPUT_ROOT="./export/tag/opus"
DATABASE_FILE="./playlist/music_metadata.db"
TABLE_NAME_2="tracks_isrc"
ISRC_REGEX='\[([A-Za-z0-9]{12})\]'

# HELPERS
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; exit 1; }

# PRE-FLIGHT
command -v sqlite3  &>/dev/null || err "sqlite3 is not installed."
command -v ffmpeg   &>/dev/null || err "ffmpeg is not installed."
command -v python3  &>/dev/null || err "python3 is not installed."
[[ -f "$DATABASE_FILE" ]]       || err "Database not found: $DATABASE_FILE"

# QUALITY → BITRATE
get_bitrate() {
    case "$1" in
        q1) echo "320k" ;;
        q2) echo "256k" ;;
        q3) echo "192k" ;;
        q4) echo "160k"  ;;
        q5) echo "128k"  ;;
        q6) echo "96k"  ;;
        q7) echo "64k"  ;;
        *)  echo "64k"  ;;
    esac
}

usage() {
    echo "Usage: $0 [--lowpass] [--debug]"
    exit 1
}

# PARSE ARGS
LOWPASS=0
DEBUG=0
for arg in "$@"; do
    case "$arg" in
        --lowpass) LOWPASS=1 ;;
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
    total_wv=$(find "$INPUT_ROOT_WV"   -type f -iname "*.wv"   2>/dev/null | wc -l)
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

    # get quality from tracks_isrc
    QTAG=$(sqlite3 -noheader "$DATABASE_FILE" \
        "SELECT quality FROM $TABLE_NAME_2 WHERE isrc='$ISRC' LIMIT 1;")

    if [[ -z "$QTAG" ]]; then
        [[ "$DEBUG" -eq 1 ]] && echo "[NO ENTRY] $ISRC | $FILE"
        ((count_no_entry++)) || true
        continue
    fi

    BITRATE="$(get_bitrate "$QTAG")"

    # relative path from input root, strip any leading q-folder
    if [[ "$INPUT" == "$INPUT_ROOT_FLAC"* ]]; then
        REL="${INPUT#"$INPUT_ROOT_FLAC"/}"
    else
        REL="${INPUT#"$INPUT_ROOT_WV"/}"
    fi
    while [[ "$REL" =~ ^q[^/]+/ ]]; do
        REL="${REL#*/}"
    done
    BASENAME_NOEXT="${REL%.*}"
    OUTPUT_PATH="$OUTPUT_ROOT/$QTAG/$BASENAME_NOEXT.opus"
    OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"

    # check for existing opus under any quality folder
    EXISTING_FILE=""
    EXISTING_Q=""
    for q in qx q0 q1 q2 q3 q4 q5 q6 q7; do
        CANDIDATE="$OUTPUT_ROOT/$q/$BASENAME_NOEXT.opus"
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

    LOWPASS_TAG=""
    [[ "$LOWPASS" -eq 1 ]] && LOWPASS_TAG=" +lowpass"
    echo "[CONVERT] $QTAG$LOWPASS_TAG | $FILE"

    mkdir -p "$OUTPUT_DIR"

    # encode opus
    LOWPASS_FILTER=()
    [[ "$LOWPASS" -eq 1 ]] && LOWPASS_FILTER=(-af "lowpass=f=16000,aresample=resampler=soxr")

    ffmpeg -nostdin -y -hide_banner -loglevel error \
        -i "$INPUT" \
        "${LOWPASS_FILTER[@]}" \
        -map 0:a \
        -c:a libopus \
        -b:a "$BITRATE" \
        -vbr on \
        -compression_level 10 \
        -application audio \
        -frame_duration 20 \
        -map_metadata 0 \
        "$OUTPUT_PATH"

    # embed artwork
    COVER="$OUTPUT_DIR/$(basename "$BASENAME_NOEXT").jpg"

    ffmpeg -nostdin -y -hide_banner -loglevel error \
        -i "$INPUT" -an -c:v mjpeg "$COVER" 2>/dev/null || true

    if [[ -s "$COVER" ]]; then
python3 <<EOF
from mutagen.oggopus import OggOpus
from mutagen.flac import Picture
import base64

audio = OggOpus(r"""$OUTPUT_PATH""")
pic = Picture()
with open(r"""$COVER""", "rb") as f:
    pic.data = f.read()
pic.type = 3
pic.mime = "image/jpeg"
pic.desc = "Cover"
audio["METADATA_BLOCK_PICTURE"] = [
    base64.b64encode(pic.write()).decode("ascii")
]
audio.save()
EOF
        rm -f "$COVER"
    fi

    ((count_converted++)) || true

done < <(
    { [[ -d "$INPUT_ROOT_FLAC" ]] && find "$INPUT_ROOT_FLAC" -type f -iname "*.flac" -print0; } 2>/dev/null
    { [[ -d "$INPUT_ROOT_WV"   ]] && find "$INPUT_ROOT_WV"   -type f -iname "*.wv"   -print0; } 2>/dev/null
)

log "Done. Converted: $count_converted | Skipped: $count_skipped | Removed old: $count_removed | No entry: $count_no_entry"
