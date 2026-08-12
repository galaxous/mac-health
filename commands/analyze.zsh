# cmd: analyze — one-shot advice (RAM + disk + top actions); inspect only

mh_cmd_analyze_usage() {
  cat <<'EOF'
Usage: mac-health analyze [--json]
Aliases: advise

Inspect only. Summarizes memory pressure, Data volume, heavy app families,
notable bloat paths, and suggests up to 3 follow-up commands.

Examples:
  mac-health analyze
  mac-health advise
  mac-health --json analyze
EOF
}

mh_cmd_analyze() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help|help)
        mh_cmd_analyze_usage
        return 0
        ;;
      *)
        mh_err "Unknown argument: $1"
        mh_cmd_analyze_usage
        return 1
        ;;
    esac
  done

  local page_size free active inactive wired compressor_occ phys_bytes
  page_size="$(pagesize 2>/dev/null || print 16384)"
  free="$(vm_stat | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')"
  active="$(vm_stat | awk '/Pages active/ {gsub(/\./,"",$3); print $3}')"
  inactive="$(vm_stat | awk '/Pages inactive/ {gsub(/\./,"",$3); print $3}')"
  wired="$(vm_stat | awk '/Pages wired/ {gsub(/\./,"",$4); print $4}')"
  compressor_occ="$(vm_stat | awk '/Pages occupied by compressor/ {gsub(/\./,"",$5); print $5}')"
  phys_bytes="$(sysctl -n hw.memsize 2>/dev/null || print 0)"

  local -A primary=()
  local line k v
  while IFS= read -r line; do
    [[ -z "$line" || "$line" != *=* ]] && continue
    k="${line%%=*}"
    v="${line#*=}"
    primary[$k]="$v"
  done < <(mh_disk_emit_primary_kv)

  local trash_b trash_h bloat_blob ps_out
  trash_b="$(mh_dir_size_bytes "$MH_TRASH")"
  trash_h="$(mh_human_size "$MH_TRASH")"
  bloat_blob="$(mh_disk_bloat_lines)"
  ps_out="$(/bin/ps -axo pid=,rss=,%mem=,comm= 2>/dev/null)" || ps_out=""

  local raw
  raw="$(
    {
      print -r -- "page_size=${page_size}"
      print -r -- "free=${free}"
      print -r -- "active=${active}"
      print -r -- "inactive=${inactive}"
      print -r -- "wired=${wired}"
      print -r -- "compressor_occ=${compressor_occ}"
      print -r -- "phys_bytes=${phys_bytes}"
      print -r -- "disk_role=${primary[role]:-}"
      print -r -- "disk_mount=${primary[mounted_on]:-}"
      print -r -- "disk_used_gi=${primary[used_gi]:-}"
      print -r -- "disk_free_gi=${primary[free_gi]:-}"
      print -r -- "disk_total_gi=${primary[total_gi]:-}"
      print -r -- "disk_capacity=${primary[capacity]:-}"
      print -r -- "disk_pct=${primary[capacity_percent]:-}"
      print -r -- "disk_status=${primary[status]:-}"
      print -r -- "trash_bytes=${trash_b}"
      print -r -- "trash_human=${trash_h}"
      print -r -- "===bloat==="
      print -r -- "$bloat_blob"
      print -r -- "===ps==="
      print -r -- "$ps_out"
    } | python3 -c '
import json, re, sys

meta = {}
bloat = []
ps_lines = []
section = "meta"
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "===bloat===":
        section = "bloat"
        continue
    if line == "===ps===":
        section = "ps"
        continue
    if section == "meta":
        if "=" in line:
            k, v = line.split("=", 1)
            meta[k] = v
    elif section == "bloat":
        if line:
            parts = line.split("|", 4)
            if len(parts) == 5:
                bloat.append({
                    "key": parts[0],
                    "path": parts[1],
                    "hint": parts[2],
                    "bytes": int(parts[3] or 0),
                    "human": parts[4],
                })
    elif section == "ps":
        if line.strip():
            ps_lines.append(line)

page = int(meta.get("page_size") or 16384)

def gb(pages):
    return round(int(pages or 0) * page / (1024 ** 3), 2)

free_gb = gb(meta.get("free"))
comp_gb = gb(meta.get("compressor_occ"))
if free_gb < 0.3 and comp_gb > 1.5:
    pressure = "Critical"
elif free_gb < 0.5 or comp_gb > 1.0:
    pressure = "Warn"
else:
    pressure = "OK"

def family_of(name):
    n = name
    if "Google Chrome" in n or "Chrome Helper" in n or "Chromium" in n:
        return "Chrome"
    if "Cursor" in n or "cursor" in n:
        return "Cursor"
    if "Code Helper" in n or "Visual Studio Code" in n or n == "Code":
        return "VS Code"
    if "Docker" in n or "com.docker" in n or "vpnkit" in n or "qemu-system" in n:
        return "Docker"
    if "Spotify" in n:
        return "Spotify"
    if "Safari" in n or "WebKit" in n:
        return "Safari"
    if "WindowServer" in n:
        return "WindowServer"
    if n == "kernel_task":
        return "kernel_task"
    return "Other"

families = {}
for line in ps_lines:
    line = line.strip()
    m = re.match(r"^(\d+)\s+(\d+)\s+(\S+)\s+(.*)$", line)
    if not m:
        continue
    rss = int(m.group(2))
    if rss <= 0:
        continue
    fam = family_of(m.group(4))
    kb, n = families.get(fam, (0, 0))
    families[fam] = (kb + rss, n + 1)

fam_rows = [
    {"family": f, "rss_kb": kb, "processes": n}
    for f, (kb, n) in families.items()
    if f != "Other"
]
fam_rows.sort(key=lambda x: x["rss_kb"], reverse=True)
fam_rows = fam_rows[:8]

def human_kb(kb):
    b = float(kb) * 1024.0
    for u in ("B", "KB", "MB", "GB", "TB"):
        if b < 1024 or u == "TB":
            if u == "B" or b >= 10:
                return "%d%s" % (int(b), u)
            return "%.1f%s" % (b, u)
        b /= 1024.0
    return "%sKB" % kb

actions = []
seen = set()

def add(cmd, why):
    if cmd in seen or len(actions) >= 3:
        return
    seen.add(cmd)
    actions.append({"command": cmd, "why": why})

Gi = 1024 ** 3
trash_b = int(meta.get("trash_bytes") or 0)
if trash_b >= Gi // 2:
    add("mac-health trash empty", "Trash is %s — safe reclaim" % meta.get("trash_human"))

disk_pct = meta.get("disk_pct") or ""
try:
    disk_pct_i = int(disk_pct) if disk_pct != "" else None
except ValueError:
    disk_pct_i = None

bloat_sorted = sorted(bloat, key=lambda x: x["bytes"], reverse=True)
cmd_for = {
    "homebrew-cache": "mac-health caches brew",
    "npm-cache": "mac-health caches npm",
    "composer-cache": "mac-health caches composer",
    "logs": "mac-health caches logs",
    "cursor-support": "mac-health caches cursor",
    "code-support": "mac-health caches code",
    "chrome-cache": "mac-health caches chrome",
    "docker-containers": "mac-health docker prune images --dry-run",
    "trash": "mac-health trash empty",
}

for item in bloat_sorted:
    if item["bytes"] < Gi:
        continue
    key = item["key"]
    if key in ("all-caches", "xcode-archives", "core-simulator"):
        continue
    if key == "xcode-derived":
        add("mac-health xcode clean-derived", "DerivedData ~%s" % item["human"])
        continue
    cmd = cmd_for.get(key)
    if not cmd:
        continue
    add(cmd, "%s ~%s" % (key, item["human"]))

if pressure in ("Warn", "Critical"):
    for fr in fam_rows[:3]:
        if fr["rss_kb"] < 1500000:
            continue
        fam = fr["family"]
        h = human_kb(fr["rss_kb"])
        if fam == "Chrome":
            add("mac-health caches chrome", "Chrome family ~%s" % h)
        elif fam == "Cursor":
            add("mac-health caches cursor", "Cursor family ~%s" % h)
        elif fam == "VS Code":
            add("mac-health caches code", "VS Code family ~%s" % h)
        elif fam == "Docker":
            add("mac-health docker quit", "Docker family ~%s (frees RAM; no disk delete)" % h)
        elif fam == "Spotify":
            add("mac-health caches spotify", "Spotify family ~%s" % h)

if disk_pct_i is not None and disk_pct_i >= 75 and len(actions) < 3:
    add("mac-health disk bloat", "Data volume at %s%% — review fat paths" % disk_pct_i)

for item in bloat_sorted[:5]:
    if item["key"] in ("core-simulator", "xcode-archives") and item["bytes"] >= Gi:
        add("mac-health xcode", "Large Simulator/Archives — inspect then clean manually")
        break

if not actions:
    add("mac-health memory", "RAM looks fine — dig into processes if needed")
    if disk_pct_i is not None and disk_pct_i >= 60:
        add("mac-health disk bloat", "Optional: review known bloat paths")

phys = int(meta.get("phys_bytes") or 0)
doc = {
    "command": "analyze",
    "memory": {
        "physical_bytes": phys,
        "physical_gb": int(round(phys / (1024 ** 3))) if phys else None,
        "free_gb": free_gb,
        "active_gb": gb(meta.get("active")),
        "inactive_gb": gb(meta.get("inactive")),
        "wired_gb": gb(meta.get("wired")),
        "compressor_occupied_gb": comp_gb,
        "pressure_heuristic": pressure,
    },
    "disk": {
        "role": meta.get("disk_role") or None,
        "mounted_on": meta.get("disk_mount") or None,
        "used_gi": float(meta["disk_used_gi"]) if meta.get("disk_used_gi") else None,
        "free_gi": float(meta["disk_free_gi"]) if meta.get("disk_free_gi") else None,
        "total_gi": float(meta["disk_total_gi"]) if meta.get("disk_total_gi") else None,
        "capacity": meta.get("disk_capacity") or None,
        "capacity_percent": disk_pct_i,
        "status": meta.get("disk_status") or None,
    },
    "trash": {
        "bytes": trash_b,
        "human": meta.get("trash_human") or "—",
    },
    "families": [
        {
            "family": fr["family"],
            "processes": fr["processes"],
            "rss_kb": fr["rss_kb"],
            "rss_human": human_kb(fr["rss_kb"]),
        }
        for fr in fam_rows
    ],
    "notable_bloat": [x for x in bloat_sorted if x["bytes"] >= Gi][:8],
    "actions": actions,
}
print(json.dumps(doc, indent=2, ensure_ascii=False))
'
  )"

  if mh_json_mode; then
    print -r -- "$raw"
    return 0
  fi

  print -r -- "$raw" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
m = doc["memory"]
d = doc["disk"]
print()
print("==> Memory")
phys = m.get("physical_gb")
print("  Physical:     %s GB" % (phys if phys is not None else "?"))
print("  Free:         %.2f GB" % (m.get("free_gb") or 0))
print("  Active:       %.2f GB" % (m.get("active_gb") or 0))
print("  Wired:        %.2f GB" % (m.get("wired_gb") or 0))
print("  Compressor:   %.2f GB" % (m.get("compressor_occupied_gb") or 0))
print("  Pressure:     %s" % m.get("pressure_heuristic"))
print()
print("==> Disk (Data)")
if d.get("mounted_on"):
    print("  Mount:        %s" % d.get("mounted_on"))
    print("  Used / Free:  %s / %s Gi" % (d.get("used_gi"), d.get("free_gi")))
    print("  Capacity:     %s  (%s)" % (d.get("capacity"), d.get("status")))
else:
    print("  (unavailable)")
print()
print("==> Trash")
print("  %s" % doc["trash"].get("human"))
print()
print("==> Top families")
if not doc.get("families"):
    print("  (no process list)")
else:
    for fr in doc["families"][:6]:
        print("  %-12s %5d procs  %s" % (fr["family"], fr["processes"], fr["rss_human"]))
print()
nb = doc.get("notable_bloat") or []
print("==> Notable bloat (>=1 Gi)")
if not nb:
    print("  (none over 1 Gi in known list)")
else:
    for x in nb[:6]:
        print("  %-18s %10s" % (x["key"], x["human"]))
print()
print("==> Suggested next (max 3)")
for i, a in enumerate(doc.get("actions") or [], 1):
    print("  %d. %s" % (i, a["command"]))
    print("     %s" % a["why"])
'
  mh_ok "Analyze complete (inspect only)"
}
