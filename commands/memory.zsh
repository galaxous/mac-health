# cmd: memory — detailed RAM usage (system + top processes + app families)

mh_cmd_memory_usage() {
  cat <<'EOF'
Usage: mac-health memory [--top <n>] [--json]

Aliases: mem, ram

Shows:
  - System memory (vm_stat, swap, pressure)
  - Top processes by RSS
  - App-family rollups (Chrome helpers counted as one family)
  - Short hints when a family is heavy

Flags:
  --top <n>   Number of processes to list (default: 15)
  --json      Machine-readable JSON on stdout (also: mac-health --json memory)
  -h, --help  This help
EOF
}

mh_memory_human_kb() {
  local kb="${1:-0}"
  /usr/bin/awk -v k="$kb" 'BEGIN {
    b = k * 1024
    if (b < 1024) { printf "%dB", b; exit }
    split("KB MB GB TB", u, " ")
    n = b; i = 0
    while (n >= 1024 && i < 4) { n /= 1024; i++ }
    if (n >= 10 || i == 0) printf "%.0f%s", n, u[i]
    else printf "%.1f%s", n, u[i]
  }'
}

mh_memory_family_of() {
  # $1 = process command/name → print family label
  local name="$1"
  case "$name" in
    *Google\ Chrome*|*Chrome\ Helper*|*Chromium*) print "Chrome" ;;
    *Cursor*|*cursor*) print "Cursor" ;;
    *Code\ Helper*|*Visual\ Studio\ Code*|*/Code.app*|Code) print "VS Code" ;;
    *Docker*|*com.docker*|*vpnkit*|*qemu-system*|*Docker\ Desktop*) print "Docker" ;;
    *Spotify*) print "Spotify" ;;
    *Safari*|*WebKit*|*com.apple.WebKit*) print "Safari" ;;
    *WindowServer*) print "WindowServer" ;;
    kernel_task) print "kernel_task" ;;
    *node*|*Node*) print "Node" ;;
    *php*|*PHP*) print "PHP" ;;
    *) print "Other" ;;
  esac
}

mh_memory_short_comm() {
  local c="$1"
  # Prefer last path component when absolute
  if [[ "$c" == /* ]]; then
    c="${c:t}"
  fi
  if (( ${#c} > 72 )); then
    print -r -- "${c[1,69]}..."
  else
    print -r -- "$c"
  fi
}

mh_cmd_memory() {
  local top_n=15

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help|help)
        mh_cmd_memory_usage
        return 0
        ;;
      --top)
        if [[ -z "${2:-}" || ! "${2}" =~ ^[1-9][0-9]*$ ]]; then
          mh_err "--top requires a positive integer"
          return 1
        fi
        top_n="$2"
        shift 2
        ;;
      --top=*)
        local t="${1#*=}"
        if [[ ! "$t" =~ ^[1-9][0-9]*$ ]]; then
          mh_err "--top requires a positive integer"
          return 1
        fi
        top_n="$t"
        shift
        ;;
      *)
        mh_err "Unknown flag: $1"
        mh_cmd_memory_usage
        return 1
        ;;
    esac
  done

  local page_size free active inactive wired compressor_occ compressor_stored
  page_size="$(pagesize 2>/dev/null || print 16384)"
  free="$(vm_stat | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')"
  active="$(vm_stat | awk '/Pages active/ {gsub(/\./,"",$3); print $3}')"
  inactive="$(vm_stat | awk '/Pages inactive/ {gsub(/\./,"",$3); print $3}')"
  wired="$(vm_stat | awk '/Pages wired/ {gsub(/\./,"",$4); print $4}')"
  compressor_occ="$(vm_stat | awk '/Pages occupied by compressor/ {gsub(/\./,"",$5); print $5}')"
  compressor_stored="$(vm_stat | awk '/Pages stored in compressor/ {gsub(/\./,"",$5); print $5}')"

  local phys_bytes phys_gb
  phys_bytes="$(sysctl -n hw.memsize 2>/dev/null || print 0)"
  if [[ -z "$phys_bytes" || "$phys_bytes" == "0" ]]; then
    phys_bytes="$(python3 - "$page_size" "$free" "$active" "$inactive" "$wired" "$compressor_occ" <<'PY'
import sys
page = int(sys.argv[1])
pages = sum(int(x or 0) for x in sys.argv[2:])
print(pages * page)
PY
)"
  fi
  phys_gb="$(/usr/bin/awk -v b="$phys_bytes" 'BEGIN { printf "%.0f", (b > 0 ? b : 0) / (1024*1024*1024) }')"

  local pressure_level
  pressure_level="$(python3 - "$page_size" "$free" "$compressor_occ" <<'PY'
import sys
page = int(sys.argv[1])
free_gb = int(sys.argv[2] or 0) * page / (1024**3)
comp_gb = int(sys.argv[3] or 0) * page / (1024**3)
if free_gb < 0.3 and comp_gb > 1.5:
    print("Critical")
elif free_gb < 0.5 or comp_gb > 1.0:
    print("Warn")
else:
    print("OK")
PY
)"

  local swap_line pressure_out
  swap_line="$(sysctl vm.swapusage 2>/dev/null || true)"
  pressure_out="$(memory_pressure 2>/dev/null | tail -6 || true)"

  local ps_out
  ps_out="$(/bin/ps -axo pid=,rss=,%mem=,comm= 2>/dev/null)" || ps_out=""

  local -A family_kb family_procs
  family_kb=()
  family_procs=()
  local -a top_proc_rows=()
  local listed_kb=0
  local line pid rss pct rest comm fam

  if [[ -n "$ps_out" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      pid="${line##[[:space:]]#}"
      pid="${pid%%[[:space:]]*}"
      rest="${line##[[:space:]]#${pid}[[:space:]]#}"
      rss="${rest%%[[:space:]]*}"
      rest="${rest##[[:space:]]#${rss}[[:space:]]#}"
      pct="${rest%%[[:space:]]*}"
      comm="${rest##[[:space:]]#${pct}[[:space:]]#}"
      [[ -z "$rss" || "$rss" == "0" ]] && continue

      fam="$(mh_memory_family_of "$comm")"
      family_kb[$fam]=$(( ${family_kb[$fam]:-0} + rss ))
      family_procs[$fam]=$(( ${family_procs[$fam]:-0} + 1 ))
    done <<< "$ps_out"

    local -a top_lines
    top_lines=("${(@f)$(printf "%s\n" "$ps_out" | /usr/bin/sort -nr -k2 | /usr/bin/head -n "$top_n")}")
    for line in "${top_lines[@]}"; do
      [[ -z "$line" ]] && continue
      pid="${line##[[:space:]]#}"
      pid="${pid%%[[:space:]]*}"
      rest="${line##[[:space:]]#${pid}[[:space:]]#}"
      rss="${rest%%[[:space:]]*}"
      rest="${rest##[[:space:]]#${rss}[[:space:]]#}"
      pct="${rest%%[[:space:]]*}"
      comm="${rest##[[:space:]]#${pct}[[:space:]]#}"
      listed_kb=$(( listed_kb + rss ))
      top_proc_rows+=("${pid}|${rss}|${pct}|${comm}")
    done
  fi

  local -a fam_rows=()
  for fam in ${(k)family_kb}; do
    [[ "$fam" == "Other" ]] && continue
    fam_rows+=("${family_kb[$fam]}|${family_procs[$fam]}|$fam")
  done
  local -a fam_sorted
  fam_sorted=("${(@f)$(printf '%s\n' "${fam_rows[@]}" | /usr/bin/sort -t'|' -nr -k1)}")

  local -a hints=()
  local chrome_kb="${family_kb[Chrome]:-0}"
  local cursor_kb="${family_kb[Cursor]:-0}"
  local docker_kb="${family_kb[Docker]:-0}"
  local code_kb="${family_kb[VS Code]:-0}"
  if (( chrome_kb > 2097152 )); then
    hints+=("Chrome family ~$(mh_memory_human_kb "$chrome_kb") — close tabs or: mac-health caches chrome")
  fi
  if (( cursor_kb > 2097152 )); then
    hints+=("Cursor family ~$(mh_memory_human_kb "$cursor_kb") — fewer windows or: mac-health caches cursor")
  fi
  if (( docker_kb > 1048576 )); then
    hints+=("Docker family ~$(mh_memory_human_kb "$docker_kb") — mac-health docker status / docker quit")
  fi
  if (( code_kb > 1572864 )); then
    hints+=("VS Code family ~$(mh_memory_human_kb "$code_kb") — mac-health caches code (or code-deep)")
  fi

  if mh_json_mode; then
    {
      print "top_n=${top_n}"
      print "page_size=${page_size}"
      print "phys_bytes=${phys_bytes}"
      print "phys_gb=${phys_gb}"
      print "free=${free}"
      print "active=${active}"
      print "inactive=${inactive}"
      print "wired=${wired}"
      print "compressor_occ=${compressor_occ}"
      print "compressor_stored=${compressor_stored}"
      print "pressure_level=${pressure_level}"
      print "listed_kb=${listed_kb}"
      print "ps_available=$([[ -n $ps_out ]] && print 1 || print 0)"
      print "swap=${swap_line}"
      print -r -- "===processes==="
      printf '%s\n' "${top_proc_rows[@]}"
      print -r -- "===families==="
      local kb procs
      local shown=0
      for line in "${fam_sorted[@]}"; do
        [[ -z "$line" ]] && continue
        kb="${line%%|*}"
        rest="${line#*|}"
        procs="${rest%%|*}"
        fam="${rest#*|}"
        print "${fam}|${procs}|${kb}"
        shown=$(( shown + 1 ))
        (( shown >= 12 )) && break
      done
      if [[ -n "${family_kb[Other]:-}" ]]; then
        print "Other|${family_procs[Other]}|${family_kb[Other]}"
      fi
      print -r -- "===hints==="
      printf '%s\n' "${hints[@]}"
      print -r -- "===pressure==="
      print -r -- "$pressure_out"
    } | python3 -c '
import json, sys

def gb(pages, page):
    return round(int(pages or 0) * int(page) / (1024**3), 2)

meta = {}
processes = []
families = []
hints = []
pressure_lines = []
section = "meta"
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "===processes===":
        section = "processes"
        continue
    if line == "===families===":
        section = "families"
        continue
    if line == "===hints===":
        section = "hints"
        continue
    if line == "===pressure===":
        section = "pressure"
        continue
    if section == "meta":
        if "=" in line:
            k, v = line.split("=", 1)
            meta[k] = v
    elif section == "processes":
        if not line:
            continue
        pid, rss, pct, comm = line.split("|", 3)
        processes.append({
            "pid": int(pid),
            "rss_kb": int(rss),
            "mem_percent": pct,
            "command": comm,
        })
    elif section == "families":
        if not line:
            continue
        fam, procs, kb = line.split("|", 2)
        families.append({
            "family": fam,
            "processes": int(procs),
            "rss_kb": int(kb),
        })
    elif section == "hints":
        if line:
            hints.append(line)
    elif section == "pressure":
        pressure_lines.append(line)

page = int(meta.get("page_size") or 16384)
doc = {
    "command": "memory",
    "top_n": int(meta.get("top_n") or 15),
    "physical_bytes": int(meta.get("phys_bytes") or 0),
    "physical_gb": int(float(meta.get("phys_gb") or 0)),
    "vm": {
        "page_size": page,
        "free_gb": gb(meta.get("free"), page),
        "active_gb": gb(meta.get("active"), page),
        "inactive_gb": gb(meta.get("inactive"), page),
        "wired_gb": gb(meta.get("wired"), page),
        "compressor_occupied_gb": gb(meta.get("compressor_occ"), page),
        "compressor_stored_gb": gb(meta.get("compressor_stored"), page),
        "pressure_heuristic": meta.get("pressure_level") or "OK",
        "swap": (meta.get("swap") or "").strip() or None,
        "pressure_raw": "\n".join(pressure_lines).strip() or None,
    },
    "ps_available": meta.get("ps_available") == "1",
    "listed_rss_kb": int(meta.get("listed_kb") or 0),
    "processes": processes,
    "families": families,
    "hints": hints,
}
print(json.dumps(doc, indent=2, ensure_ascii=False))
'
    return 0
  fi

  mh_section "System memory"
  printf "  Physical RAM: %s GB\n" "${phys_gb:-?}"

  python3 - "$page_size" "$free" "$active" "$inactive" "$wired" "$compressor_occ" "$compressor_stored" <<'PY'
import sys
page = int(sys.argv[1])
vals = [int(x or 0) for x in sys.argv[2:]]
labels = ["Free", "Active", "Inactive", "Wired", "Compressor occupied", "Stored in compressor"]
for label, pages in zip(labels, vals):
    print(f"  {label:22s} {pages * page / (1024**3):6.2f} GB")
PY
  printf "  Pressure (heuristic): %s\n" "$pressure_level"

  print
  [[ -n "$swap_line" ]] && print "$swap_line"
  [[ -n "$pressure_out" ]] && print "$pressure_out"

  mh_section "Top processes by RSS (top ${top_n})"
  if [[ -z "$ps_out" ]]; then
    mh_warn "Process list restricted — open Activity Monitor → Memory"
    mh_warn "Or run from Terminal.app (Full Disk Access may be required)."
    return 0
  fi

  printf "  %-10s %6s %7s  %s\n" "RSS" "%MEM" "PID" "COMMAND"
  printf "  %-10s %6s %7s  %s\n" "----------" "------" "-------" "-------"

  local mem_h
  for line in "${top_proc_rows[@]}"; do
    pid="${line%%|*}"
    rest="${line#*|}"
    rss="${rest%%|*}"
    rest="${rest#*|}"
    pct="${rest%%|*}"
    comm="${rest#*|}"
    mem_h="$(mh_memory_human_kb "$rss")"
    printf "  %-10s %6s %7s  %s\n" "$mem_h" "$pct" "$pid" "$(mh_memory_short_comm "$comm")"
  done

  print
  mh_log "Listed RSS total: $(mh_memory_human_kb "$listed_kb") (of ${phys_gb}G physical)"

  mh_section "App families (aggregated RSS)"
  printf "  %-14s %6s  %s\n" "FAMILY" "PROCS" "RSS"
  printf "  %-14s %6s  %s\n" "--------------" "------" "----"

  local kb procs shown=0
  for line in "${fam_sorted[@]}"; do
    [[ -z "$line" ]] && continue
    kb="${line%%|*}"
    rest="${line#*|}"
    procs="${rest%%|*}"
    fam="${rest#*|}"
    printf "  %-14s %6s  %s\n" "$fam" "$procs" "$(mh_memory_human_kb "$kb")"
    shown=$(( shown + 1 ))
    (( shown >= 12 )) && break
  done
  if [[ -n "${family_kb[Other]:-}" ]]; then
    printf "  %-14s %6s  %s\n" "Other" "${family_procs[Other]}" "$(mh_memory_human_kb "${family_kb[Other]}")"
  fi

  mh_section "Hints"
  if (( ${#hints} == 0 )); then
    mh_ok "No heavy-family hints (thresholds: Chrome/Cursor 2G, Docker 1G, VS Code 1.5G)"
  else
    local h
    for h in "${hints[@]}"; do
      mh_warn "$h"
    done
  fi

  mh_ok "Memory report complete"
}
