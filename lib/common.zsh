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
    out="$(/usr/bin/du -sh "$path" 2>/dev/null || true)"
    if [[ -n "$out" ]]; then
      print "${out%%$'\t'*}"
    else
      print "—"
    fi
  else
    print "—"
  fi
}

mh_dir_size_bytes() {
  local path="$1" out kb
  if [[ -e "$path" ]]; then
    out="$(/usr/bin/du -sk "$path" 2>/dev/null || true)"
    kb="${out%%$'\t'*}"
    if [[ "$kb" =~ ^[0-9]+$ ]]; then
      print $(( kb * 1024 ))
    else
      print 0
    fi
  else
    print 0
  fi
}

# Timed du for huge trees (Containers, Developer, ...). On timeout: bytes=-1, human=...
# Usage: mh_dir_size_timed <path> [seconds] → prints "bytes|human"
mh_dir_size_timed() {
  local path="$1"
  local sec="${2:-8}"
  local out kb human rc

  if [[ ! -e "$path" ]]; then
    print -r -- "0|—"
    return 0
  fi

  # perl alarm avoids hanging forever on deep trees
  out="$(/usr/bin/perl -e 'alarm shift; exec @ARGV' "$sec" /usr/bin/du -sk "$path" 2>/dev/null)"
  rc=$?
  if (( rc != 0 )); then
    if (( rc == 142 || rc == 255 || rc > 128 )); then
      print -r -- "-1|..."
    else
      print -r -- "0|—"
    fi
    return 0
  fi

  kb="${out%%$'\t'*}"
  kb="${kb##[[:space:]]#}"
  if [[ ! "$kb" =~ ^[0-9]+$ ]]; then
    print -r -- "0|—"
    return 0
  fi
  human="$(/usr/bin/awk -v k="$kb" 'BEGIN {
    b = k * 1024
    if (b < 1024) { printf "%dB", b; exit }
    split("KB MB GB TB", u, " ")
    n = b; i = 0
    while (n >= 1024 && i < 4) { n /= 1024; i++ }
    if (n >= 10 || i == 0) printf "%.0f%s", n, u[i]
    else printf "%.1f%s", n, u[i]
  }')"
  print -r -- "$(( kb * 1024 ))|${human}"
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
