#!/usr/bin/env bash
# mp3.sh - Converts wv files to MP3, preserving folder structure.
# Input:  Music/export/tag/wv
# Output: Music/export/tag/mp3 (same structure)

set -euo pipefail

# SAFETY
[[ "$(basename "$PWD")" != "Music" ]] && {
    echo "[ERROR] Run from Music directory"
    exit 1
}

# CONFIG
INPUT_ROOT="./export/tag/wv"
OUTPUT_ROOT="./export/tag/mp3"
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
command -v ffmpeg  &>/dev/null || err "ffmpeg is not installed."
command -v python3 &>/dev/null || err "python3 is not installed."

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
        qx) echo "320k" ;;
    esac
}

usage() {
    echo "Usage: $0 [-q q1|q2|q3|q4|q5|q6|q7|qx] [--debug]"
    echo ""
    echo "  -q QUALITY  Set bitrate quality (default: qx / 320k)"
    echo "  --debug     Show extra output"
    exit 0
}

# PARSE ARGS
QTAG="qx"
DEBUG=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -q)
            shift
            [[ -z "${1:-}" ]] && err "-q requires a value (q1-q7, qx)"
            QTAG="$1"
            ;;
        --debug)   DEBUG=1 ;;
        --help|-h) usage ;;
        *) err "Unknown option: $1" ;;
    esac
    shift
done

# validate quality
get_bitrate "$QTAG" > /dev/null 2>&1 || err "Invalid quality: $QTAG (use q1-q7 or qx)"
BITRATE="$(get_bitrate "$QTAG")"

[[ -d "$INPUT_ROOT" ]] || err "Input directory not found: $INPUT_ROOT"

log "Quality: $QTAG ($BITRATE)"

# CONVERT
count_converted=0
count_skipped=0

while IFS= read -r -d '' INPUT; do

    FILE="$(basename "$INPUT")"

    # skip .wvc correction files
    [[ "$FILE" == *.wvc ]] && continue

    # preserve full folder structure from input root
    REL="${INPUT#"$INPUT_ROOT"/}"
    BASENAME_NOEXT="${REL%.*}"
    OUTPUT_PATH="$OUTPUT_ROOT/$BASENAME_NOEXT.mp3"
    OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"

    if [[ -f "$OUTPUT_PATH" ]]; then
        [[ "$DEBUG" -eq 1 ]] && echo "[SKIP] $FILE"
        ((count_skipped++)) || true
        continue
    fi

    echo "[CONVERT] $QTAG ($BITRATE) | $FILE"
    mkdir -p "$OUTPUT_DIR"

    CURRENT_TMP="${OUTPUT_PATH}.tmp"

    ffmpeg -nostdin -y -hide_banner -loglevel error \
        -i "$INPUT" \
        -map 0:a \
        -c:a libmp3lame \
        -b:a "$BITRATE" \
        -map_metadata 0 \
        -id3v2_version 3 \
        -f mp3 \
        "$CURRENT_TMP"

    # embed artwork via mutagen
    COVER_TMP="$(mktemp /tmp/cover_XXXXXX.jpg)"
    ffmpeg -nostdin -y -hide_banner -loglevel error \
        -i "$INPUT" -an -c:v mjpeg "$COVER_TMP" 2>/dev/null || true

    if [[ -s "$COVER_TMP" ]]; then
        python3 <<PYEOF
from mutagen.mp3 import MP3
from mutagen.id3 import ID3, APIC, error
audio = MP3(r"""$CURRENT_TMP""", ID3=ID3)
try:
    audio.add_tags()
except error:
    pass
with open(r"""$COVER_TMP""", "rb") as f:
    cover_data = f.read()
audio.tags.add(APIC(
    encoding=3,
    mime="image/jpeg",
    type=3,
    desc="Cover",
    data=cover_data
))
audio.save()
PYEOF
    fi
    rm -f "$COVER_TMP"

    mv "$CURRENT_TMP" "$OUTPUT_PATH"
    CURRENT_TMP=""

    ((count_converted++)) || true

done < <(find "$INPUT_ROOT" -type f -iname "*.wv" -print0 2>/dev/null)

log "Done. Converted: $count_converted | Skipped: $count_skipped"
