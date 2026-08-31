# macOS Orphaned Application Files & Folders Cleanup Guide

This guide provides a script to safely identify and remove leftover configuration files, caches, and directories in your `$HOME` directory left behind by uninstalled applications or CLI tools.

---

## 1. Cleanup Script (`cleanup_old_app_dirs.sh`)

```zsh
#!/usr/bin/env zsh

set -euo pipefail

# List of known dotfiles/folders to check and their associated commands/apps
# Format: "directory_or_file_name:binary_or_app_name"
# If binary_or_app_name is not found via `which` or in /Applications, it is marked as leftover candidate.
CANDIDATE_MAP=(
  ".agents:agents"
  ".antigravity:antigravity"
  ".antigravity_cockpit:antigravity"
  ".aspnet:dotnet"
  ".azure:az"
  ".azurefunctions:func"
  ".bun:bun"
  ".cagent:cagent"
  ".cisco:Cisco AnyConnect Secure Mobility Client.app"
  ".claude:Claude.app"
  ".claude.json:Claude.app"
  ".clickshare:ClickShare.app"
  ".cline:cline"
  ".codex:codex"
  ".ollama:ollama"
  ".lmstudio:LM Studio.app"
)

echo "🔍 Scanning home directory (~/) for potential leftover folders..."
echo "---------------------------------------------------------------"

candidates=()

is_installed() {
  local target="$1"

  # Check standard CLI binary
  if command -v "$target" >/dev/null 2>&1; then
    return 0
  fi

  # Check Homebrew installed formulas/casks
  if command -v brew >/dev/null 2>&1; then
    if brew list --versions "$target" >/dev/null 2>&1; then
      return 0
    fi
  fi

  # Check macOS Applications folders
  if [[ -d "/Applications/$target" ]] || \
     [[ -d "/System/Applications/$target" ]] || \
     [[ -d "$HOME/Applications/$target" ]]; then
    return 0
  fi

  return 1
}

for item in "${CANDIDATE_MAP[@]}"; do
  folder_name="${item%%:*}"
  app_name="${item##*:}"
  target_path="$HOME/$folder_name"

  if [[ -e "$target_path" ]]; then
    if ! is_installed "$app_name"; then
      candidates+=("$folder_name")
    fi
  fi
done

if [[ ${#candidates[@]} -eq 0 ]]; then
  echo "✅ No orphaned application folders detected in ~/."
  exit 0
fi

echo "Identified potential leftover folders/files:"
echo ""
for c in "${candidates[@]}"; do
  size=$(du -sh "$HOME/$c" 2>/dev/null | awk '{print $1}')
  echo " • ~/$c (${size:-unknown size})"
done
echo "---------------------------------------------------------------"

echo -n "Do you want to review and delete these items? (y/N): "
read -r overall_confirm

if [[ ! "$overall_confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted. No files or folders were modified."
  exit 0
fi

echo ""
echo "Choose deletion mode:"
echo " 1) Move ALL identified items to Trash"
echo " 2) Ask for confirmation per item"
echo " 3) Cancel"
echo -n "Select [1-3]: "
read -r mode

case "$mode" in
  1)
    for c in "${candidates[@]}"; do
      target="$HOME/$c"
      if [[ -e "$target" ]]; then
        mv "$target" "$HOME/.Trash/"
        echo "🗑️  Moved ~/$c to ~/.Trash"
      fi
    done
    echo "Done! You can empty your Trash to permanently free up space."
    ;;
  2)
    for c in "${candidates[@]}"; do
      echo -n "Move ~/$c to Trash? (y/N): "
      read -r item_confirm
      if [[ "$item_confirm" =~ ^[Yy]$ ]]; then
        mv "$HOME/$c" "$HOME/.Trash/"
        echo "🗑️  Moved ~/$c to ~/.Trash"
      else
        echo "Skipped ~/$c"
      fi
    done
    echo "Done!"
    ;;
  *)
    echo "Operation cancelled."
    exit 0
    ;;
esac
```

---

## 2. Usage Instructions

1. **Make executable**:
   ```bash
   chmod +x cleanup_old_app_dirs.sh
   ```

2. **Run the script**:
   ```bash
   ./cleanup_old_app_dirs.sh
   ```

3. **Follow the interactive prompts**:
   - The script scans `$HOME` and checks whether the associated command or `.app` exists in `/Applications`, `/System/Applications`, `~/Applications`, `PATH`, or `brew`.
   - Displays all matching candidates and their disk usage.
   - Offers to move items safely to `~/.Trash/` (either in bulk or one by one).
