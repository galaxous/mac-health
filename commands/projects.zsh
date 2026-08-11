# cmd: projects — scan/purge vendor + node_modules under a required root

mh_cmd_projects_usage() {
  cat <<'EOF'
Usage: mac-health projects <root> <target> [flags]

Arguments:
  <root>      Required directory to scan (e.g. ~/Desktop/Projects.nosync)
  <target>    composer | npm | all

Targets:
  composer    vendor dirs whose parent has composer.json|lock (or composer-dev.*)
  npm         node_modules dirs whose parent has package.json|package-lock.json
  all         both (same per-dir manifest checks)

Flags:
  (default)           Dry-run: list matches + sizes (no delete)
  --apply             Delete matched directories
  --no-interaction    Skip confirm on --apply (same as mac-health -y)
  --json              Machine-readable JSON on stdout
  --maxDepth <n>      Max project nesting under root (default: 1)
                      1 = root/<project>/vendor|node_modules only
                      2 = also root/<a>/<b>/vendor|node_modules, etc.
  --exclude <regex>   Drop relative paths matching regex (repeatable)
  --include <regex>   If any include is set, keep only matches (repeatable)

Examples:
  mac-health projects ~/Desktop/Projects.nosync composer
  mac-health projects ~/Desktop/Projects.nosync npm --maxDepth 3
  mac-health projects ~/Desktop/Projects.nosync all --exclude 'b2press-cms|modularous'
  mac-health projects ~/Desktop/Projects.nosync npm --include 'heydaytr' --apply
  mac-health -y projects ~/Desktop/Projects.nosync all --apply
EOF
}

mh_projects_resolve_root() {
  # $1 = user path → print absolute path or return 1
  local raw="$1"
  local expanded="${raw/#\~/${HOME}}"
  local abs

  if [[ ! -e "$expanded" ]]; then
    mh_err "Root does not exist: $raw"
    return 1
  fi
  if [[ ! -d "$expanded" ]]; then
    mh_err "Root is not a directory: $raw"
    return 1
  fi

  abs="$(cd "$expanded" && pwd -P)"
  if [[ -z "$abs" ]]; then
    mh_err "Could not resolve root: $raw"
    return 1
  fi

  if [[ "$abs" == "/" || "$abs" == "$HOME" ]]; then
    mh_err "Refusing to scan root filesystem or \$HOME ($abs)"
    return 1
  fi

  print -r -- "$abs"
}

mh_projects_dirname_ok() {
  # $1 = basename, $2 = target (composer|npm|all)
  local base="$1"
  local target="$2"
  case "$target" in
    composer) [[ "$base" == "vendor" ]] ;;
    npm) [[ "$base" == "node_modules" ]] ;;
    all) [[ "$base" == "vendor" || "$base" == "node_modules" ]] ;;
    *) return 1 ;;
  esac
}

mh_projects_has_manifest() {
  # $1 = full path to vendor|node_modules, $2 = kind (composer|npm)
  # Keep only if a package-manager manifest exists in the parent directory.
  local dep="$1"
  local kind="$2"
  local parent="${dep:h}"

  case "$kind" in
    composer)
      [[ -f "$parent/composer.json" || -f "$parent/composer.lock" \
        || -f "$parent/composer-dev.json" || -f "$parent/composer-dev.lock" ]]
      ;;
    npm)
      [[ -f "$parent/package.json" || -f "$parent/package-lock.json" ]]
      ;;
    *)
      return 1
      ;;
  esac
}

mh_projects_relpath() {
  local root="$1"
  local full="$2"
  local rel="${full#${root}/}"
  if [[ "$rel" == "$full" ]]; then
    print -r -- "$full"
  else
    print -r -- "$rel"
  fi
}

mh_projects_filter_path() {
  # stdin unused; args: relpath, then include patterns (empty means all), exclude patterns
  # Returns 0 if path should be kept
  local rel="$1"
  shift
  local -a includes excludes
  includes=()
  excludes=()

  # Remaining args: "i:pattern" or "e:pattern"
  local item
  for item in "$@"; do
    case "$item" in
      i:*) includes+=("${item#i:}") ;;
      e:*) excludes+=("${item#e:}") ;;
    esac
  done

  local pat
  if (( ${#includes} > 0 )); then
    local hit=0
    for pat in "${includes[@]}"; do
      if [[ "$rel" =~ $pat ]]; then
        hit=1
        break
      fi
    done
    (( hit )) || return 1
  fi

  for pat in "${excludes[@]}"; do
    if [[ "$rel" =~ $pat ]]; then
      return 1
    fi
  done
  return 0
}

mh_projects_human_bytes() {
  local bytes="${1:-0}"
  /usr/bin/awk -v b="$bytes" 'BEGIN {
    if (b < 1024) { printf "%dB", b; exit }
    split("KB MB GB TB", u, " ")
    n = b
    i = 0
    while (n >= 1024 && i < 4) { n /= 1024; i++ }
    if (n >= 10 || i == 0) printf "%.0f%s", n, u[i]
    else printf "%.1f%s", n, u[i]
  }'
}

mh_cmd_projects() {
  local apply=0
  local max_depth=1
  local -a includes excludes positionals
  includes=()
  excludes=()
  positionals=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help|help)
        mh_cmd_projects_usage
        return 0
        ;;
      --apply)
        apply=1
        shift
        ;;
      --no-interaction)
        MH_YES=1
        shift
        ;;
      --maxDepth|--max-depth)
        if [[ -z "${2:-}" || ! "${2}" =~ ^[1-9][0-9]*$ ]]; then
          mh_err "--maxDepth requires a positive integer (got: ${2:-})"
          return 1
        fi
        max_depth="$2"
        shift 2
        ;;
      --maxDepth=*|--max-depth=*)
        local md="${1#*=}"
        if [[ ! "$md" =~ ^[1-9][0-9]*$ ]]; then
          mh_err "--maxDepth requires a positive integer (got: ${md})"
          return 1
        fi
        max_depth="$md"
        shift
        ;;
      --exclude)
        if [[ -z "${2:-}" ]]; then
          mh_err "--exclude requires a regex"
          return 1
        fi
        excludes+=("$2")
        shift 2
        ;;
      --include)
        if [[ -z "${2:-}" ]]; then
          mh_err "--include requires a regex"
          return 1
        fi
        includes+=("$2")
        shift 2
        ;;
      --)
        shift
        positionals+=("$@")
        break
        ;;
      -*)
        mh_err "Unknown flag: $1"
        mh_cmd_projects_usage
        return 1
        ;;
      *)
        positionals+=("$1")
        shift
        ;;
    esac
  done

  if (( ${#positionals} < 2 )); then
    mh_err "Missing required arguments: <root> <target>"
    mh_cmd_projects_usage
    return 1
  fi

  local root_raw="${positionals[1]}"
  local target="${positionals[2]}"
  if (( ${#positionals} > 2 )); then
    mh_err "Unexpected extra arguments: ${positionals[3,-1]}"
    mh_cmd_projects_usage
    return 1
  fi

  case "$target" in
    composer|npm|all) ;;
    *)
      mh_err "Unknown target: $target (use composer|npm|all)"
      mh_cmd_projects_usage
      return 1
      ;;
  esac

  local root
  root="$(mh_projects_resolve_root "$root_raw")" || return 1

  local -a filter_args
  filter_args=()
  local p
  for p in "${includes[@]}"; do
    filter_args+=("i:$p")
  done
  for p in "${excludes[@]}"; do
    filter_args+=("e:$p")
  done

  mh_section "Projects scan"
  mh_log "root:     $root"
  mh_log "target:   $target"
  mh_log "maxDepth: $max_depth"
  mh_log "mode:     $([[ $apply -eq 1 ]] && print apply || print dry-run)"
  (( ${#includes} )) && mh_log "include:  ${(j:, :)includes}"
  (( ${#excludes} )) && mh_log "exclude:  ${(j:, :)excludes}"

  local -a found_raw matched
  found_raw=()
  matched=()

  # maxDepth=1 → root/<project>/vendor (find -maxdepth 2)
  # maxDepth=N → up to N path segments under root before the leaf dir name
  local find_maxdepth=$(( max_depth + 1 ))

  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && found_raw+=("$line")
  done < <(/usr/bin/find "$root" -maxdepth "$find_maxdepth" \( -type d -name node_modules -o -type d -name vendor \) -prune -print 2>/dev/null)

  local full base rel kind
  for full in "${found_raw[@]}"; do
    base="${full:t}"
    mh_projects_dirname_ok "$base" "$target" || continue
    case "$base" in
      vendor) kind=composer ;;
      node_modules) kind=npm ;;
      *) continue ;;
    esac
    mh_projects_has_manifest "$full" "$kind" || continue
    rel="$(mh_projects_relpath "$root" "$full")"
    if mh_projects_filter_path "$rel" "${filter_args[@]}"; then
      matched+=("$full")
    fi
  done

  if (( ${#matched} == 0 )); then
    if mh_json_mode; then
      MH_JSON_ROOT="$root" MH_JSON_TARGET="$target" MH_JSON_DEPTH="$max_depth" \
      MH_JSON_MODE="$([[ $apply -eq 1 ]] && print apply || print dry-run)" \
      mh_json_doc <<'PY'
import os
doc = {
    "command": "projects",
    "root": os.environ["MH_JSON_ROOT"],
    "target": os.environ["MH_JSON_TARGET"],
    "max_depth": int(os.environ["MH_JSON_DEPTH"]),
    "mode": os.environ["MH_JSON_MODE"],
    "matches": [],
    "total_bytes": 0,
    "count": 0,
}
PY
    else
      mh_ok "No matching directories"
    fi
    return 0
  fi

  # Build sortable rows: kb|path|human
  local -a rows
  rows=()
  local kb total_bytes=0
  for full in "${matched[@]}"; do
    kb="$(/usr/bin/du -sk "$full" 2>/dev/null | /usr/bin/awk '{print $1}')"
    kb="${kb:-0}"
    total_bytes=$(( total_bytes + kb * 1024 ))
    rows+=("${kb}|${full}|$(mh_human_size "$full")")
  done

  # Sort by size descending
  local -a sorted
  sorted=("${(@f)$(printf '%s\n' "${rows[@]}" | /usr/bin/sort -t'|' -nr -k1)}")

  local total_h
  total_h="$(mh_projects_human_bytes "$total_bytes")"

  if (( ! apply )); then
    if mh_json_mode; then
      {
        print "root=${root}"
        print "target=${target}"
        print "max_depth=${max_depth}"
        print "mode=dry-run"
        print "total_bytes=${total_bytes}"
        print "count=${#matched}"
        print -r -- "===matches==="
        local row size_h path_abs
        for row in "${sorted[@]}"; do
          kb="${row%%|*}"
          size_h="${row##*|}"
          path_abs="${row#*|}"
          path_abs="${path_abs%|*}"
          print "${path_abs}|$(( kb * 1024 ))|${size_h}"
        done
      } | python3 -c '
import json, sys
meta = {}
matches = []
section = "meta"
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "===matches===":
        section = "matches"
        continue
    if section == "meta":
        if "=" in line:
            k, v = line.split("=", 1)
            meta[k] = v
    elif section == "matches":
        if not line:
            continue
        path, nbytes, human = line.split("|", 2)
        matches.append({"path": path, "bytes": int(nbytes), "human": human})
doc = {
    "command": "projects",
    "root": meta.get("root"),
    "target": meta.get("target"),
    "max_depth": int(meta.get("max_depth") or 1),
    "mode": "dry-run",
    "matches": matches,
    "total_bytes": int(meta.get("total_bytes") or 0),
    "count": int(meta.get("count") or 0),
}
print(json.dumps(doc, indent=2, ensure_ascii=False))
'
      return 0
    fi

    print
    printf "  %-10s  %s\n" "SIZE" "PATH"
    printf "  %-10s  %s\n" "----------" "----"
    local row size_h path_abs
    for row in "${sorted[@]}"; do
      kb="${row%%|*}"
      size_h="${row##*|}"
      path_abs="${row#*|}"
      path_abs="${path_abs%|*}"
      printf "  %-10s  %s\n" "$size_h" "$path_abs"
    done

    print
    mh_log "${#matched} directories · reclaimable ~${total_h}"
    mh_warn "Dry-run only. Re-run with --apply to delete."
    return 0
  fi

  if ! mh_confirm "Delete ${#matched} directories (~${total_h}) under ${root}?"; then
    if mh_json_mode; then
      mh_json_doc <<'PY'
doc = {"command": "projects", "ok": False, "cancelled": True}
PY
    else
      mh_warn "Cancelled"
    fi
    return 1
  fi

  local deleted=0
  local -a deleted_paths=()
  for full in "${matched[@]}"; do
    if [[ ! -d "$full" ]]; then
      mh_warn "Skip (missing): $full"
      continue
    fi
    # Only remove leaf vendor/node_modules dirs
    base="${full:t}"
    if [[ "$base" != "vendor" && "$base" != "node_modules" ]]; then
      mh_err "Refuse unexpected path: $full"
      return 1
    fi
    mh_log "Removing $full ($(mh_human_size "$full"))…"
    rm -rf "$full"
    mh_ok "Removed $full"
    deleted=$(( deleted + 1 ))
    deleted_paths+=("$full")
  done

  if mh_json_mode; then
    {
      print "root=${root}"
      print "target=${target}"
      print "max_depth=${max_depth}"
      print "total_bytes=${total_bytes}"
      print "deleted=${deleted}"
      print -r -- "===deleted==="
      printf '%s\n' "${deleted_paths[@]}"
    } | python3 -c '
import json, sys
meta = {}
deleted_paths = []
section = "meta"
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "===deleted===":
        section = "deleted"
        continue
    if section == "meta":
        if "=" in line:
            k, v = line.split("=", 1)
            meta[k] = v
    elif section == "deleted":
        if line:
            deleted_paths.append(line)
doc = {
    "command": "projects",
    "ok": True,
    "root": meta.get("root"),
    "target": meta.get("target"),
    "max_depth": int(meta.get("max_depth") or 1),
    "mode": "apply",
    "deleted": int(meta.get("deleted") or 0),
    "deleted_paths": deleted_paths,
    "total_bytes": int(meta.get("total_bytes") or 0),
}
print(json.dumps(doc, indent=2, ensure_ascii=False))
'
    return 0
  fi

  mh_ok "Deleted ${deleted} directories (~${total_h})"
}
