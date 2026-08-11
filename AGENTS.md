# AGENTS.md — conventions for mac-health

Guidance for humans and coding agents working on this repo.

## CLI shape

```text
mac-health [-y|--yes] [--json] <command> [args...]
mac-health <command> [--json] [-y|--yes] [args...]
```

- Bare `mac-health` runs **`health`** (not help).
- Help: `mac-health help` / `-h` / `--help`.
- Global flags may appear **before or after** the command name.
- `--no-interaction` is accepted as an alias of `-y` when it appears after the command (same as `projects --no-interaction`).

## `--json` mode

When `MH_JSON=1` (via `--json`):

| Concern | Rule |
|--------|------|
| **Stdout** | Exactly one JSON document (pretty-printed, UTF-8). No banners, tables, or progress lines. |
| **Stderr** | Warnings (`[warn] …`) and errors. Do not mix JSON onto stderr. |
| **Human UI** | `mh_log` / `mh_ok` / `mh_section` are no-ops. |
| **Prompts** | Interactive confirm is disabled. Destructive actions **must** pass `-y` / `--yes` / `--no-interaction`, or the command fails. |
| **Envelope** | Every document includes `"command": "<name>"`. Subcommands also include `"action"` when applicable. |

### Commands that emit structured JSON

| Command | Notes |
|---------|--------|
| `version` | `{version, root}` |
| `paths` | `{paths: {MH_*: …}}` |
| `health` | hardware, os, memory, disk (`primary` = Data volume), heavy_paths, launch_agents |
| `analyze` | advice snapshot: memory, disk, trash, families, notable_bloat, `actions` (max 3) |
| `memory` | vm, processes, families, hints (`--top N` still applies) |
| `watch` | **No JSON** — TTY in-place memory refresh (`--interval` / `--top`; alt screen, no full clear flash) |
| `disk` / `disk status` | primary Data volume + `~/Library` buckets |
| `disk bloat` | known fat paths + hints (inspect only) |
| `trash status` | `{path, bytes, human}` |
| `trash empty` | `{ok, …}` (requires `-y` when confirm would prompt) |
| `caches list` | caches / vscode / cursor size inventories |
| `caches <target>` | mutator result `{action, ok}` (requires `-y` when confirm would prompt) |
| `projects` | dry-run inventory or apply summary |
| `docker status` | path sizes, system df, volume inventory |
| `docker volumes` | volume list only; never deletes |
| `docker prune` / `prune images` | `{action:"prune", target:"images", dry_run}`; only unused images |
| `docker quit` | `{action, ok, …}` |
| `login list\|checkpoint` | agents / login items |
| `maintenance report` | nested `caches` + `docker` documents |
| `purge` | `{ok, …}` (requires `-y`) |

`maintenance monthly` stays a guided human route; prefer `maintenance report --json` for automation.

### Examples

```bash
mac-health --json version
mac-health --json analyze
mac-health --json disk bloat
mac-health --json trash status
mac-health memory --json --top 25
mac-health --json caches list
mac-health --json projects ~/Desktop/Projects.nosync npm
mac-health -y --json caches npm
mac-health --json docker status
mac-health --json docker volumes
mac-health --json docker prune images --dry-run
mac-health -y --json docker prune images
mac-health --json login list
mac-health --json maintenance report
mac-health -y --json trash empty
```

### Schema sketch

```json
{
  "command": "memory",
  "top_n": 15,
  "physical_bytes": 17179869184,
  "vm": { "pressure_heuristic": "Warn", "free_gb": 0.42 },
  "processes": [{ "pid": 1, "rss_kb": 12345, "mem_percent": "1.2", "command": "…" }],
  "families": [{ "family": "Chrome", "processes": 42, "rss_kb": 3145728 }],
  "hints": ["…"]
}
```

Sizes that are inventory-oriented use **bytes** (integer) plus optional **human** string. Process RSS uses **rss_kb** (as reported by `ps`).

## Safety

- Never delete `all-caches` as a whole; `caches list`’s `all-caches` row is size-only.
- `*-deep` cache targets are not part of `caches all`.
- `projects` only removes leaf `vendor` / `node_modules` dirs that pass the sibling-manifest gate.
- Refuse scanning `/` or `$HOME` as a projects root.
- App-gated cleanups call `mh_require_app_closed` first.
- Docker: inspect (`status`, `volumes`) never delete. The only mutator is `docker prune images` (`--dry-run` supported). Containers, networks, volumes, and build cache are never removed by mac-health. Former targets (`soft`, `routine`, `all`, …) are refused.

## Code layout

| Path | Role |
|------|------|
| `mac-health` | Entry: global flags, command dispatch |
| `lib/paths.zsh` | `MH_*` path constants + app process map |
| `lib/common.zsh` | logging, confirm, JSON helpers (`mh_json_mode`, `mh_json_doc`) |
| `commands/*.zsh` | One file per command group |

When adding a new inspect command: support `--json` with a stable `"command"` key, keep human output behind `mh_json_mode` checks, and document it in this file + `README.md`. Exception: `watch` is human-only (live TTY refresh); refuse `--json`.

### zsh `print` pitfall

Never `print` a token that begins with `-` (e.g. `---section---`) without `print -r -- …`. zsh treats it as options (`bad option: -g`). Prefer markers like `===section===` and always `print -r --`.

## Install / release notes

- Public install: `curl …/galaxous/mac-health/…/install.sh | bash`
- Version file: `VERSION` (synced by release workflows when configured)
- Do not commit secrets or machine-local paths into docs beyond examples under `~/…`
