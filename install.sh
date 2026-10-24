#!/usr/bin/env bash
# Interactive installer: copies ./creel into a directory on your $PATH.
# Non-interactive (no TTY): installs to the first candidate without asking.
set -euo pipefail

cd "$(dirname "$0")"
[ -f creel ] || { echo "install.sh: ./creel not found; run from the checkout" >&2; exit 1; }

# Candidate destinations, in order: wherever creel is already installed,
# then the conventional user bin dirs, then any other writable $PATH entry.
candidates=()
add() {
    case " ${candidates[*]-} " in *" $1 "*) return ;; esac
    candidates+=("$1")
}

current="$(command -v creel 2>/dev/null || true)"
[ -n "$current" ] && add "$(dirname "$current")"

for d in "$HOME/.local/bin" "$HOME/bin"; do
    case ":$PATH:" in *":$d:"*) [ -d "$d" ] && add "$d" ;; esac
done

IFS=: read -ra path_dirs <<< "$PATH"
for d in "${path_dirs[@]}"; do
    [ -n "$d" ] && [ -d "$d" ] && [ -w "$d" ] && add "$d"
done

# Nothing usable found: fall back to ~/.local/bin (created on demand).
if [ "${#candidates[@]}" -eq 0 ]; then
    add "$HOME/.local/bin"
fi

dest=""
if [ -t 0 ]; then
    echo "Install creel to:"
    i=1
    for d in "${candidates[@]}"; do
        note=""
        [ -n "$current" ] && [ "$d" = "$(dirname "$current")" ] && note=" (replaces $current)"
        [ -d "$d" ] && [ ! -w "$d" ] && note="$note (needs sudo)"
        case ":$PATH:" in *":$d:"*) ;; *) note="$note (not on \$PATH)" ;; esac
        printf '  %d) %s%s\n' "$i" "$d" "$note"
        i=$((i + 1))
    done
    printf '  %d) other (type a path)\n' "$i"
    read -rp "choice [1]: " choice
    choice="${choice:-1}"
    case "$choice" in
        ''|*[!0-9]*) echo "install.sh: not a number: $choice" >&2; exit 1 ;;
    esac
    if [ "$choice" -eq "$i" ]; then
        read -rp "path: " dest
        [ -n "$dest" ] || { echo "install.sh: no path given" >&2; exit 1; }
        dest="${dest/#~\//$HOME/}"
        case ":$PATH:" in *":$dest:"*) ;; *)
            echo ">> note: $dest is not on your \$PATH; add it to your shell profile" ;;
        esac
    elif [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        dest="${candidates[$((choice - 1))]}"
    else
        echo "install.sh: no such option: $choice" >&2; exit 1
    fi
else
    dest="${candidates[0]}"
fi

mkdir -p "$dest" 2>/dev/null || true
if [ -w "$dest" ]; then
    install -m755 creel "$dest/creel"
else
    sudo install -m755 creel "$dest/creel"
fi
echo ">> installed $dest/creel"
echo ">> stateful containers created by an older creel keep its run settings;"
echo ">> run 'creel --fresh' in a project to recreate them."
