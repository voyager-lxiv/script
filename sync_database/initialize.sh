#!/usr/bin/env bash
# initialize.sh - Creates the SQLite music metadata database and tables.

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

DB_DIR="$(dirname "$DATABASE_FILE")"
if [[ ! -d "$DB_DIR" ]]; then
    log "Creating directory: $DB_DIR"
    mkdir -p "$DB_DIR"
fi

# CREATE TABLES
log "Initialising database: $DATABASE_FILE"

sqlite3 "$DATABASE_FILE" <<EOF
CREATE TABLE IF NOT EXISTS $TABLE_NAME_1 (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    year        TEXT,
    album       TEXT,
    track       TEXT,
    isrc        TEXT,
    title       TEXT,
    artist      TEXT,
    duration    REAL,
    genre       TEXT,
    bitrate     INTEGER,
    sample_rate INTEGER,
    filepath    TEXT UNIQUE,
    mtime       INTEGER,
    atime       INTEGER
);

CREATE TABLE IF NOT EXISTS $TABLE_NAME_2 (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    quality    TEXT DEFAULT 'qx',
    year       TEXT,
    album      TEXT,
    track      TEXT,
    isrc       TEXT UNIQUE,
    title      TEXT,
    artist     TEXT,
    audio_data TEXT DEFAULT 'not exist',
    flac       INTEGER DEFAULT 0,
    m4a        INTEGER DEFAULT 0,
    opus       INTEGER DEFAULT 0,
    ogg        INTEGER DEFAULT 0,
    wv         INTEGER DEFAULT 0
);
EOF

log "Tables created: $TABLE_NAME_1, $TABLE_NAME_2"

# VERIFY
log "Tables in database:"
sqlite3 "$DATABASE_FILE" "
    SELECT name FROM sqlite_master
    WHERE type='table' AND name NOT LIKE 'sqlite_%'
    ORDER BY name;
"

log "Done."
