# Shared helpers for mac-health toolkit.
# Requires: lib/paths.zsh already sourced.

autoload -Uz colors && colors

# MH_JSON=1 → machine-readable JSON on stdout; human UI suppressed (warns/errors → stderr).

mh_json_mode() {
  [[ "${MH_JSON:-0}" == "1" ]]
}

mh_log() {
  mh_json_mode && return 0
  print -P "%F{cyan}[mac-health]%f $*"
}

mh_ok() {
  mh_json_mode && return 0
  print -P "%F{green}✔%f $*"
}

mh_warn() {
  if mh_json_mode; then
    print -r -- "[warn] $*" >&2
    return 0
  fi
  print -P "%F{yellow}!%f $*"
}

mh_err() {
  print -P "%F{red}✖%f $*" >&2
}

mh_section() {
  mh_json_mode && return 0
  print -P "\n%F{blue}==>%f %B$*%b"
}

# Emit JSON from a Python snippet that sets `doc = ...`
# Usage: mh_json_doc <<'PY'
# doc = {"ok": True}
# PY
mh_json_doc() {
  python3 -c '
import json, sys
ns = {}
exec(sys.stdin.read(), ns, ns)
doc = ns.get("doc")
if doc is None:
    raise SystemExit("mh_json_doc: Python snippet must set doc = ...")
print(json.dumps(doc, indent=2, ensure_ascii=False))
'
}

mh_human_size() {
  local path="$1" out
  if [[ -e "$path" ]]; then
    out="$(/usr/bin/du -sh "$path" 2>/dev/null)"
    print "${out%%$'\t'*}"
  else
    print "—"
  fi
}

mh_dir_size_bytes() {
  local path="$1" out
  if [[ -e "$path" ]]; then
    out="$(/usr/bin/du -sk "$path" 2>/dev/null)"
    print $(( ${out%%$'\t'*} * 1024 ))
  else
    print 0
  fi
}

mh_confirm() {
  local prompt="${1:-Continue?}"
  local reply
  if [[ "${MH_YES:-0}" == "1" ]]; then
    return 0
  fi
  if mh_json_mode; then
    mh_err "JSON mode requires -y / --yes / --no-interaction for destructive actions"
    return 1
  fi
  read -q "reply?${prompt} [y/N] "
  print
  [[ "$reply" == "y" || "$reply" == "Y" ]]
}

mh_app_running() {
  local key="$1"
  local name="${MH_APP_PROCESS[$key]:-$key}"
  pgrep -xq "$name" 2>/dev/null || pgrep -x "$name" >/dev/null 2>&1
}

mh_require_app_closed() {
  local key="$1"
  local name="${MH_APP_PROCESS[$key]:-$key}"
  if mh_app_running "$key"; then
    mh_err "$name is running. Quit it first, then retry."
    return 1
  fi
  return 0
}

mh_safe_rm_contents() {
  local dir="$1"
  local label="${2:-$dir}"

  if [[ ! -d "$dir" ]]; then
    mh_warn "Skip (missing): $label"
    return 0
  fi

  local before
  before="$(mh_human_size "$dir")"
  mh_log "Cleaning $label (was $before)…"

  find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  mh_ok "$label cleaned (now $(mh_human_size "$dir"))"
}

mh_run_if_cmd() {
  local bin="$1"
  shift
  if command -v "$bin" >/dev/null 2>&1; then
    "$bin" "$@"
  else
    mh_warn "Command not found: $bin — skipped"
    return 1
  fi
}

mh_bytes_to_gb() {
  awk -v b="$1" 'BEGIN { printf "%.2f", b / (1024*1024*1024) }'
}
