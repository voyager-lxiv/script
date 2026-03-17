#!/usr/bin/env bash
# sync_database_isrc.sh - Syncs ISRC table from tracks and updates audio_data status.

set -euo pipefail

# CONFIG
DATABASE_FILE="playlist/music_metadata.db"
TABLE_NAME_1="tracks"
TABLE_NAME_2="tracks_isrc"

# HELPERS
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; exit 1; }

# PRE-FLIGHT
command -v sqlite3 &>/dev/null || err "sqlite3 is not installed."
[[ -f "$DATABASE_FILE" ]]       || err "Database not found: $DATABASE_FILE — run initialize.sh first."

# SYNC NEW ISRC ENTRIES
log "Syncing ISRC table from tracks..."

sqlite3 "$DATABASE_FILE" <<EOF
INSERT INTO $TABLE_NAME_2 (isrc, year, album, track, title, artist)
SELECT
    isrc,
    year,
    album,
    track,
    title,
    artist
FROM $TABLE_NAME_1
WHERE isrc IS NOT NULL
  AND isrc != ''
ON CONFLICT(isrc) DO NOTHING;
EOF

# UPDATE CHANGED FIELDS ONLY
log "Updating changed fields in ISRC table..."

sqlite3 "$DATABASE_FILE" <<EOF
UPDATE $TABLE_NAME_2
SET
    year   = (SELECT t.year   FROM $TABLE_NAME_1 t WHERE t.isrc = $TABLE_NAME_2.isrc LIMIT 1),
    album  = (SELECT t.album  FROM $TABLE_NAME_1 t WHERE t.isrc = $TABLE_NAME_2.isrc LIMIT 1),
    track  = (SELECT t.track  FROM $TABLE_NAME_1 t WHERE t.isrc = $TABLE_NAME_2.isrc LIMIT 1),
    title  = (SELECT t.title  FROM $TABLE_NAME_1 t WHERE t.isrc = $TABLE_NAME_2.isrc LIMIT 1),
    artist = (SELECT t.artist FROM $TABLE_NAME_1 t WHERE t.isrc = $TABLE_NAME_2.isrc LIMIT 1)
WHERE EXISTS (
    SELECT 1 FROM $TABLE_NAME_1 t
    WHERE t.isrc = $TABLE_NAME_2.isrc
      AND (
          t.year   != $TABLE_NAME_2.year   OR
          t.album  != $TABLE_NAME_2.album  OR
          t.track  != $TABLE_NAME_2.track  OR
          t.title  != $TABLE_NAME_2.title  OR
          t.artist != $TABLE_NAME_2.artist
      )
);
EOF

# UPDATE AUDIO_DATA STATUS
# case 1: filepath starts with ./export, ./import, OR has both ./trash and another path -> exist
# case 2: filepath is ONLY ./trash -> trash
# case 3: no filepath found -> not exist
log "Updating audio_data status..."

sqlite3 "$DATABASE_FILE" <<EOF
-- case 1: exist — any non-trash filepath found (./export, ./import, or any other path)
UPDATE $TABLE_NAME_2
SET audio_data = 'exist'
WHERE EXISTS (
    SELECT 1 FROM $TABLE_NAME_1 t
    WHERE t.isrc = $TABLE_NAME_2.isrc
      AND t.filepath NOT LIKE './trash/%'
);

-- case 2: trash — filepath found but ALL of them are under ./trash
UPDATE $TABLE_NAME_2
SET audio_data = 'trash'
WHERE EXISTS (
    SELECT 1 FROM $TABLE_NAME_1 t
    WHERE t.isrc = $TABLE_NAME_2.isrc
      AND t.filepath LIKE './trash/%'
  )
  AND NOT EXISTS (
    SELECT 1 FROM $TABLE_NAME_1 t
    WHERE t.isrc = $TABLE_NAME_2.isrc
      AND t.filepath NOT LIKE './trash/%'
  );

-- case 3: not exist — no filepath found in tracks at all
UPDATE $TABLE_NAME_2
SET audio_data = 'not exist'
WHERE NOT EXISTS (
    SELECT 1 FROM $TABLE_NAME_1 t
    WHERE t.isrc = $TABLE_NAME_2.isrc
);
EOF

# UPDATE FORMAT FIELDS (flac, m4a, opus, ogg)
# mark 1 if a non-trash filepath with that extension exists for this ISRC
log "Updating format fields..."

sqlite3 "$DATABASE_FILE" <<EOF
UPDATE $TABLE_NAME_2
SET
    flac = CASE WHEN EXISTS (
        SELECT 1 FROM $TABLE_NAME_1 t
        WHERE t.isrc = $TABLE_NAME_2.isrc
          AND t.filepath LIKE '%.flac'
          AND t.filepath NOT LIKE './trash/%'
    ) THEN 1 ELSE 0 END,

    m4a = CASE WHEN EXISTS (
        SELECT 1 FROM $TABLE_NAME_1 t
        WHERE t.isrc = $TABLE_NAME_2.isrc
          AND t.filepath LIKE '%.m4a'
          AND t.filepath NOT LIKE './trash/%'
    ) THEN 1 ELSE 0 END,

    opus = CASE WHEN EXISTS (
        SELECT 1 FROM $TABLE_NAME_1 t
        WHERE t.isrc = $TABLE_NAME_2.isrc
          AND t.filepath LIKE '%.opus'
          AND t.filepath NOT LIKE './trash/%'
    ) THEN 1 ELSE 0 END,

    ogg = CASE WHEN EXISTS (
        SELECT 1 FROM $TABLE_NAME_1 t
        WHERE t.isrc = $TABLE_NAME_2.isrc
          AND t.filepath LIKE '%.ogg'
          AND t.filepath NOT LIKE './trash/%'
    ) THEN 1 ELSE 0 END,

    wv = CASE WHEN EXISTS (
        SELECT 1 FROM $TABLE_NAME_1 t
        WHERE t.isrc = $TABLE_NAME_2.isrc
          AND t.filepath LIKE '%.wv'
          AND t.filepath NOT LIKE './trash/%'
    ) THEN 1 ELSE 0 END;
EOF


total=$(sqlite3 -noheader "$DATABASE_FILE" "SELECT COUNT(*) FROM $TABLE_NAME_2;")
exist=$(sqlite3 -noheader "$DATABASE_FILE" "SELECT COUNT(*) FROM $TABLE_NAME_2 WHERE audio_data = 'exist';")
trash=$(sqlite3 -noheader "$DATABASE_FILE" "SELECT COUNT(*) FROM $TABLE_NAME_2 WHERE audio_data = 'trash';")
not_exist=$(sqlite3 -noheader "$DATABASE_FILE" "SELECT COUNT(*) FROM $TABLE_NAME_2 WHERE audio_data = 'not exist';")

log "Done. Total: $total | Exist: $exist | Trash: $trash | Not exist: $not_exist"
