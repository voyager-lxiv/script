#!/usr/bin/env bash
# sync_playlist.sh - Generates M3U8 playlist files from tracks_isrc table.
set -euo pipefail

# SAFETY
[[ "$(basename "$PWD")" != "Music" ]] && {
    echo "[ERROR] Run from Music directory"
    exit 1
}

# CONFIG
DATABASE_FILE="./playlist/music_metadata.db"
OUTPUT_DIR="./playlist/m3u"
TABLE_ISRC="tracks_isrc"
TABLE_TRACKS="tracks"

# HELPERS
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; exit 1; }

# PRE-FLIGHT
command -v sqlite3 &>/dev/null || err "sqlite3 is not installed."
[[ -f "$DATABASE_FILE" ]] || err "Database not found: $DATABASE_FILE"

mkdir -p "$OUTPUT_DIR"

# ── STEP 1: detect duplicate ISRCs across playlists ──────────────────────────
mapfile -t DUPES < <(sqlite3 -noheader "$DATABASE_FILE" "
    SELECT isrc, GROUP_CONCAT(playlist, ', '), COUNT(*) AS cnt
    FROM $TABLE_ISRC
    WHERE playlist IS NOT NULL AND playlist != ''
    GROUP BY isrc
    HAVING cnt > 1
    ORDER BY cnt DESC;
" 2>/dev/null || true)
if [[ "${#DUPES[@]}" -gt 0 ]]; then
    log "Duplicate ISRCs found across playlists:"
    for DUPE in "${DUPES[@]}"; do
        IFS='|' read -r isrc playlists count <<< "$DUPE"
        log "  [DUPLICATE] ISRC=$isrc in $count playlists: $playlists"
    done
fi

# ── STEP 2: build entry for a single ISRC ────────────────────────────────────
build_entry() {
    local isrc="$1" title="$2" artist="$3"
    local isrc_esc
    isrc_esc=$(printf '%s' "$isrc" | sed "s/'/''/g")

    local row
    row=$(sqlite3 -noheader "$DATABASE_FILE" "
        SELECT
            CAST(ROUND(COALESCE(t.duration, 0) * 1000) AS INTEGER),
            t.filepath
        FROM $TABLE_TRACKS t
        WHERE t.isrc = '$isrc_esc'
          AND t.filepath LIKE './export/%'
          AND t.filepath NOT LIKE './trash/%'
          AND t.filepath NOT LIKE '%.wvc'
        ORDER BY
            CASE
                WHEN t.filepath LIKE '%.opus' THEN 1
                WHEN t.filepath LIKE '%.m4a'  THEN 2
                WHEN t.filepath LIKE '%.mp3'  THEN 3
                WHEN t.filepath LIKE '%.ogg'  THEN 4
                WHEN t.filepath LIKE '%.flac' THEN 5
                WHEN t.filepath LIKE '%.wv'   THEN 6
                ELSE 7
            END
        LIMIT 1;
    ")
    [[ -z "$row" ]] && return

    local duration filepath
    IFS='|' read -r duration filepath <<< "$row"
    [[ -z "$filepath" ]] && return

    local display="$artist - $title"
    [[ -z "$artist" ]] && display="$title"
    local rel_path="./../..${filepath#.}"

    printf '#EXTINF:%s,%s\n%s\n' "$duration" "$display" "$rel_path"
}

# ── STEP 3: remove ISRC entry from any .m3u8 file ────────────────────────────
remove_from_file() {
    local file="$1" isrc="$2"
    [[ ! -f "$file" ]] && return
    local tmp_file="${file}.tmp"
    # keep header lines, then filter out any line containing [ISRC]
    # also remove the #EXTINF line immediately before it (paired lines)
    python3 - "$file" "$isrc" "$tmp_file" << 'PYEOF'
import sys

src, isrc, dst = sys.argv[1], sys.argv[2], sys.argv[3]
pattern = f"[{isrc}]"

with open(src, "r", encoding="utf-8") as f:
    lines = f.readlines()

out = []
skip_next = False
for i, line in enumerate(lines):
    stripped = line.rstrip()
    if skip_next:
        skip_next = False
        continue
    if pattern in stripped:
        # remove previous #EXTINF line if it was just added
        if out and out[-1].startswith("#EXTINF"):
            out.pop()
        skip_next = False
        continue
    if stripped.startswith("#EXTINF"):
        # peek ahead: if next non-empty line contains pattern, skip this too
        for j in range(i + 1, len(lines)):
            nxt = lines[j].rstrip()
            if nxt == "":
                continue
            if pattern in nxt:
                skip_next = True
                break
            break
        if skip_next:
            continue
    out.append(line)

with open(dst, "w", encoding="utf-8") as f:
    f.writelines(out)
PYEOF
    mv "$tmp_file" "$file"
}

# ── STEP 4: scan ALL existing .m3u8 files for moved ISRCs ────────────────────
mapfile -t ALL_M3U < <(find "$OUTPUT_DIR" -maxdepth 1 -name "*.m3u8" -type f 2>/dev/null | sort)

for M3U in "${ALL_M3U[@]}"; do
    FILE_PLAYLIST="$(basename "$M3U" .m3u8)"

    # collect all ISRCs to remove from this file first
    declare -a TO_REMOVE=()
    while IFS= read -r line; do
        if [[ "$line" =~ \[([^]]+)\] ]]; then
            found_isrc="${BASH_REMATCH[1]}"
            current_pl=$(sqlite3 -noheader "$DATABASE_FILE" \
                "SELECT LOWER(playlist) FROM $TABLE_ISRC WHERE isrc='$found_isrc' LIMIT 1;" 2>/dev/null || true)
            if [[ -n "$current_pl" && "${current_pl,,}" != "$FILE_PLAYLIST" ]]; then
                log "[MOVE] ISRC=$found_isrc: $FILE_PLAYLIST → $current_pl"
                TO_REMOVE+=("$found_isrc")
            fi
        fi
    done < "$M3U"

    # now apply all removals after reading is complete
    for isrc in "${TO_REMOVE[@]+"${TO_REMOVE[@]}"}"; do
        remove_from_file "$M3U" "$isrc"
    done
    unset TO_REMOVE
done

# ── STEP 5: get all playlists from DB ────────────────────────────────────────
mapfile -t DB_PLAYLISTS < <(sqlite3 -noheader "$DATABASE_FILE" \
    "SELECT DISTINCT LOWER(playlist) FROM $TABLE_ISRC WHERE playlist IS NOT NULL AND playlist != '' ORDER BY 1;")

log "Found ${#DB_PLAYLISTS[@]} playlist(s): ${DB_PLAYLISTS[*]}"
count_created=0
count_updated=0

# ── STEP 6: generate each playlist file ──────────────────────────────────────
for PLAYLIST in "${DB_PLAYLISTS[@]}"; do
    PLAYLIST_LOWER="${PLAYLIST,,}"
    M3U_FILE="$OUTPUT_DIR/$PLAYLIST_LOWER.m3u8"
    IS_NEW=0
    [[ ! -f "$M3U_FILE" ]] && IS_NEW=1

    mapfile -t ROWS < <(sqlite3 -noheader "$DATABASE_FILE" "
        SELECT ti.isrc, ti.title, ti.artist
        FROM $TABLE_ISRC ti
        WHERE LOWER(ti.playlist) = '$(printf '%s' "$PLAYLIST_LOWER" | sed "s/'/''/g")'
        ORDER BY ti.artist, ti.year, ti.album, ti.track;
    ")

    {
        echo "#EXTM3U"
        echo "#EXTENC:UTF-8"
        echo "#PLAYLIST:$PLAYLIST_LOWER"
        echo ""
        for ROW in "${ROWS[@]}"; do
            IFS='|' read -r isrc title artist <<< "$ROW"
            entry=$(build_entry "$isrc" "$title" "$artist")
            [[ -n "$entry" ]] && echo "$entry" && echo ""
        done
    } > "$M3U_FILE"

    if [[ "$IS_NEW" -eq 1 ]]; then
        log "[CREATED] $M3U_FILE"
        ((count_created++)) || true
    else
        log "[UPDATED] $M3U_FILE"
        ((count_updated++)) || true
    fi
done

log "Done. Created: $count_created | Updated: $count_updated"
