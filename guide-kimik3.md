# macOS App Leftover Cleanup Script

A script that finds orphaned app-data folders in a user's home directory. It builds an inventory of installed apps from `/Applications` and Homebrew, scans the hidden (dot-)folders of `/Users/<username>`, flags folders that match no installed app as orphaned, and asks before deleting anything. Items go to the Trash by default so the action is recoverable.

## Script: `cleanup-app-vkimi.sh`

See [cleanup-app-vkimi.sh](cleanup-app-vkimi.sh) in this folder — the guide and the script are kept in sync. Key implementation points:

- `collect_installed` gathers app names from `/Applications` and `~/Applications` (`.app` bundles) plus `brew list --formula` and `brew list --cask`.
- Names are normalized to lowercase alphanumerics and split into word tokens, so `.azure` matches brew package `azure-cli` and `.claude` matches `Claude.app`.
- `folder_installed` checks each hidden folder in `/Users/<username>` against that inventory (exact name, then token match, then the ALIASES map).
- Only folders with status `orphaned` are offered for deletion, one by one.

## Usage

```bash
chmod +x cleanup-app-vkimi.sh
./cleanup-app-vkimi.sh <username> --dry-run   # preview only
./cleanup-app-vkimi.sh <username>             # scan, then confirm per folder
```

Example output:

```
Installed apps detected: 214 unique names/tokens
Scanning hidden folders in /Users/franciscosusana ...

FOLDER                             SIZE     STATUS
---------------------------------- -------- ---------
.agents                            12M      orphaned
.azure                             44M      installed
.claude                            1.2G     installed
.clickshare                        89M      orphaned
```

## Notes

- Detection is fully dynamic — no hardcoded folder catalog. Installed names come from app bundles in `/Applications` and `~/Applications`, plus `brew list --formula` and `brew list --cask`.
- Matching is token-based and case-insensitive: folder tokens are compared against app/brew name tokens.
- Names that do not textually match their app are handled by a small ALIASES map (e.g. `aspnet` -> `dotnet`, `cline` -> VS Code). Extend it in the script when you hit false positives.
- Apps installed outside Homebrew and `/Applications` (e.g. .NET SDK via pkg installer) cannot be detected, so their folders may appear orphaned — verify before confirming.
- Shared/system folders (`.config`, `.cache`, `.ssh`, ...) are on a PROTECTED list: shown in the report but never offered for deletion.
- Only hidden dot-folders are scanned — the typical location of app leftovers.
- Default answer to each prompt is **No** (press Enter to skip); `a` accepts all remaining, `q` quits.
- Deletion goes to the **Trash** via Finder (recoverable); `--rm` makes it permanent. The first Trash run may trigger a macOS prompt asking permission for your terminal to control Finder.
