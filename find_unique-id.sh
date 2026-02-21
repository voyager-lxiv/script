#!/bin/bash

# Multithreaded unique ID finder
# Group-wise interactive delete

# find_unique-id --exclude -d dir -f file --delete
# find_unique-id --delete

DIR="."
EXCLUDE_DIRS=()
EXCLUDE_EXTS=()
JOBS=$(nproc)
DELETE_MODE=false

# -------- argument parsing --------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --delete)
            DELETE_MODE=true
            shift
            ;;
        --exclude)
            shift
            while [[ "$1" == -* ]]; do
                case "$1" in
                    -d) EXCLUDE_DIRS+=("$2"); shift 2 ;;
                    -f) EXCLUDE_EXTS+=("$2"); shift 2 ;;
                    *) break ;;
                esac
            done
            ;;
        --jobs)
            JOBS="$2"
            shift 2
            ;;
        *)
            DIR="$1"
            shift
            ;;
    esac
done

[[ ! -d "$DIR" ]] && { echo "Directory not found."; exit 1; }

TMP=$(mktemp)

# -------- worker --------
process_file() {
    file="$1"

    filename=$(basename "$file")
    directory=$(dirname "$file")

    number=$(echo "$filename" | grep -oE '^[0-9]+\.[[:space:]]*')
    id=$(echo "$filename" | grep -oE '\[[^]]+\]' | head -n1)
    [[ -z "$id" ]] && exit 0

    clean_name=$(echo "$filename" | sed -E 's/\[[^]]+\][[:space:]]*//g')
    clean_name=$(echo "$clean_name" | sed -E 's/^[0-9]+\.[[:space:]]*//')

    size=$(du -h "$file" | cut -f1)

    echo "${id}|${number}${id} ${clean_name} ${size} ${directory}|${file}"
}

export -f process_file

# -------- build find --------
FIND_ARGS=("$DIR")

for d in "${EXCLUDE_DIRS[@]}"; do
    FIND_ARGS+=(-type d -iname "$d" -prune -o)
done

FIND_ARGS+=(-type f)

for e in "${EXCLUDE_EXTS[@]}"; do
    FIND_ARGS+=(! -iname "*.${e}")
done

FIND_ARGS+=(-print0)

find "${FIND_ARGS[@]}" |
xargs -0 -n1 -P "$JOBS" bash -c 'process_file "$0"' |
sort > "$TMP"

# -------- group processor --------
process_group() {

    local grp="$1"
    local files=()
    local displays=()

    while IFS='|' read -r display filepath; do
        [[ -z "$display" ]] && continue
        displays+=("$display")
        files+=("$filepath")
    done <<< "$grp"

    (( ${#files[@]} <= 1 )) && return

    while true; do

        echo
        echo "Duplicate ID group:"
        echo "-------------------"

        for i in "${!files[@]}"; do
            printf "%d. %s\n" "$((i+1))" "${displays[$i]}"
        done

        $DELETE_MODE || break

        echo
        read -r -p "[1-${#files[@]} delete | a=delete all | s=skip | q=quit]: " ans < /dev/tty

        # ---- FIX 1: trim spaces ----
        ans="$(echo "$ans" | xargs)"

        # ---- FIX 2: ignore empty ENTER ----
        [[ -z "$ans" ]] && continue

        case "$ans" in
            q)
                rm -f "$TMP"
                exit 0
                ;;
            s)
                break
                ;;
            a)
                echo "Deleting all files in group..."
                for f in "${files[@]}"; do
                    command rm -f -- "$f"
                done
                break
                ;;
            *)
                if [[ "$ans" =~ ^[0-9]+$ ]] &&
                   (( ans>=1 && ans<=${#files[@]} )); then

                    idx=$((ans-1))
                    target="${files[$idx]}"

                    echo
                    echo "Deleting:"
                    echo "$target"

                    command rm -f -- "$target"

                    unset 'files[idx]'
                    unset 'displays[idx]'

                    # compact arrays safely
                    files=("${files[@]}")
                    displays=("${displays[@]}")

                    # auto exit group if only one left
                    (( ${#files[@]} <= 1 )) && break
                else
                    echo "Invalid option."
                fi
                ;;
        esac
    done
}


# -------- iterate groups --------
prev_id=""
group=""

while IFS='|' read -r current_id display filepath; do

    line="${display}|${filepath}"

    if [[ "$current_id" == "$prev_id" || -z "$prev_id" ]]; then
        group+="$line"$'\n'
    else
        process_group "$group"
        group="$line"$'\n'
    fi

    prev_id="$current_id"

done < "$TMP"

process_group "$group"

rm -f "$TMP"
