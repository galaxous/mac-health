# cmd: health — system check (memory, disk, heavy paths)

mh_cmd_health() {
  local page_size free active inactive wired compressor_occ compressor_stored
  page_size="$(pagesize 2>/dev/null || print 16384)"
  free="$(vm_stat | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')"
  active="$(vm_stat | awk '/Pages active/ {gsub(/\./,"",$3); print $3}')"
  inactive="$(vm_stat | awk '/Pages inactive/ {gsub(/\./,"",$3); print $3}')"
  wired="$(vm_stat | awk '/Pages wired/ {gsub(/\./,"",$4); print $4}')"
  compressor_occ="$(vm_stat | awk '/Pages occupied by compressor/ {gsub(/\./,"",$5); print $5}')"
  compressor_stored="$(vm_stat | awk '/Pages stored in compressor/ {gsub(/\./,"",$5); print $5}')"

  local model chip memory_line product os_version build
  model="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/ {print $2; exit}')"
  chip="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip/ {print $2; exit}')"
  memory_line="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Memory:/ {print $2; exit}')"
  product="$(sw_vers -productName 2>/dev/null)"
  os_version="$(sw_vers -productVersion 2>/dev/null)"
  build="$(sw_vers -buildVersion 2>/dev/null)"

  local swap_line pressure_out
  swap_line="$(sysctl vm.swapusage 2>/dev/null || true)"
  pressure_out="$(memory_pressure 2>/dev/null | tail -8 || true)"

  local -a heavy_paths=(
    "$MH_CACHES"
    "$MH_CACHE_SPOTIFY"
    "$MH_CACHE_CHROME"
    "$MH_NPM_CACHE"
    "$MH_CURSOR_SUPPORT"
    "$MH_CODE_SUPPORT"
    "$MH_DOCKER_CONTAINERS"
    "$MH_DOCKER_HOME"
    "$MH_LOGS"
    "$MH_PROJECTS"
  )

  local -a agents=()
  if [[ -d "$MH_LAUNCH_AGENTS" ]]; then
    local f
    for f in "$MH_LAUNCH_AGENTS"/*(N); do
      agents+=("${f:t}")
    done
  fi

  if mh_json_mode; then
    {
      print -r -- "page_size=${page_size}"
      print -r -- "free=${free}"
      print -r -- "active=${active}"
      print -r -- "inactive=${inactive}"
      print -r -- "wired=${wired}"
      print -r -- "compressor_occ=${compressor_occ}"
      print -r -- "compressor_stored=${compressor_stored}"
      print -r -- "model=${model}"
      print -r -- "chip=${chip}"
      print -r -- "memory_line=${memory_line}"
      print -r -- "product=${product}"
      print -r -- "version=${os_version}"
      print -r -- "build=${build}"
      print -r -- "swap=${swap_line}"
      print -r -- "===paths==="
      local p
      for p in "${heavy_paths[@]}"; do
        print -r -- "${p}|$(mh_dir_size_bytes "$p")|$(mh_human_size "$p")"
      done
      print -r -- "===agents==="
      printf '%s\n' "${agents[@]}"
      print -r -- "===pressure==="
      print -r -- "$pressure_out"
      print -r -- "===df==="
      /bin/df -k / /System/Volumes/Data 2>/dev/null || /bin/df -k /
    } | python3 -c '
import json, sys

def gb(pages, page):
    return round(int(pages or 0) * int(page) / (1024**3), 2)

meta = {}
paths = []
agents = []
pressure_lines = []
df_rows = []
section = "meta"
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "===paths===":
        section = "paths"
        continue
    if line == "===agents===":
        section = "agents"
        continue
    if line == "===pressure===":
        section = "pressure"
        continue
    if line == "===df===":
        section = "df"
        continue
    if section == "meta":
        if "=" in line:
            k, v = line.split("=", 1)
            meta[k] = v
    elif section == "paths":
        if not line:
            continue
        parts = line.split("|", 2)
        if len(parts) == 3:
            paths.append({"path": parts[0], "bytes": int(parts[1] or 0), "human": parts[2]})
    elif section == "agents":
        if line:
            agents.append(line)
    elif section == "pressure":
        pressure_lines.append(line)
    elif section == "df":
        if line and not line.startswith("Filesystem"):
            cols = line.split()
            if len(cols) >= 6:
                df_rows.append({
                    "filesystem": cols[0],
                    "blocks_1k": int(cols[1]) if cols[1].isdigit() else cols[1],
                    "used_1k": int(cols[2]) if cols[2].isdigit() else cols[2],
                    "avail_1k": int(cols[3]) if cols[3].isdigit() else cols[3],
                    "capacity": cols[4],
                    "mounted_on": " ".join(cols[5:]),
                })

page = int(meta.get("page_size") or 16384)
doc = {
    "command": "health",
    "hardware": {
        "model": meta.get("model") or None,
        "chip": meta.get("chip") or None,
        "memory": meta.get("memory_line") or None,
    },
    "os": {
        "product": meta.get("product") or None,
        "version": meta.get("version") or None,
        "build": meta.get("build") or None,
    },
    "memory": {
        "page_size": page,
        "free_gb": gb(meta.get("free"), page),
        "active_gb": gb(meta.get("active"), page),
        "inactive_gb": gb(meta.get("inactive"), page),
        "wired_gb": gb(meta.get("wired"), page),
        "compressor_occupied_gb": gb(meta.get("compressor_occ"), page),
        "compressor_stored_gb": gb(meta.get("compressor_stored"), page),
        "swap": (meta.get("swap") or "").strip() or None,
        "pressure_raw": "\n".join(pressure_lines).strip() or None,
    },
    "disk": df_rows,
    "heavy_paths": paths,
    "launch_agents": agents,
}
print(json.dumps(doc, indent=2, ensure_ascii=False))
'
    return 0
  fi

  mh_section "Hardware / OS"
  [[ -n "$model" ]] && print "  Model Name: $model"
  [[ -n "$chip" ]] && print "  Chip: $chip"
  [[ -n "$memory_line" ]] && print "  Memory: $memory_line"
  sw_vers

  mh_section "Memory (vm_stat)"
  python3 - "$page_size" "$free" "$active" "$inactive" "$wired" "$compressor_occ" "$compressor_stored" <<'PY'
import sys
page = int(sys.argv[1])
vals = [int(x or 0) for x in sys.argv[2:]]
labels = ["Free", "Active", "Inactive", "Wired", "Compressor occupied", "Stored in compressor"]
for label, pages in zip(labels, vals):
    print(f"  {label:22s} {pages * page / (1024**3):6.2f} GB")
PY

  print
  [[ -n "$swap_line" ]] && print "$swap_line"
  [[ -n "$pressure_out" ]] && print "$pressure_out"

  mh_section "Disk"
  df -h / /System/Volumes/Data 2>/dev/null || df -h /

  mh_section "Heavy paths"
  local p
  for p in "${heavy_paths[@]}"; do
    printf "  %-55s %s\n" "$p" "$(mh_human_size "$p")"
  done

  mh_section "Top memory processes"
  mh_log "For detailed RSS + app families: mac-health memory"

  mh_section "LaunchAgents (user)"
  if (( ${#agents} )); then
    printf '  %s\n' "${agents[@]}"
  fi

  mh_ok "Health check complete"
}
