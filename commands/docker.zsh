# cmd: docker — inspect + unused-image prune only
#
# Removals are intentionally limited to unused images. Containers, networks,
# volumes, and build cache are never deleted by mac-health.

typeset -g MH_DOCKER_PROTECT_RE='mariadb|mysql|maria|postgres|pgsql|redis|valkey|mongo|elastic|meili|typesense|rabbit|minio|database|db[_-]?data|_db$'

mh_cmd_docker_usage() {
  cat <<'EOF'
Usage: mac-health docker <action> [flags]

Inspect (no deletes):
  status              Path sizes + system df + volume inventory
  volumes             List volumes (dangling / DB-like protect hints)

REMOVE (images only):
  prune images        Remove unused images (docker image prune -a)
  prune               Same as: prune images

Other:
  quit                Quit Docker Desktop (frees RAM; does not delete disk data)

Flags:
  --dry-run, -n       Show images that would be removed; delete nothing
  --exclude <re>      Extra protect-label regex for volume names (status/volumes)
  -y / --yes          Skip confirms (required with --json for prune)

Examples:
  mac-health docker status
  mac-health docker volumes
  mac-health docker prune images --dry-run
  mac-health -y docker prune images
  mac-health docker quit
EOF
}

mh_docker_require_daemon() {
  local action="${1:-docker}"
  mh_docker_require_cli "$action" || return 1
  if ! docker info >/dev/null 2>&1; then
    if mh_json_mode; then
      MH_JSON_ACTION="$action" mh_json_doc <<'PY'
import os
doc = {
    "command": "docker",
    "action": os.environ.get("MH_JSON_ACTION"),
    "ok": False,
    "error": "Docker daemon not running — start Docker Desktop first",
}
PY
    else
      mh_err "Docker daemon not running — start Docker Desktop first"
    fi
    return 1
  fi
  return 0
}

mh_docker_require_cli() {
  local action="${1:-docker}"
  if ! command -v docker >/dev/null 2>&1; then
    if mh_json_mode; then
      MH_JSON_ACTION="$action" mh_json_doc <<'PY'
import os
doc = {
    "command": "docker",
    "action": os.environ.get("MH_JSON_ACTION"),
    "ok": False,
    "error": "docker not found",
}
PY
    else
      mh_err "docker not found"
    fi
    return 1
  fi
  return 0
}

mh_docker_dry_run() {
  [[ "${MH_DOCKER_DRY_RUN:-0}" == "1" ]]
}

mh_docker_json_mutator() {
  local target="$1" ok="$2" out="${3:-}" df_out="${4:-}" cancelled="${5:-0}"
  MH_JSON_TARGET="$target" MH_JSON_OK="$ok" MH_JSON_OUT="$out" \
  MH_JSON_DF="$df_out" MH_JSON_CANCELLED="$cancelled" \
  mh_json_doc <<'PY'
import os
cancelled = os.environ.get("MH_JSON_CANCELLED") == "1"
doc = {
    "command": "docker",
    "action": "prune",
    "target": os.environ.get("MH_JSON_TARGET"),
    "dry_run": False,
    "ok": os.environ.get("MH_JSON_OK") == "1",
    "output": (os.environ.get("MH_JSON_OUT") or "").strip() or None,
    "system_df": (os.environ.get("MH_JSON_DF") or "").strip() or None,
}
if cancelled:
    doc["cancelled"] = True
PY
}

mh_docker_json_dry_run() {
  local target="$1"
  MH_JSON_TARGET="$target" python3 -c '
import json, os, sys
would = {}
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if not line or "|" not in line:
        continue
    kind, rest = line.split("|", 1)
    if "|" in rest:
        ident, detail = rest.split("|", 1)
    else:
        ident, detail = rest, ""
    would.setdefault(kind, []).append({"id": ident, "detail": detail or None})
doc = {
    "command": "docker",
    "action": "prune",
    "target": os.environ.get("MH_JSON_TARGET"),
    "dry_run": True,
    "ok": True,
    "would_remove": would,
    "counts": {k: len(v) for k, v in would.items()},
}
print(json.dumps(doc, indent=2, ensure_ascii=False))
'
}

mh_docker_preview_unused_images() {
  # Approx. of `docker image prune -a`: images with no container ancestor.
  local id repo tag size
  while IFS=$'\t' read -r id repo tag size; do
    [[ -z "$id" ]] && continue
    if docker ps -aq --filter "ancestor=${id}" 2>/dev/null | grep -q .; then
      continue
    fi
    print -r -- "images|${id}|${repo}:${tag} ${size}"
  done < <(docker images --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}' 2>/dev/null)
}

mh_docker_preview_print() {
  local line kind ident detail rest
  local -A shown
  shown=()
  while IFS= read -r line; do
    [[ -z "$line" || "$line" != *"|"* ]] && continue
    kind="${line%%|*}"
    rest="${line#*|}"
    ident="${rest%%|*}"
    detail="${rest#*|}"
    [[ -z "$kind" || "$kind" == *"="* ]] && continue
    if [[ -z "${shown[$kind]:-}" ]]; then
      shown[$kind]=1
      print -r -- "  [$kind]"
    fi
    if [[ -n "$detail" && "$detail" != "$ident" ]]; then
      print -r -- "    - ${ident}  ${detail}"
    else
      print -r -- "    - ${ident}"
    fi
  done
}

mh_docker_emit_dry_run() {
  local target="$1"
  local preview
  preview="$(cat)"
  if mh_json_mode; then
    print -r -- "$preview" | mh_docker_json_dry_run "$target"
  else
    mh_section "DRY-RUN prune ${target} — would REMOVE (nothing deleted)"
    if [[ -z "$preview" ]]; then
      mh_ok "Nothing matched"
    else
      print -r -- "$preview" | mh_docker_preview_print
    fi
    mh_warn "Dry-run only. Re-run without --dry-run to REMOVE."
  fi
}

mh_docker_is_protected() {
  local name="${(L)1}"
  shift
  local pat
  if [[ "$name" =~ ${MH_DOCKER_PROTECT_RE} ]]; then
    return 0
  fi
  for pat in "$@"; do
    [[ -z "$pat" ]] && continue
    if [[ "$name" =~ ${(L)pat} ]]; then
      return 0
    fi
  done
  return 1
}

mh_docker_collect_volume_rows() {
  local -A all_driver dangling_set
  all_driver=()
  dangling_set=()
  local name driver

  while IFS=$'\t' read -r name driver; do
    [[ -z "$name" ]] && continue
    all_driver[$name]="$driver"
  done < <(docker volume ls --format '{{.Name}}\t{{.Driver}}' 2>/dev/null)

  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    dangling_set[$name]=1
  done < <(docker volume ls -f dangling=true --format '{{.Name}}' 2>/dev/null)

  local prot
  for name in ${(k)all_driver}; do
    prot=0
    if mh_docker_is_protected "$name" "$@"; then
      prot=1
    fi
    print -r -- "${name}|${dangling_set[$name]:-0}|${all_driver[$name]}|${prot}"
  done
}

mh_cmd_docker_status() {
  local -a excludes
  excludes=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --exclude)
        [[ -z "${2:-}" ]] && { mh_err "--exclude requires a regex"; return 1; }
        excludes+=("$2")
        shift 2
        ;;
      -h|--help|help)
        mh_cmd_docker_usage
        return 0
        ;;
      *)
        mh_err "Unknown flag: $1"
        return 1
        ;;
    esac
  done

  local containers_b home_b
  containers_b="$(mh_dir_size_bytes "$MH_DOCKER_CONTAINERS")"
  home_b="$(mh_dir_size_bytes "$MH_DOCKER_HOME")"

  local cli=0 daemon=0 df_out=""
  if command -v docker >/dev/null 2>&1; then
    cli=1
    if docker info >/dev/null 2>&1; then
      daemon=1
      df_out="$(docker system df 2>/dev/null || true)"
    fi
  fi

  local -a vol_rows=()
  if (( daemon )); then
    while IFS= read -r line; do
      [[ -n "$line" ]] && vol_rows+=("$line")
    done < <(mh_docker_collect_volume_rows "${excludes[@]}")
  fi

  if mh_json_mode; then
    {
      print -r -- "containers_b=${containers_b}"
      print -r -- "home_b=${home_b}"
      print -r -- "containers_path=${MH_DOCKER_CONTAINERS}"
      print -r -- "home_path=${MH_DOCKER_HOME}"
      print -r -- "cli=${cli}"
      print -r -- "daemon=${daemon}"
      print -r -- "protect_re=${MH_DOCKER_PROTECT_RE}"
      print -r -- "===df==="
      print -r -- "$df_out"
      print -r -- "===volumes==="
      printf '%s\n' "${vol_rows[@]}"
      print -r -- "===excludes==="
      printf '%s\n' "${excludes[@]}"
    } | python3 -c '
import json, sys
meta = {}
df_lines, vols, excludes = [], [], []
section = "meta"
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "===df===":
        section = "df"; continue
    if line == "===volumes===":
        section = "volumes"; continue
    if line == "===excludes===":
        section = "excludes"; continue
    if section == "meta":
        if "=" in line:
            k, v = line.split("=", 1)
            meta[k] = v
    elif section == "df":
        df_lines.append(line)
    elif section == "volumes":
        if not line:
            continue
        parts = line.split("|", 3)
        if len(parts) == 4:
            vols.append({
                "name": parts[0],
                "dangling": parts[1] == "1",
                "driver": parts[2],
                "protected": parts[3] == "1",
            })
    elif section == "excludes":
        if line:
            excludes.append(line)

dangling = [v for v in vols if v["dangling"]]
protected = [v for v in vols if v["protected"]]
doc = {
    "command": "docker",
    "action": "status",
    "paths": {
        "containers": {"path": meta.get("containers_path"), "bytes": int(meta.get("containers_b") or 0)},
        "home": {"path": meta.get("home_path"), "bytes": int(meta.get("home_b") or 0)},
    },
    "cli_available": meta.get("cli") == "1",
    "daemon_running": meta.get("daemon") == "1",
    "protect_regex": meta.get("protect_re"),
    "exclude_regexes": excludes,
    "system_df": "\n".join(df_lines).strip() or None,
    "volumes": vols,
    "summary": {
        "volume_count": len(vols),
        "dangling_count": len(dangling),
        "protected_count": len(protected),
    },
    "hints": [
        "Only image removal is supported: mac-health docker prune images --dry-run",
        "Containers / networks / volumes are never deleted by mac-health",
    ],
}
print(json.dumps(doc, indent=2, ensure_ascii=False))
'
    return 0
  fi

  mh_section "Docker disk usage"
  printf "  %-55s %s\n" "$MH_DOCKER_CONTAINERS" "$(mh_human_size "$MH_DOCKER_CONTAINERS")"
  printf "  %-55s %s\n" "$MH_DOCKER_HOME" "$(mh_human_size "$MH_DOCKER_HOME")"

  if (( ! cli )); then
    mh_warn "docker not in PATH"
    return 0
  fi
  if (( ! daemon )); then
    mh_warn "Docker CLI present but daemon not running"
    return 0
  fi

  mh_section "system df"
  print -r -- "$df_out"

  mh_section "Volumes (inspect only)"
  printf "  %-8s %-10s %s\n" "STATE" "DB-LIKE" "NAME"
  printf "  %-8s %-10s %s\n" "--------" "----------" "----"
  local row name dang drv prot state_h prot_h rest
  local dang_n=0 prot_n=0
  for row in "${vol_rows[@]}"; do
    name="${row%%|*}"
    rest="${row#*|}"
    dang="${rest%%|*}"
    rest="${rest#*|}"
    drv="${rest%%|*}"
    prot="${rest#*|}"
    state_h="in-use"
    (( dang == 1 )) && state_h="dangling"
    prot_h="—"
    (( prot == 1 )) && prot_h="yes"
    printf "  %-8s %-10s %s\n" "$state_h" "$prot_h" "$name"
    (( dang == 1 )) && dang_n=$(( dang_n + 1 ))
    (( prot == 1 )) && prot_n=$(( prot_n + 1 ))
  done
  print
  mh_log "${#vol_rows} volumes · dangling ${dang_n} · DB-like ${prot_n}"
  mh_ok "Hint: only mac-health docker prune images removes data (volumes never touched)"
}

mh_cmd_docker_quit() {
  mh_section "Quit Docker Desktop"
  if ! mh_app_running docker && ! pgrep -f "Docker Desktop" >/dev/null 2>&1; then
    if mh_json_mode; then
      mh_json_doc <<'PY'
doc = {"command": "docker", "action": "quit", "ok": True, "already_stopped": True}
PY
    else
      mh_ok "Docker does not appear to be running"
    fi
    return 0
  fi
  if ! mh_confirm "Quit Docker Desktop now?"; then
    if mh_json_mode; then
      mh_json_doc <<'PY'
doc = {"command": "docker", "action": "quit", "ok": False, "cancelled": True}
PY
    else
      mh_warn "Cancelled"
    fi
    return 1
  fi
  osascript -e 'quit app "Docker"' 2>/dev/null \
    || osascript -e 'quit app "Docker Desktop"' 2>/dev/null \
    || true
  sleep 2
  if mh_json_mode; then
    mh_json_doc <<'PY'
doc = {"command": "docker", "action": "quit", "ok": True}
PY
  else
    mh_ok "Quit signal sent"
  fi
}

mh_cmd_docker_volumes() {
  local -a excludes
  excludes=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply|--dry-run|-n)
        mh_err "'docker volumes' is inspect-only."
        mh_err "mac-health only removes unused images: docker prune images"
        return 1
        ;;
      --exclude)
        [[ -z "${2:-}" ]] && { mh_err "--exclude requires a regex"; return 1; }
        excludes+=("$2")
        shift 2
        ;;
      -h|--help|help)
        mh_cmd_docker_usage
        return 0
        ;;
      *)
        mh_err "Unknown flag: $1"
        mh_cmd_docker_usage
        return 1
        ;;
    esac
  done

  mh_docker_require_daemon volumes || return 1

  local -a vol_rows=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && vol_rows+=("$line")
  done < <(mh_docker_collect_volume_rows "${excludes[@]}")

  local -a dangling_all=() protected_dangling=()
  local row name dang prot rest
  for row in "${vol_rows[@]}"; do
    name="${row%%|*}"
    rest="${row#*|}"
    dang="${rest%%|*}"
    rest="${rest#*|}"
    rest="${rest#*|}"
    prot="${rest}"
    (( dang != 1 )) && continue
    dangling_all+=("$name")
    (( prot == 1 )) && protected_dangling+=("$name")
  done

  if mh_json_mode; then
    {
      print -r -- "protect_re=${MH_DOCKER_PROTECT_RE}"
      print -r -- "===dangling==="
      printf '%s\n' "${dangling_all[@]}"
      print -r -- "===protected==="
      printf '%s\n' "${protected_dangling[@]}"
      print -r -- "===excludes==="
      printf '%s\n' "${excludes[@]}"
    } | python3 -c '
import json, sys
meta = {}
dangling, protected, excludes = [], [], []
section = "meta"
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "===dangling===":
        section = "dangling"; continue
    if line == "===protected===":
        section = "protected"; continue
    if line == "===excludes===":
        section = "excludes"; continue
    if section == "meta":
        if "=" in line:
            k, v = line.split("=", 1)
            meta[k] = v
    elif section == "dangling":
        if line: dangling.append(line)
    elif section == "protected":
        if line: protected.append(line)
    elif section == "excludes":
        if line: excludes.append(line)
doc = {
    "command": "docker",
    "action": "volumes",
    "mode": "list",
    "protect_regex": meta.get("protect_re"),
    "exclude_regexes": excludes,
    "dangling": dangling,
    "dangling_protected": protected,
    "counts": {"dangling": len(dangling), "protected": len(protected)},
    "hint": "mac-health never deletes volumes; only: docker prune images",
}
print(json.dumps(doc, indent=2, ensure_ascii=False))
'
    return 0
  fi

  mh_section "Volumes (inspect only — nothing deleted)"
  if (( ${#dangling_all} == 0 )); then
    mh_ok "No dangling volumes"
  else
    local n
    for n in "${dangling_all[@]}"; do
      if mh_docker_is_protected "$n" "${excludes[@]}"; then
        print -r -- "  [dangling][db-like] $n"
      else
        print -r -- "  [dangling] $n"
      fi
    done
  fi
  mh_log "Protect label regex: ${MH_DOCKER_PROTECT_RE}"
  mh_warn "Inspect only. Removals: mac-health docker prune images"
}

mh_cmd_docker_images() {
  mh_docker_require_daemon "prune" || return 1
  if mh_docker_dry_run; then
    mh_docker_preview_unused_images | mh_docker_emit_dry_run images
    return 0
  fi

  mh_section "PRUNE images — remove unused images (-a)"
  mh_warn "This DELETES images not used by any container. Volumes/containers/networks are kept."
  if ! mh_confirm "REMOVE with: docker image prune -a -f ?"; then
    if mh_json_mode; then
      mh_docker_json_mutator "images" 0 "" "" 1
    else
      mh_warn "Cancelled"
    fi
    return 1
  fi
  local out df_out
  out="$(docker image prune -a -f 2>&1)" || {
    mh_err "prune images failed"
    return 1
  }
  df_out="$(docker system df 2>/dev/null || true)"
  if mh_json_mode; then
    mh_docker_json_mutator "images" 1 "$out" "$df_out" 0
  else
    print -r -- "$out"
    mh_ok "prune images done (volumes untouched)"
    print -r -- "$df_out"
  fi
}

mh_cmd_docker_prune() {
  typeset -g MH_DOCKER_DRY_RUN="${MH_DOCKER_DRY_RUN:-0}"
  local -a rest
  rest=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run|-n)
        MH_DOCKER_DRY_RUN=1
        shift
        ;;
      *)
        rest+=("$1")
        shift
        ;;
    esac
  done
  set -- "${rest[@]}"

  local target="${1:-images}"
  [[ $# -gt 0 ]] && shift
  case "$target" in
    ""|images|image)
      mh_cmd_docker_images "$@"
      ;;
    -h|--help|help)
      mh_cmd_docker_usage
      ;;
    soft|routine|recommended|buildcache|builder|cache|volumes|volume|vol|all|nuke|full)
      mh_err "Removed: 'docker prune ${target}' — mac-health only prunes unused images."
      mh_err "Use: mac-health docker prune images [--dry-run]"
      return 1
      ;;
    *)
      mh_err "Unknown prune target: ${target} (only 'images' is supported)"
      mh_cmd_docker_usage
      return 1
      ;;
  esac
}

mh_cmd_docker() {
  local action="${1:-status}"
  [[ $# -gt 0 ]] && shift
  case "$action" in
    -h|--help|help) mh_cmd_docker_usage ;;
    status|df) mh_cmd_docker_status "$@" ;;
    volumes|volume|vol) mh_cmd_docker_volumes "$@" ;;
    prune) mh_cmd_docker_prune "$@" ;;
    quit|stop) mh_cmd_docker_quit "$@" ;;
    soft|safe|routine|buildcache|builder|cache|nuke|full|images|image)
      mh_err "Use explicit: mac-health docker prune images [--dry-run]"
      mh_cmd_docker_usage
      return 1
      ;;
    *)
      mh_err "Unknown docker action: $action"
      mh_cmd_docker_usage
      return 1
      ;;
  esac
}
