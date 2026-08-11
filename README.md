# mac-health

Small **zsh** toolkit for macOS hygiene: check memory/disk pressure, clean caches safely, and prune Docker when your Mac starts feeling slow.

## Why

On a 16 GB Mac, Docker, Chrome, IDEs, and app caches often pile up. `mac-health` groups those cleanups into simple commands with confirmations and “quit the app first” guards.

## Install

```bash
cd /path/to/mac-health
./install.zsh
```

This symlinks the CLI to `~/bin/mac-health`. Ensure `~/bin` is on your `PATH`:

```bash
export PATH="$HOME/bin:$PATH"
```

Or run directly:

```bash
./mac-health help
```

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
```

Global flag:

```bash
mac-health -y caches npm       # skip confirmation prompts
```

## Layout

```
mac-health/           # CLI entry
install.zsh           # symlink into ~/bin
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

## Requirements

- macOS
- zsh (default on modern macOS)
- Optional: Docker CLI, Homebrew, npm, Composer (for related cleanups)
