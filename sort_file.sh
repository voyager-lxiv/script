#!/bin/bash

BASE_DIR="$(pwd)"
RECURSIVE=0

# Show help message
show_help() {
    echo "usage: sort_file [-r] [-h]"
    echo
    echo "options:"
    echo "  -r    recursive search"
    echo "  -h    show this help"
}

# Parse parameters
while getopts ":rh" opt; do
    case "$opt" in
        r) RECURSIVE=1 ;;
        h)
            show_help
            exit 0
            ;;
        \?)
            show_help
            exit 1
            ;;
    esac
done

# Enable nullglob
shopt -s nullglob

# Select find mode
if [[ "$RECURSIVE" -eq 1 ]]; then
    FIND_CMD=(find . -type f -print0)
else
    FIND_CMD=(find . -maxdepth 1 -type f -print0)
fi

# Find files
"${FIND_CMD[@]}" | while IFS= read -r -d '' file; do

    # Skip files already inside extension folders
    [[ "$RECURSIVE" -eq 1 ]] && \
    [[ "$file" == ./*/* ]] && \
    [[ "$(dirname "$file")" == "./${file##*.}" ]] && continue

    # Get filename only
    name="$(basename "$file")"

    # Determine extension
    if [[ "$name" == *.* ]]; then
        ext="${name##*.}"
    else
        ext="no_extension"
    fi

    # Create extension directory at top level
    mkdir -p "$BASE_DIR/$ext"

    # Move file (avoid overwrite)
    if [[ ! -e "$BASE_DIR/$ext/$name" ]]; then
        mv -- "$file" "$BASE_DIR/$ext/"
    else
        echo "Skipped (exists): $name"
    fi

done
