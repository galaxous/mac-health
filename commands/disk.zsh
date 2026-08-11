# cmd: disk — APFS Data summary + Library buckets + known bloat (inspect only)

mh_cmd_disk_usage() {
  cat <<'EOF'
Usage: mac-health disk [status|bloat] [--json]

Inspect only — never deletes.

Actions:
  status   Data volume + fixed ~/Library buckets (default)
  bloat    Known fat paths with cleanup hints

Examples:
  mac-health disk
  mac-health disk bloat
  mac-health --json disk status
EOF
}

# Emit primary volume fields from df -kP (python → key=value lines on stdout).
mh_disk_emit_primary_kv() {
  {
    /bin/df -kP / /System/Volumes/Data 2>/dev/null || /bin/df -kP /
  } | python3 -c '
import sys
rows = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line or line.startswith("Filesystem"):
        continue
    cols = line.split()
    if len(cols) < 6:
        continue
    try:
        blocks, used, avail = int(cols[1]), int(cols[2]), int(cols[3])
    except ValueError:
        continue
    cap_s = cols[4]
    try:
        cap = int(cap_s.rstrip("%"))
    except ValueError:
        cap = None
    mount = " ".join(cols[5:])
    rows.append((mount, blocks, used, avail, cap, cap_s))

data = next((r for r in rows if r[0] == "/System/Volumes/Data"), None)
root = next((r for r in rows if r[0] == "/"), None)
primary = data or root
if not primary:
    raise SystemExit(0)

def gi(k):
    return round(k / 1024 / 1024, 2)

role = "data" if data else "root"
pct = primary[4]
if pct is None:
    status = ""
elif pct >= 90:
    status = "Critical"
elif pct >= 75:
    status = "Warn"
else:
    status = "OK"

print("role=" + role)
print("mounted_on=" + primary[0])
print("used_1k=" + str(primary[2]))
print("avail_1k=" + str(primary[3]))
print("blocks_1k=" + str(primary[1]))
print("used_gi=" + str(gi(primary[2])))
print("free_gi=" + str(gi(primary[3])))
print("total_gi=" + str(gi(primary[1])))
print("capacity=" + primary[5])
print("capacity_percent=" + (str(pct) if pct is not None else ""))
print("status=" + status)
if root:
    print("system_used_gi=" + str(gi(root[2])))
'
}

mh_disk_library_bucket_lines() {
  # key|path|bytes|human
  local -a keys=(Caches "Application Support" Logs Containers Developer)
  local k path sized bytes human
  for k in "${keys[@]}"; do
    path="${MH_LIBRARY}/${k}"
    sized="$(mh_dir_size_timed "$path" 6)"
    bytes="${sized%%|*}"
    human="${sized#*|}"
    print -r -- "${k}|${path}|${bytes}|${human}"
  done
}

mh_disk_bloat_lines() {
  # key|path|hint|bytes|human
  local -a rows=(
    "trash|${MH_TRASH}|mac-health trash empty"
    "homebrew-cache|${MH_CACHE_HOMEBREW}|mac-health caches brew"
    "npm-cache|${MH_NPM_CACHE}|mac-health caches npm"
    "composer-cache|${MH_CACHE_COMPOSER}|mac-health caches composer"
    "all-caches|${MH_CACHES}|mac-health caches list  # summary only"
    "logs|${MH_LOGS}|mac-health caches logs"
    "cursor-support|${MH_CURSOR_SUPPORT}|mac-health caches cursor"
    "code-support|${MH_CODE_SUPPORT}|mac-health caches code"
    "chrome-cache|${MH_CACHE_CHROME}|mac-health caches chrome"
    "docker-containers|${MH_DOCKER_CONTAINERS}|mac-health docker status / docker quit"
    "xcode-derived|${MH_XCODE_DERIVED}|Xcode → Settings → Locations → DerivedData (or delete folder)"
    "xcode-archives|${MH_XCODE_ARCHIVES}|Xcode Organizer / delete old archives"
    "core-simulator|${MH_CORESIMULATOR}|xcrun simctl delete unavailable"
  )
  local row key path hint rest sized bytes human
  for row in "${rows[@]}"; do
    key="${row%%|*}"
    rest="${row#*|}"
    path="${rest%%|*}"
    hint="${rest#*|}"
    sized="$(mh_dir_size_timed "$path" 6)"
    bytes="${sized%%|*}"
    human="${sized#*|}"
    print -r -- "${key}|${path}|${hint}|${bytes}|${human}"
  done
}

mh_cmd_disk_status() {
  local -A primary=()
  local line k v
  while IFS= read -r line; do
    [[ -z "$line" || "$line" != *=* ]] && continue
    k="${line%%=*}"
    v="${line#*=}"
    primary[$k]="$v"
  done < <(mh_disk_emit_primary_kv)

  if mh_json_mode; then
    {
      print -r -- "===primary==="
      for k in ${(k)primary}; do
        print -r -- "${k}=${primary[$k]}"
      done
      print -r -- "===library==="
      mh_disk_library_bucket_lines
    } | python3 -c '
import json, sys
meta = {}
library = []
section = "meta"
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "===primary===":
        section = "primary"
        continue
    if line == "===library===":
        section = "library"
        continue
    if section == "primary" and "=" in line:
        k, v = line.split("=", 1)
        meta[k] = v
    elif section == "library" and line:
        key, path, nbytes, human = line.split("|", 3)
        library.append({"key": key, "path": path, "bytes": int(nbytes or 0), "human": human})
cap = meta.get("capacity_percent") or None
doc = {
    "command": "disk",
    "action": "status",
    "primary": {
        "role": meta.get("role"),
        "note": "APFS Data volume — what fills your Mac" if meta.get("role") == "data" else "Root volume",
        "mounted_on": meta.get("mounted_on"),
        "used_gi": float(meta["used_gi"]) if meta.get("used_gi") else None,
        "free_gi": float(meta["free_gi"]) if meta.get("free_gi") else None,
        "total_gi": float(meta["total_gi"]) if meta.get("total_gi") else None,
        "capacity": meta.get("capacity") or None,
        "capacity_percent": int(cap) if cap not in (None, "") else None,
        "status": meta.get("status") or None,
    },
    "system_volume": {
        "mounted_on": "/",
        "used_gi": float(meta["system_used_gi"]),
        "note": "Sealed OS space; ignore for cleanup.",
    } if meta.get("system_used_gi") else None,
    "library": library,
}
print(json.dumps(doc, indent=2, ensure_ascii=False))
'
    return 0
  fi

  mh_section "Disk (Data volume)"
  if [[ -z "${primary[mounted_on]:-}" ]]; then
    mh_warn "Could not read disk usage"
    return 0
  fi
  print -r -- "  Mount:    ${primary[mounted_on]}"
  print -r -- "  Used:     ${primary[used_gi]} Gi"
  print -r -- "  Free:     ${primary[free_gi]} Gi"
  print -r -- "  Capacity: ${primary[capacity]}  (${primary[total_gi]} Gi total)"
  print -r -- "  Status:   ${primary[status]:-—}"
  if [[ -n "${primary[system_used_gi]:-}" ]]; then
    print
    print -r -- "  System (/) sealed OS — ${primary[system_used_gi]} Gi used; do not sum with Data."
  fi

  mh_section "~/Library buckets"
  local key path nbytes human
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%|*}"
    rest="${line#*|}"
    path="${rest%%|*}"
    rest="${rest#*|}"
    nbytes="${rest%%|*}"
    human="${rest#*|}"
    printf "  %-22s %-48s %s\n" "$key" "$path" "$human"
  done < <(mh_disk_library_bucket_lines)

  mh_ok "Disk status complete (inspect only)"
}

mh_cmd_disk_bloat() {
  if mh_json_mode; then
    {
      mh_disk_bloat_lines
    } | python3 -c '
import json, sys
items = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    key, path, hint, nbytes, human = line.split("|", 4)
    items.append({
        "key": key,
        "path": path,
        "hint": hint,
        "bytes": int(nbytes or 0),
        "human": human,
    })
items.sort(key=lambda x: x["bytes"], reverse=True)
print(json.dumps({"command": "disk", "action": "bloat", "items": items}, indent=2, ensure_ascii=False))
'
    return 0
  fi

  mh_section "Known bloat candidates (inspect only)"
  print -r -- "  Sorted by size. Hints are suggestions — nothing is deleted here."
  print
  printf "  %-18s %10s  %s\n" "KEY" "SIZE" "HINT"
  printf "  %-18s %10s  %s\n" "------------------" "----------" "----"

  local -a lines sorted
  lines=("${(@f)$(mh_disk_bloat_lines)}")
  sorted=("${(@f)$(printf '%s\n' "${lines[@]}" | /usr/bin/awk -F'|' '{print $4 "|" $0}' | /usr/bin/sort -t'|' -nr -k1 | /usr/bin/cut -d'|' -f2-)}")

  local line key path hint nbytes human
  for line in "${sorted[@]}"; do
    [[ -z "$line" ]] && continue
    key="${line%%|*}"
    rest="${line#*|}"
    path="${rest%%|*}"
    rest="${rest#*|}"
    hint="${rest%%|*}"
    rest="${rest#*|}"
    nbytes="${rest%%|*}"
    human="${rest#*|}"
    printf "  %-18s %10s  %s\n" "$key" "$human" "$hint"
  done

  mh_ok "Bloat inventory complete"
}

mh_cmd_disk() {
  local action="${1:-status}"
  [[ $# -gt 0 ]] && shift
  case "$action" in
    -h|--help|help) mh_cmd_disk_usage ;;
    status|"") mh_cmd_disk_status "$@" ;;
    bloat|fat) mh_cmd_disk_bloat "$@" ;;
    *)
      mh_err "Unknown disk action: $action"
      mh_cmd_disk_usage
      return 1
      ;;
  esac
}
