#!/usr/bin/env bash
#
# cleanup-app-vkimi.sh
#
# Finds orphaned app-data folders in a user's home directory:
#   1. Builds an inventory of installed apps from /Applications,
#      ~/Applications and Homebrew (formulas + casks).
#   2. Scans the hidden (dot-)folders of /Users/<username>.
#   3. A folder is "orphaned" when its name matches no installed app.
#      Orphaned folders are listed first; you then confirm each deletion.
# Deletions go to the Trash by default (recoverable).

set -uo pipefail

DRY_RUN=0
USE_TRASH=1

usage() {
  cat <<'EOF'
Usage: cleanup-app-vkimi.sh <username> [--dry-run] [--rm] [--help]

  <username>  macOS user whose home folder (/Users/<username>) is scanned
  --dry-run   scan and list only, never delete
  --rm        permanently delete (rm -rf) instead of moving to Trash
  --help      show this help
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "")        usage; exit 1 ;;
esac

USERNAME="$1"; shift
TARGET_HOME="/Users/$USERNAME"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --rm)      USE_TRASH=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage; exit 1 ;;
  esac
done

if [ ! -d "$TARGET_HOME" ]; then
  echo "Error: home directory $TARGET_HOME does not exist." >&2
  exit 1
fi

# --------------------------------------------------------------------------
# Folders that are listed but never offered for deletion.
# --------------------------------------------------------------------------
PROTECTED=" .Trash .ssh .gnupg .config .cache .local .zsh_sessions .bash_sessions .CFUserTextEncoding .oh-my-zsh .cups "

# --------------------------------------------------------------------------
# Aliases for folders whose name does not textually match the app or brew
# package that owns them. Format: foldername|token token ...
# Extend this list when you hit false "orphaned" results.
# --------------------------------------------------------------------------
ALIASES=$(cat <<'EOF'
aspnet|dotnet
azurefunctions|azure
cline|visualstudiocode
vscode|visualstudiocode
EOF
)

is_protected() {
  case "$PROTECTED" in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

alias_tokens() {
  while IFS='|' read -r key extra; do
    if [ "$key" = "$1" ]; then printf '%s' "$extra"; return; fi
  done <<< "$ALIASES"
}

# ------------------- build inventory of installed apps ---------------------

INSTALLED_SET=$(mktemp -t appcleanup)
trap 'rm -f "$INSTALLED_SET"' EXIT

add_installed() {
  local raw token old_ifs
  raw=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  # full name with separators stripped ("Visual Studio Code" -> "visualstudiocode")
  token=${raw//[^a-z0-9]/}
  [ -n "$token" ] && printf '%s\n' "$token" >> "$INSTALLED_SET"
  # individual words ("Visual Studio Code" -> visual, studio, code)
  old_ifs=$IFS
  IFS='-_. /'
  for token in $raw; do
    token=${token//[^a-z0-9]/}
    [ "${#token}" -ge 3 ] && printf '%s\n' "$token" >> "$INSTALLED_SET"
  done
  IFS=$old_ifs
}

collect_installed() {
  local dir app name pkg
  for dir in /Applications "$TARGET_HOME/Applications"; do
    [ -d "$dir" ] || continue
    for app in "$dir"/*.app; do
      [ -e "$app" ] || continue
      name=$(basename "$app" .app)
      add_installed "$name"
    done
  done
  if command -v brew >/dev/null 2>&1; then
    while IFS= read -r pkg; do
      [ -n "$pkg" ] && add_installed "$pkg"
    done < <(brew list --formula 2>/dev/null; brew list --cask 2>/dev/null)
  fi
  sort -u -o "$INSTALLED_SET" "$INSTALLED_SET"
}

# ------------------------------- matching ----------------------------------

folder_installed() {
  local base compact token old_ifs
  base=${1#.}
  base=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')

  compact=${base//[^a-z0-9]/}
  if [ -n "$compact" ] && grep -qx "$compact" "$INSTALLED_SET"; then
    return 0
  fi

  old_ifs=$IFS
  IFS='-_.'
  for token in $base $(alias_tokens "$compact"); do
    token=${token//[^a-z0-9]/}
    [ "${#token}" -ge 3 ] || continue
    if grep -qx "$token" "$INSTALLED_SET"; then
      IFS=$old_ifs
      return 0
    fi
  done
  IFS=$old_ifs
  return 1
}

trash_path() {
  local path="$1" esc
  esc=${path//\\/\\\\}
  esc=${esc//\"/\\\"}
  osascript -e "tell application \"Finder\" to delete (POSIX file \"$esc\")" >/dev/null 2>&1
}

# ------------------------------- scan --------------------------------------

collect_installed
installed_count=$(wc -l < "$INSTALLED_SET" | tr -d ' ')

echo
echo "Installed apps detected: $installed_count unique names/tokens"
echo "Scanning hidden folders in $TARGET_HOME ..."

names=(); sizes=(); statuses=()

shopt -s nullglob
for path in "$TARGET_HOME"/.*; do
  name=$(basename "$path")
  case "$name" in .|..) continue ;; esac
  { [ -d "$path" ] || [ -L "$path" ]; } || continue

  if is_protected "$name"; then
    status="protected"
  elif folder_installed "$name"; then
    status="installed"
  else
    status="orphaned"
  fi

  size=$(du -sh "$path" 2>/dev/null | cut -f1)
  names+=("$name"); sizes+=("${size:-?}"); statuses+=("$status")
done

if [ "${#names[@]}" -eq 0 ]; then
  echo "No hidden folders found in $TARGET_HOME."
  exit 0
fi

echo
echo "Scan results for $TARGET_HOME"
printf "%-34s %-8s %s\n" "FOLDER" "SIZE" "STATUS"
printf "%-34s %-8s %s\n" "----------------------------------" "--------" "---------"
for i in "${!names[@]}"; do
  printf "%-34s %-8s %s\n" "${names[$i]}" "${sizes[$i]}" "${statuses[$i]}"
done
echo
echo "orphaned  = matches no installed app in /Applications or Homebrew"
echo "protected = system/shared folder, never offered for deletion"
echo

# ------------------------------ delete -------------------------------------

candidates=()
for i in "${!names[@]}"; do
  [ "${statuses[$i]}" = "orphaned" ] && candidates+=("$i")
done

if [ "${#candidates[@]}" -eq 0 ]; then
  echo "Nothing to clean up — every folder matches an installed app."
  exit 0
fi

echo "Found ${#candidates[@]} orphaned folder(s)."

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run: no changes made."
  exit 0
fi

if [ "$USE_TRASH" -eq 1 ]; then
  echo "Deletion mode: move to Trash (recoverable). Use --rm for permanent deletion."
else
  echo "Deletion mode: PERMANENT (rm -rf)."
fi
echo "Caution: apps installed outside /Applications and Homebrew (e.g. pkg installers)"
echo "cannot be detected — verify a folder's contents before confirming."
echo

removed=0; skipped=0; remove_all=0

for i in "${candidates[@]}"; do
  folder="${names[$i]}"
  path="$TARGET_HOME/$folder"

  if [ "$remove_all" -eq 0 ]; then
    printf "Delete %s (%s)? [y]es/[N]o/[a]ll/[q]uit " "$path" "${sizes[$i]}"
    if ! read -r reply; then echo; echo "Aborted."; break; fi
    case "$reply" in
      y|Y|yes|YES)   ;;
      a|A|all|ALL)   remove_all=1 ;;
      q|Q|quit|QUIT) echo "Stopped by user."; break ;;
      *)             echo "  skipped."; skipped=$((skipped+1)); continue ;;
    esac
  fi

  if [ "$USE_TRASH" -eq 1 ]; then
    if trash_path "$path"; then
      echo "  moved to Trash: $path"; removed=$((removed+1))
    else
      echo "  ERROR: could not move $path to Trash" >&2; skipped=$((skipped+1))
    fi
  else
    if rm -rf -- "$path"; then
      echo "  deleted: $path"; removed=$((removed+1))
    else
      echo "  ERROR: failed to delete $path" >&2; skipped=$((skipped+1))
    fi
  fi
done

echo
echo "Done. Removed: $removed, skipped: $skipped."
