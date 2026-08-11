# mac-health

Small **zsh** toolkit for macOS hygiene: check memory/disk pressure, clean caches safely, and prune Docker when your Mac starts feeling slow.

## Install (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/galaxous/mac-health/main/install.sh | bash
```

This downloads the toolkit into `~/.mac-health`, symlinks `~/bin/mac-health`, and appends `~/bin` to your `PATH` in `~/.zshrc` if needed.

Then:

```bash
source ~/.zshrc   # if PATH was just added
mac-health help
mac-health                 # same as: mac-health health
mac-health version
```

Pin a tag/branch:

```bash
curl -fsSL https://raw.githubusercontent.com/galaxous/mac-health/main/install.sh | REF=v0.1.0-alpha bash
# or
curl -fsSL https://raw.githubusercontent.com/galaxous/mac-health/main/install.sh | REF=main bash
```

### From a local clone

```bash
make install
make uninstall
```

`make help` lists targets. Equivalent scripts remain available:

```bash
./install.sh --local
# or
./install.zsh
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/galaxous/mac-health/main/uninstall.sh | bash
```

Removes `~/bin/mac-health`, `~/.mac-health`, and the `# mac-health PATH` block from `~/.zshrc` if present. Safe to re-run.

From a clone (preferred) or an installed copy:

```bash
make uninstall
# or
./uninstall.sh
# or
./uninstall.zsh
# or
mac-health uninstall   # also: mac-health remove
```

Custom prefix (same env as install):

```bash
curl -fsSL https://raw.githubusercontent.com/galaxous/mac-health/main/uninstall.sh | PREFIX=~/.mac-health bash
```

## Why

On a 16 GB Mac, Docker, Chrome, IDEs, and app caches often pile up. `mac-health` groups those cleanups into simple commands with confirmations and “quit the app first” guards.

## Usage

```bash
mac-health                     # default: health check (RAM, disk, heavy paths)
mac-health health              # same
mac-health purge               # sudo purge (temporary relief)
mac-health caches list         # sizes + IDE breakdown
mac-health caches code         # VS Code safe caches (quit Code)
mac-health caches code-deep    # + workspaceStorage + History
mac-health caches cursor       # Cursor Cache + CachedData
mac-health caches cursor-deep  # + Cursor workspaceStorage + History
mac-health caches chrome-sw    # Chrome Service Worker
mac-health caches spotify
mac-health caches all          # safe batch only (no *-deep)
mac-health docker status       # Docker disk usage
mac-health docker soft         # light prune
mac-health docker prune        # full prune (images + volumes)
mac-health docker quit         # quit Docker Desktop
mac-health login list          # LaunchAgents / login items
mac-health maintenance monthly # guided monthly route
mac-health projects <root> …   # scan/purge vendor + node_modules (see below)
mac-health paths               # print central MH_* paths
mac-health version             # version + install root
mac-health uninstall           # remove install + PATH block
```

### Projects deps (`vendor` / `node_modules`)

`<root>` is **required** (no default). Default mode is dry-run. A `vendor` / `node_modules` match is kept only when its **parent** has a matching package-manager manifest (`composer.json`/`composer.lock`/`composer-dev.*` for Composer; `package.json`/`package-lock.json` for npm).

```bash
mac-health projects ~/Desktop/Projects.nosync composer
mac-health projects ~/Desktop/Projects.nosync npm
mac-health projects ~/Desktop/Projects.nosync all
mac-health projects ~/Desktop/Projects.nosync all --maxDepth 3
mac-health projects ~/Desktop/Projects.nosync all --exclude 'b2press-cms|modularous'
mac-health projects  ~/Desktop/Projects.nosync npm --exclude '^press-(app|cms)(/|$)'
mac-health projects ~/Desktop/Projects.nosync npm --include 'heydaytr|jakomeet' --apply
mac-health -y projects ~/Desktop/Projects.nosync all --apply
```

| Arg / flag                 | Meaning                                                                                                    |
| -------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `<root>`                   | Directory to scan (e.g. `~/Desktop/Projects.nosync`)                                                       |
| `composer` / `npm` / `all` | `vendor` / `node_modules` (manifest-gated), or both                                                        |
| `--maxDepth <n>`           | Nesting under root (default **1** = `root/<project>/vendor\|node_modules` only; raise for nested packages) |
| `--apply`                  | Delete matches (asks to confirm)                                                                           |
| `--no-interaction`         | Same as `-y`: no confirm on `--apply`                                                                      |
| `--exclude <regex>`        | Skip relative paths matching (repeatable)                                                                  |
| `--include <regex>`        | If set, keep only matching relative paths                                                                  |

Global flag:

```bash
mac-health -y caches npm       # skip confirmation prompts
```

## Layout

```
Makefile              # local clone: make install / uninstall / help
install.sh            # remote/local system installer
install.zsh           # thin wrapper → install.sh --local
uninstall.sh          # remote/local uninstaller
uninstall.zsh         # thin wrapper → uninstall.sh
mac-health            # CLI entry
VERSION               # semver / alpha label
lib/
  paths.zsh           # central paths (MH_*)
  common.zsh          # helpers
commands/
  health.zsh
  purge.zsh
  caches.zsh
  docker.zsh
  login.zsh
  maintenance.zsh
  projects.zsh        # vendor / node_modules scan + purge
```

Each command group lives in its own file under `commands/` and is sourced by the main `mac-health` script.

## Notes

- Destructive steps ask for confirmation unless you pass `-y`.
- Cache cleans for Spotify, Chrome, Cursor, and VS Code refuse to run while that app is open.
- `caches code` / `caches cursor` never delete settings.json; `*-deep` only clears workspaceStorage + History.
- `caches list` “all-caches” is a size summary only — not a delete target.
- `docker prune` removes unused images **and** volumes — back up important volumes first.
- `purge` only reclaims inactive pages; it is not a long-term fix.
- Re-running the installer replaces `~/.mac-health` and refreshes the `~/bin` symlink.
- Uninstall is idempotent; it only removes the `# mac-health PATH` block install wrote (not other `PATH` exports).
- `projects` never defaults a scan root — pass it explicitly. It refuses `/` and `$HOME`. Dry-run unless `--apply`. Default `--maxDepth 1` only hits `root/<project>/vendor|node_modules`.

## Requirements

- macOS
- zsh (default on modern macOS)
- curl, tar
- Optional: Docker CLI, Homebrew, npm, Composer (for related cleanups)
