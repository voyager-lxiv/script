#!/usr/bin/env bash
# sort_qx_map.sh - Sorts ./export/tag files into quality folders based on tracks_isrc.quality

set -euo pipefail

# SAFETY — must run inside .../Music
CURRENT_DIR="${PWD%/}"
[[ "$CURRENT_DIR" == */Music ]] || {
    echo "[ERROR] Run only inside Music directory"
    exit 1
}

# CONFIG
MUSIC_ROOT="$CURRENT_DIR"
INPUT_ROOT="$MUSIC_ROOT/export/tag"
DATABASE_FILE="$MUSIC_ROOT/playlist/music_metadata.db"
TABLE_NAME_2="tracks_isrc"
FILENAME_REGEX='\[[A-Za-z0-9]{12}\]'

command -v sqlite3 >/dev/null 2>&1 || {
    echo "[ERROR] sqlite3 not found"
    exit 1
}

usage() {
    echo "Usage: $0 --sort"
    exit 1
}

[[ $# -eq 0 ]] && usage

# SORT
if [[ "$1" == "--sort" ]]; then

    while IFS= read -r -d '' INPUT; do

        FILE=$(basename "$INPUT")

        # extract ISRC from filename
        [[ ! $FILE =~ $FILENAME_REGEX ]] && continue
        RAW=$(grep -oE "$FILENAME_REGEX" <<< "$FILE")
        ISRC="${RAW:1:12}"

        # lookup quality from tracks_isrc table
        QVALUE=$(sqlite3 -noheader "$DATABASE_FILE" \
            "SELECT quality FROM $TABLE_NAME_2 WHERE isrc='$ISRC' LIMIT 1;")
        [[ -z "$QVALUE" ]] && QVALUE="qx"

        # RELATIVE PATH FROM tag/
        REL="${INPUT#"$INPUT_ROOT"/}"

        # strip all leading q-folders
        while [[ "$REL" =~ ^q[^/]+/ ]]; do
            REL="${REL#*/}"
        done

        EXT="${REL%%/*}"
        REST="${REL#"$EXT"/}"

        # strip q-folders from REST too
        while [[ "$REST" =~ ^q[^/]+/ ]]; do
            REST="${REST#*/}"
        done

        DEST="$INPUT_ROOT/$EXT/$QVALUE/$REST"
        DEST_DIR=$(dirname "$DEST")

        # skip if already in correct location
        [[ "$INPUT" == "$DEST" ]] && continue

        # skip if destination already exists
        [[ -e "$DEST" ]] && continue

        SRC_REL="${INPUT#"$MUSIC_ROOT/"}"
        DST_REL="${DEST#"$MUSIC_ROOT/"}"
        OLD_Q=$(grep -oE '/q[^/]+' <<< "$SRC_REL" | head -n1 | tr -d '/' || true)

        printf '[%s → %s] %s\n' "${OLD_Q:-new}" "$QVALUE" "$DST_REL"

        mkdir -p "$DEST_DIR"
        mv -- "$INPUT" "$DEST"

        # remove empty source directories up to INPUT_ROOT
        SRC_DIR=$(dirname "$INPUT")
        while [[ "$SRC_DIR" != "$INPUT_ROOT" && "$SRC_DIR" != "$MUSIC_ROOT" ]]; do
            rmdir --ignore-fail-on-non-empty "$SRC_DIR" 2>/dev/null || break
            [[ -d "$SRC_DIR" ]] && break
            SRC_DIR=$(dirname "$SRC_DIR")
        done

    done < <(find "$INPUT_ROOT" -type f -print0)

    echo "[INFO] Sort complete."
    exit 0
fi

usage
