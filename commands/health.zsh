# cmd: health — system check (memory, disk, heavy paths)

mh_cmd_health() {
  mh_section "Hardware / OS"
  system_profiler SPHardwareDataType 2>/dev/null | grep -E 'Model Name|Chip|Memory:' || true
  sw_vers

  mh_section "Memory (vm_stat)"
  local page_size free active inactive wired compressor_occ compressor_stored
  page_size="$(pagesize 2>/dev/null || print 16384)"
  free="$(vm_stat | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')"
  active="$(vm_stat | awk '/Pages active/ {gsub(/\./,"",$3); print $3}')"
  inactive="$(vm_stat | awk '/Pages inactive/ {gsub(/\./,"",$3); print $3}')"
  wired="$(vm_stat | awk '/Pages wired/ {gsub(/\./,"",$4); print $4}')"
  compressor_occ="$(vm_stat | awk '/Pages occupied by compressor/ {gsub(/\./,"",$5); print $5}')"
  compressor_stored="$(vm_stat | awk '/Pages stored in compressor/ {gsub(/\./,"",$5); print $5}')"

  python3 - "$page_size" "$free" "$active" "$inactive" "$wired" "$compressor_occ" "$compressor_stored" <<'PY'
import sys
page = int(sys.argv[1])
vals = [int(x or 0) for x in sys.argv[2:]]
labels = ["Free", "Active", "Inactive", "Wired", "Compressor occupied", "Stored in compressor"]
for label, pages in zip(labels, vals):
    print(f"  {label:22s} {pages * page / (1024**3):6.2f} GB")
PY

  print
  sysctl vm.swapusage 2>/dev/null || true
  memory_pressure 2>/dev/null | tail -8 || true

  mh_section "Disk"
  df -h / /System/Volumes/Data 2>/dev/null || df -h /

  mh_section "Heavy paths"
  local -a paths=(
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
  local p
  for p in "${paths[@]}"; do
    printf "  %-55s %s\n" "$p" "$(mh_human_size "$p")"
  done

  mh_section "Top memory processes (if permitted)"
  if ps -Arc -o %mem,%cpu,rss,comm 2>/dev/null | head -1 >/dev/null; then
    ps -Arc -o %mem,%cpu,rss,comm 2>/dev/null | sort -nr -k1 | head -12
  else
    mh_warn "Process list restricted — open Activity Monitor → Memory"
  fi

  mh_section "LaunchAgents (user)"
  if [[ -d "$MH_LAUNCH_AGENTS" ]]; then
    ls -1 "$MH_LAUNCH_AGENTS" 2>/dev/null || true
  fi

  mh_ok "Health check complete"
}
