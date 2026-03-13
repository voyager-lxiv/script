#!/usr/bin/env bash
# stream_import.sh - Converts files from ./import/filter to WavPack in ./import/raw

set -euo pipefail

# SAFETY
[[ "$(basename "$PWD")" != "Music" ]] && {
    echo "[ERROR] Run from Music directory"
    exit 1
}

# CONFIG
INPUT_ROOT="./import/filter"
OUTPUT_ROOT="./import/raw"

# HELPERS
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; exit 1; }

usage() {
    echo "Usage: $0 [--hybrid] [--debug]"
    exit 1
}

# PARSE ARGS
HYBRID=0
DEBUG=0
for arg in "$@"; do
    case "$arg" in
        --hybrid) HYBRID=1 ;;
        --debug)  DEBUG=1 ;;
        --help|-h) usage ;;
        *) err "Unknown option: $arg" ;;
    esac
done

# PRE-FLIGHT
command -v ffmpeg  &>/dev/null || err "ffmpeg is not installed."
command -v wavpack &>/dev/null || err "wavpack CLI is not installed."
command -v ffprobe &>/dev/null || err "ffprobe is not installed."
command -v python3 &>/dev/null || err "python3 is not installed."
[[ -d "$INPUT_ROOT" ]] || err "Input directory not found: $INPUT_ROOT"

MODE="lossless"
[[ "$HYBRID" -eq 1 ]] && MODE="hybrid"
log "Starting import conversion (WavPack, $MODE)..."

count_converted=0
count_skipped=0

while IFS= read -r -d '' INPUT; do

    REL="${INPUT#"$INPUT_ROOT"/}"
    BASENAME_NOEXT="${REL%.*}"
    OUTPUT="$OUTPUT_ROOT/$BASENAME_NOEXT.wv"
    OUTPUT_DIR="$(dirname "$OUTPUT")"

    if [[ -f "$OUTPUT" ]]; then
        ((count_skipped++)) || true
        continue
    fi

    echo "[CONVERT] $REL"
    mkdir -p "$OUTPUT_DIR"

    # get all metadata in one ffprobe call
    json=$(ffprobe -v quiet -print_format json -show_format -show_streams "$INPUT")

    get_tag() {
        local key="${1^^}" keyl="${1,,}"
        echo "$json" | jq -r ".format.tags.$key // .format.tags.$keyl // .streams[0].tags.$key // .streams[0].tags.$keyl // empty"
    }

    title=$(get_tag title)
    artist=$(get_tag artist)
    album=$(get_tag album)
    year=$(get_tag date)
    track=$(get_tag track)
    tracktotal=$(get_tag tracktotal)
    disc=$(get_tag discnumber)
    disctotal=$(get_tag disctotal)
    genre=$(get_tag genre)
    composer=$(get_tag composer)
    comment=$(get_tag comment)
    albumartist=$(get_tag albumartist)
    isrc=$(get_tag isrc)
    label=$(get_tag label)
    copyright=$(get_tag copyright)
    lyrics=$(get_tag lyrics)

    # build wavpack args
    if [[ "$HYBRID" -eq 0 ]]; then
        WVPACK_ARGS=(-f -i)
    else
        WVPACK_ARGS=(-h -b256 -c -i)
    fi

    [[ -n "$title"       ]] && WVPACK_ARGS+=(-w "Title=$title")
    [[ -n "$artist"      ]] && WVPACK_ARGS+=(-w "Artist=$artist")
    [[ -n "$album"       ]] && WVPACK_ARGS+=(-w "Album=$album")
    [[ -n "$year"        ]] && WVPACK_ARGS+=(-w "Year=$year")
    [[ -n "$track"       ]] && WVPACK_ARGS+=(-w "Track=$track")
    [[ -n "$tracktotal"  ]] && WVPACK_ARGS+=(-w "Track Total=$tracktotal")
    [[ -n "$disc"        ]] && WVPACK_ARGS+=(-w "Disc=$disc")
    [[ -n "$disctotal"   ]] && WVPACK_ARGS+=(-w "Disc Total=$disctotal")
    [[ -n "$genre"       ]] && WVPACK_ARGS+=(-w "Genre=$genre")
    [[ -n "$composer"    ]] && WVPACK_ARGS+=(-w "Composer=$composer")
    [[ -n "$comment"     ]] && WVPACK_ARGS+=(-w "Comment=$comment")
    [[ -n "$albumartist" ]] && WVPACK_ARGS+=(-w "Album Artist=$albumartist")
    [[ -n "$isrc"        ]] && WVPACK_ARGS+=(-w "ISRC=$isrc")
    [[ -n "$label"       ]] && WVPACK_ARGS+=(-w "Label=$label")
    [[ -n "$copyright"   ]] && WVPACK_ARGS+=(-w "Copyright=$copyright")
    [[ -n "$lyrics"      ]] && WVPACK_ARGS+=(-w "Lyrics=$lyrics")

    # ffmpeg → pipe → wavpack
    if [[ "$HYBRID" -eq 0 ]]; then
        if [[ "$DEBUG" -eq 1 ]]; then
            ffmpeg -nostdin -hide_banner -loglevel error \
                -i "$INPUT" -map 0:a -f wav - | \
            wavpack "${WVPACK_ARGS[@]}" - -o "$OUTPUT"
        else
            ffmpeg -nostdin -hide_banner -loglevel error \
                -i "$INPUT" -map 0:a -f wav - | \
            wavpack "${WVPACK_ARGS[@]}" - -o "$OUTPUT" 2>/dev/null
        fi
    else
        WAV_TMP="$OUTPUT_DIR/.tmp_$(basename "$BASENAME_NOEXT").wav"
        ffmpeg -nostdin -y -hide_banner -loglevel error \
            -i "$INPUT" -map 0:a "$WAV_TMP"
        if [[ "$DEBUG" -eq 1 ]]; then
            wavpack "${WVPACK_ARGS[@]}" "$WAV_TMP" -o "$OUTPUT"
        else
            wavpack "${WVPACK_ARGS[@]}" "$WAV_TMP" -o "$OUTPUT" 2>/dev/null
        fi
        rm -f "$WAV_TMP"
    fi

    # embed cover art via mutagen
    has_video=$(echo "$json" | jq -r '[.streams[] | select(.codec_type=="video")] | length')
    if [[ "$has_video" -gt 0 ]]; then
        COVER_TMP="$OUTPUT_DIR/.cover_$(basename "$BASENAME_NOEXT").jpg"
        ffmpeg -nostdin -y -hide_banner -loglevel error \
            -i "$INPUT" -an -c:v mjpeg "$COVER_TMP" 2>/dev/null || true
        if [[ -s "$COVER_TMP" ]]; then
python3 << PYEOF
from mutagen.wavpack import WavPack
audio = WavPack("$OUTPUT")
if audio.tags is None:
    audio.tags = mutagen.apev2.APEv2()
with open("$COVER_TMP", "rb") as f:
    data = f.read()
from mutagen.apev2 import APEBinaryValue
audio["Cover Art (Front)"] = APEBinaryValue(b"Cover Art (Front)\x00" + data)
audio.save()
PYEOF
            rm -f "$COVER_TMP"
        fi
    fi

    ((count_converted++)) || true

    # delete source file after successful conversion
    rm -f "$INPUT"

done < <(find "$INPUT_ROOT" -type f \( \
    -iname "*.flac" -o \
    -iname "*.mp3"  -o \
    -iname "*.m4a"  -o \
    -iname "*.opus" -o \
    -iname "*.ogg"  -o \
    -iname "*.wav"  -o \
    -iname "*.aiff" \
\) -print0)

log "Done. Converted: $count_converted | Skipped: $count_skipped"
