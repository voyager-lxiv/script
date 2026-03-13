#!/usr/bin/env bash
# scan_filesystem.sh - Scans audio files and appends/updates metadata in the database.

set -euo pipefail

# CONFIG
DATABASE_FILE="playlist/music_metadata.db"
TABLE_NAME_1="tracks"
SCAN_DIR="${1:-.}"

# HELPERS
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; exit 1; }
esc() { printf '%s' "$1" | sed "s/'/''/g"; }

# PRE-FLIGHT
command -v sqlite3  &>/dev/null || err "sqlite3 is not installed."
command -v ffprobe  &>/dev/null || err "ffprobe is not installed."
command -v jq       &>/dev/null || err "jq is not installed."
[[ -f "$DATABASE_FILE" ]]       || err "Database not found: $DATABASE_FILE — run initialize.sh first."

# SCAN
log "Scanning audio files in: $SCAN_DIR"

count_new=0
count_updated=0
count_skipped=0

find "$SCAN_DIR" -type f \( \
    -iname "*.mp3" -o \
    -iname "*.flac" -o \
    -iname "*.m4a" -o \
    -iname "*.opus" -o \
    -iname "*.ogg" -o \
    -iname "*.wv" -o \
    -iname "*.wvc" \
\) | while read -r file; do

    # FILE TIMES
    mtime=$(stat -c %Y "$file")
    atime=$(stat -c %X "$file")

    # CHECK DB
    db_row=$(sqlite3 -noheader "$DATABASE_FILE" \
        "SELECT mtime, atime FROM $TABLE_NAME_1 WHERE filepath='$(esc "$file")';")

    if [[ -n "$db_row" ]]; then
        IFS='|' read -r db_mtime db_atime <<< "$db_row"
        if [[ "$mtime" == "$db_mtime" && "$atime" == "$db_atime" ]]; then
            continue
        fi
        status="updated"
    else
        db_mtime=""
        db_atime=""
        status="new"
    fi

    echo "[${status^^}] $file"

    # EXTRACT METADATA
    json=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file")

    raw_date=$(echo "$json" | jq -r '
        .format.tags.DATE // .format.tags.date // .format.tags.Year // .format.tags.year
        // .streams[0].tags.DATE // .streams[0].tags.date // .streams[0].tags.Year // .streams[0].tags.year
        // empty')
    year=$(echo "$raw_date" | grep -oE '^[0-9]{4}' || true)

    album=$(echo "$json" | jq -r '
        .format.tags.ALBUM // .format.tags.album // .format.tags.Album
        // .streams[0].tags.ALBUM // .streams[0].tags.album // .streams[0].tags.Album
        // empty')

    track=$(echo "$json" | jq -r '
        .format.tags.TRACK // .format.tags.track // .format.tags.Track
        // .format.tags.TRACKNUMBER
        // .streams[0].tags.TRACK // .streams[0].tags.track // .streams[0].tags.Track
        // empty')

    title=$(echo "$json" | jq -r '
        .format.tags.TITLE // .format.tags.title // .format.tags.Title
        // .streams[0].tags.TITLE // .streams[0].tags.title // .streams[0].tags.Title
        // empty')

    artist=$(echo "$json" | jq -r '
        .format.tags.ARTIST // .format.tags.artist // .format.tags.Artist
        // .streams[0].tags.ARTIST // .streams[0].tags.artist // .streams[0].tags.Artist
        // empty')

    genre=$(echo "$json" | jq -r '
        .format.tags.GENRE // .format.tags.genre // .format.tags.Genre
        // .streams[0].tags.GENRE // .streams[0].tags.genre // .streams[0].tags.Genre
        // empty')

    isrc=$(echo "$json" | jq -r '
        .format.tags.ISRC // .format.tags.isrc // .format.tags.Isrc
        // .streams[0].tags.ISRC // .streams[0].tags.isrc // .streams[0].tags.Isrc
        // empty')
    isrc="${isrc%%;*}"

    duration=$(echo "$json"   | jq -r '.format.duration // 0')
    bitrate=$(echo "$json"    | jq -r '
        .format.bit_rate // .streams[0].bit_rate
        // (if (.format.size and .format.duration)
            then ((.format.size|tonumber)*8 / (.format.duration|tonumber))
            else 0 end)')
    sample_rate=$(echo "$json" | jq -r '.streams[0].sample_rate // 0')

    # UPSERT
    sqlite3 "$DATABASE_FILE" <<EOF
INSERT INTO $TABLE_NAME_1
    (isrc, year, album, track, title, artist, genre,
     bitrate, sample_rate, duration, filepath, mtime, atime)
VALUES (
    '$(esc "$isrc")',
    '$(esc "$year")',
    '$(esc "$album")',
    '$(esc "$track")',
    '$(esc "$title")',
    '$(esc "$artist")',
    '$(esc "$genre")',
    ${bitrate:-0},
    ${sample_rate:-0},
    ${duration:-0},
    '$(esc "$file")',
    $mtime,
    $atime
)
ON CONFLICT(filepath) DO UPDATE SET
    isrc        = excluded.isrc,
    year        = excluded.year,
    album       = excluded.album,
    track       = excluded.track,
    title       = excluded.title,
    artist      = excluded.artist,
    genre       = excluded.genre,
    bitrate     = excluded.bitrate,
    sample_rate = excluded.sample_rate,
    duration    = excluded.duration,
    mtime       = excluded.mtime,
    atime       = excluded.atime
WHERE
    mtime != excluded.mtime OR
    atime != excluded.atime;
EOF

done

log "Scan complete."
log "Total tracks in database: $(sqlite3 "$DATABASE_FILE" "SELECT COUNT(*) FROM $TABLE_NAME_1;")"
