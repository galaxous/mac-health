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
mac-health health
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
mac-health health              # RAM, disk, heavy paths
mac-health purge               # sudo purge (temporary relief)
mac-health caches list         # show cache sizes
mac-health caches spotify      # clean one cache target
mac-health caches all          # safe batch (skips running apps)
mac-health docker status       # Docker disk usage
mac-health docker soft         # light prune
mac-health docker prune        # full prune (images + volumes)
mac-health docker quit         # quit Docker Desktop
mac-health login list          # LaunchAgents / login items
mac-health maintenance monthly # guided monthly route
mac-health paths               # print central MH_* paths
mac-health version             # version + install root
mac-health uninstall           # remove install + PATH block
```

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
```

Each command group lives in its own file under `commands/` and is sourced by the main `mac-health` script.

## Notes

- Destructive steps ask for confirmation unless you pass `-y`.
- Cache cleans for Spotify, Chrome, and Cursor refuse to run while that app is open.
- `docker prune` removes unused images **and** volumes — back up important volumes first.
- `purge` only reclaims inactive pages; it is not a long-term fix.
- Re-running the installer replaces `~/.mac-health` and refreshes the `~/bin` symlink.
- Uninstall is idempotent; it only removes the `# mac-health PATH` block install wrote (not other `PATH` exports).

## Requirements

- macOS
- zsh (default on modern macOS)
- curl, tar
- Optional: Docker CLI, Homebrew, npm, Composer (for related cleanups)
