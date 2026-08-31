# macOS Old App Data Cleanup

This conservative `zsh` script scans top-level hidden folders in your home directory, checks whether matching apps or commands still exist, shows candidates first, and moves confirmed folders to the macOS Trash rather than permanently deleting them.

```zsh
#!/bin/zsh

set -u
setopt NULL_GLOB

STALE_DAYS="${STALE_DAYS:-60}"

typeset -a CANDIDATES=()
typeset -a MANUAL_REVIEW=()
typeset -a BREW_ITEMS=()
typeset -a APPLICATION_BUNDLES=()
typeset -a EXTENSIONS=()

typeset -A APP_HINTS=(
    .antigravity           "antigravity"
    .antigravity_cockpit   "antigravitycockpit|antigravity"
    .azurefunctions        "azurefunctions|func"
    .cagent                 "cagent"
    .cisco                  "cisco|webex"
    .clickshare             "clickshare|barco"
    .claude                 "claude"
    .cline                  "cline|claudedev|saoudrizwan"
    .codex                  "codex"
)

typeset -A PROTECTED=(
    .Trash 1
    .ssh 1
    .gnupg 1
    .aws 1
    .azure 1
    .config 1
    .cache 1
    .local 1
    .npm 1
    .yarn 1
    .pnpm-store 1
    .docker 1
    .kube 1
    .git 1
    .bun 1
    .cargo 1
    .rustup 1
    .nvm 1
    .pyenv 1
    .asdf 1
    .mise 1
    .gradle 1
    .m2 1
    .aspnet 1
    .vscode 1
    .cursor 1
)

normalise() {
    printf '%s' "$1" |
        tr '[:upper:]' '[:lower:]' |
        tr -cd '[:alnum:]'
}

folder_age_days() {
    local folder_path="$1"
    local modified_epoch
    local current_epoch

    modified_epoch="$(stat -f '%m' "$folder_path" 2>/dev/null)" || return 1
    current_epoch="$(date +%s)"

    printf '%s\n' "$(( (current_epoch - modified_epoch) / 86400 ))"
}

folder_modified_date() {
    stat -f '%Sm' -t '%Y-%m-%d' "$1" 2>/dev/null
}

folder_size() {
    du -sh "$1" 2>/dev/null | awk 'NR == 1 { print $1 }'
}

if command -v brew >/dev/null 2>&1; then
    BREW_ITEMS=("${(@f)$(brew list --formula 2>/dev/null)}")
    BREW_ITEMS+=("${(@f)$(brew list --cask 2>/dev/null)}")
fi

for application_root in \
    /Applications \
    "$HOME/Applications" \
    /System/Applications
do
    [[ -d "$application_root" ]] || continue

    for application_bundle in "$application_root"/*.app(N); do
        APPLICATION_BUNDLES+=("$application_bundle")
    done
done

for extension_root in \
    "$HOME/.vscode/extensions" \
    "$HOME/.vscode-insiders/extensions" \
    "$HOME/.cursor/extensions"
do
    [[ -d "$extension_root" ]] || continue

    for extension_path in "$extension_root"/*(/N); do
        EXTENSIONS+=("$extension_path")
    done
done

installed_match() {
    local aliases="$1"
    local alias_token
    local needle
    local brew_item
    local normalized_brew_item
    local application_bundle
    local normalized_application
    local extension_path
    local normalized_extension

    for alias_token in "${(@s:|:)aliases}"; do
        [[ -n "$alias_token" ]] || continue

        needle="$(normalise "$alias_token")"
        [[ -n "$needle" ]] || continue

        if [[ "$alias_token" != *[[:space:]]* ]] &&
            command -v "$alias_token" >/dev/null 2>&1
        then
            return 0
        fi

        for brew_item in "${BREW_ITEMS[@]}"; do
            normalized_brew_item="$(normalise "$brew_item")"
            [[ -n "$normalized_brew_item" ]] || continue

            if [[ "$normalized_brew_item" == *"$needle"* ]] ||
                [[ "$needle" == *"$normalized_brew_item"* ]]
            then
                return 0
            fi
        done

        for application_bundle in "${APPLICATION_BUNDLES[@]}"; do
            normalized_application="$(normalise "${application_bundle:t}")"

            if [[ "$normalized_application" == *"$needle"* ]] ||
                [[ "$needle" == *"$normalized_application"* ]]
            then
                return 0
            fi
        done

        for extension_path in "${EXTENSIONS[@]}"; do
            normalized_extension="$(normalise "${extension_path:t}")"

            if [[ "$normalized_extension" == *"$needle"* ]] ||
                [[ "$needle" == *"$normalized_extension"* ]]
            then
                return 0
            fi
        done
    done

    return 1
}

integer inspected=0
integer age_days
local folder_name
local folder_aliases

for folder_path in "$HOME"/.[!.]*(/N); do
    [[ -d "$folder_path" && ! -L "$folder_path" ]] || continue

    (( inspected++ ))
    folder_name="${folder_path:t}"

    [[ -n "${PROTECTED[$folder_name]-}" ]] && continue

    age_days="$(folder_age_days "$folder_path")" || continue
    (( age_days >= STALE_DAYS )) || continue

    folder_aliases="${APP_HINTS[$folder_name]-}"

    if [[ -z "$folder_aliases" ]]; then
        MANUAL_REVIEW+=("$folder_path")
        continue
    fi

    if installed_match "$folder_aliases"; then
        continue
    fi

    CANDIDATES+=("$folder_path")
done

printf '\nScanned %d hidden directories in %s.\n\n' "$inspected" "$HOME"

if (( ${#CANDIDATES[@]} == 0 )); then
    printf 'No mapped old-app folders met the checks.\n'
else
    printf 'Candidates older than %d days with no matching app, command, Homebrew item, or VS Code extension:\n' "$STALE_DAYS"

    for folder_path in "${CANDIDATES[@]}"; do
        folder_name="${folder_path:t}"
        printf '  %-30s %8s  modified %s\n' \
            "~/$folder_name" \
            "$(folder_size "$folder_path")" \
            "$(folder_modified_date "$folder_path")"
    done
fi

if (( ${#MANUAL_REVIEW[@]} > 0 )); then
    printf '\nOlder unrecognized folders, shown for manual review only:\n'

    for folder_path in "${MANUAL_REVIEW[@]}"; do
        folder_name="${folder_path:t}"
        printf '  %-30s %8s  modified %s\n' \
            "~/$folder_name" \
            "$(folder_size "$folder_path")" \
            "$(folder_modified_date "$folder_path")"
    done
fi

(( ${#CANDIDATES[@]} > 0 )) || exit 0

printf '\nMoving a folder to Trash can remove settings, caches, or login data.\n'
printf 'Nothing will be permanently deleted by this script.\n\n'

confirmation=""
read "confirmation?Type MOVE to move every candidate above to the macOS Trash: "

if [[ "$confirmation" != "MOVE" ]]; then
    printf 'Nothing moved.\n'
    exit 0
fi

for folder_path in "${CANDIDATES[@]}"; do
    if osascript - "$folder_path" <<'APPLESCRIPT'
on run argv
    tell application "Finder"
        delete POSIX file (item 1 of argv)
    end tell
end run
APPLESCRIPT
    then
        printf 'Moved to Trash: %s\n' "$folder_path"
    else
        printf 'Could not move: %s\n' "$folder_path"
    fi
done
```

## Usage

Make the script executable and run it:

```sh
chmod +x review-old-app-data.zsh
./review-old-app-data.zsh
```

The default age threshold is 60 days. To inspect everything in the app mapping regardless of age, run:

```sh
STALE_DAYS=0 ./review-old-app-data.zsh
```

The `.azure`, `.cache`, `.bun`, `.aspnet`, `.ssh`, and similar folders are deliberately excluded or limited to manual review because they may contain credentials, shared runtime data, or development state.
