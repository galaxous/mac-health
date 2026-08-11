# cmd: watch — live refresh (top/htop-style) for fast inspect commands

mh_cmd_watch_usage() {
  cat <<'EOF'
Usage: mac-health watch [memory] [--interval <sec>] [--top <n>]

Live in-place refresh (Ctrl+C to quit). Human UI only — no --json.

Redraws over the previous frame (no full-screen flash). Uses a fast
memory snapshot (skips memory_pressure / heavy footers).

Target (default: memory):
  memory|mem|ram   RAM pressure, top RSS, app families

Flags:
  -n, --interval <sec>   Pause after each frame (default: 2, min: 1)
  --top <n>              Top processes to list (default: 15)
  -h, --help             This help

Examples:
  mac-health watch
  mac-health watch memory --interval 1 --top 25
  mac-health watch -n 3 --top 20

Not supported: health (too slow — system_profiler / heavy paths).
EOF
}

# Paint a multi-line frame in-place (home → overwrite → clear tail).
mh_watch_paint() {
  local frame="$1"
  printf '\033[H'
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\033[K\n' "$line"
  done <<< "$frame"
  printf '\033[J'
}

# Fast memory snapshot → fixed layout stdout (one python; no mh_cmd_memory).
mh_watch_memory_frame() {
  local top_n="${1:-15}"
  local interval="${2:-2}"
  local stamp="${3:-}"

  TOP_N="$top_n" INTERVAL="$interval" STAMP="$stamp" python3 - <<'PY'
import os, re, subprocess, time

top_n = max(1, int(os.environ.get("TOP_N") or 15))
interval = os.environ.get("INTERVAL") or "2"
stamp = os.environ.get("STAMP") or time.strftime("%H:%M:%S")

def run(cmd):
    try:
        return subprocess.check_output(cmd, text=True, errors="replace")
    except Exception:
        return ""

def family_of(name: str) -> str:
    n = name
    if "Google Chrome" in n or "Chrome Helper" in n or "Chromium" in n:
        return "Chrome"
    if "Cursor" in n or "cursor" in n:
        return "Cursor"
    if "Code Helper" in n or "Visual Studio Code" in n or n.endswith("/Code") or n == "Code":
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
    if "node" in n or "Node" in n:
        return "Node"
    if "php" in n or "PHP" in n:
        return "PHP"
    return "Other"

def human_kb(kb: int) -> str:
    b = float(kb) * 1024.0
    for u in ("B", "KB", "MB", "GB", "TB"):
        if b < 1024 or u == "TB":
            if u == "B" or b >= 10:
                return f"{int(b)}{u}"
            return f"{b:.1f}{u}"
        b /= 1024.0
    return f"{kb}KB"

def short_comm(c: str, width: int = 48) -> str:
    if c.startswith("/"):
        c = c.rsplit("/", 1)[-1]
    if len(c) > width:
        return c[: width - 3] + "..."
    return c

page = 16384
try:
    page = int(subprocess.check_output(["pagesize"], text=True).strip() or "16384")
except Exception:
    pass

vm = run(["vm_stat"])
pages = {}
for key, pat in (
    ("free", r"Pages free:\s+(\d+)"),
    ("active", r"Pages active:\s+(\d+)"),
    ("inactive", r"Pages inactive:\s+(\d+)"),
    ("wired", r"Pages wired down:\s+(\d+)"),
    ("comp_occ", r"Pages occupied by compressor:\s+(\d+)"),
    ("comp_stored", r"Pages stored in compressor:\s+(\d+)"),
):
    m = re.search(pat, vm)
    pages[key] = int(m.group(1)) if m else 0

def gb(p):
    return pages[p] * page / (1024 ** 3)

free_gb, comp_gb = gb("free"), gb("comp_occ")
if free_gb < 0.3 and comp_gb > 1.5:
    pressure = "Critical"
elif free_gb < 0.5 or comp_gb > 1.0:
    pressure = "Warn"
else:
    pressure = "OK"

try:
    phys = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True).strip())
    phys_gb = phys / (1024 ** 3)
except Exception:
    phys_gb = 0.0

swap = run(["sysctl", "vm.swapusage"]).strip()

ps_out = run(["/bin/ps", "-axo", "pid=,rss=,%mem=,comm="])
procs = []
families = {}
for line in ps_out.splitlines():
    line = line.strip()
    if not line:
        continue
    m = re.match(r"^(\d+)\s+(\d+)\s+(\S+)\s+(.*)$", line)
    if not m:
        continue
    pid, rss, pct, comm = int(m.group(1)), int(m.group(2)), m.group(3), m.group(4)
    if rss <= 0:
        continue
    procs.append((rss, pct, pid, comm))
    fam = family_of(comm)
    kb, n = families.get(fam, (0, 0))
    families[fam] = (kb + rss, n + 1)

procs.sort(key=lambda x: x[0], reverse=True)
top = procs[:top_n]

fam_rows = [(kb, n, f) for f, (kb, n) in families.items() if f != "Other"]
fam_rows.sort(reverse=True)
other = families.get("Other")

lines = []
lines.append(f"mac-health watch memory  every {interval}s  {stamp}  (Ctrl+C quit)")
lines.append("─" * 72)
ram_s = f"{phys_gb:.0f}G" if phys_gb > 0 else "?"
lines.append(
    f"RAM {ram_s}  pressure {pressure:8s}  "
    f"free {free_gb:5.2f}  active {gb('active'):5.2f}  "
    f"wired {gb('wired'):5.2f}  comp {comp_gb:5.2f} G"
)
lines.append(
    f"inactive {gb('inactive'):5.2f}G   stored-in-comp {gb('comp_stored'):5.2f}G"
)
if swap:
    lines.append(swap.replace("vm.swapusage: ", "swap: "))
lines.append("")
lines.append(f"TOP RSS ({top_n})")
lines.append(f"  {'RSS':>8}  {'%MEM':>5}  {'PID':>7}  COMMAND")
if not top:
    lines.append("  (no process list — Full Disk Access / Terminal?)")
else:
    for rss, pct, pid, comm in top:
        lines.append(
            f"  {human_kb(rss):>8}  {pct:>5}  {pid:7d}  {short_comm(comm)}"
        )

lines.append("")
lines.append("FAMILIES")
lines.append(f"  {'FAMILY':<12}  {'PROCS':>5}  RSS")
shown = 0
for kb, n, fam in fam_rows:
    lines.append(f"  {fam:<12}  {n:5d}  {human_kb(kb)}")
    shown += 1
    if shown >= 10:
        break
if other:
    lines.append(f"  {'Other':<12}  {other[1]:5d}  {human_kb(other[0])}")

print("\n".join(lines))
PY
}

mh_cmd_watch() {
  local interval=2
  local target="memory"
  local top_n=15
  local saw_target=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help|help)
        mh_cmd_watch_usage
        return 0
        ;;
      -n|--interval)
        if [[ -z "${2:-}" || ! "${2}" =~ ^[1-9][0-9]*$ ]]; then
          mh_err "--interval requires a positive integer (seconds)"
          return 1
        fi
        interval="$2"
        shift 2
        ;;
      --interval=*)
        local iv="${1#*=}"
        if [[ ! "$iv" =~ ^[1-9][0-9]*$ ]]; then
          mh_err "--interval requires a positive integer (seconds)"
          return 1
        fi
        interval="$iv"
        shift
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
      memory|mem|ram)
        if (( saw_target )); then
          mh_err "Multiple watch targets: already ${target}"
          return 1
        fi
        target="memory"
        saw_target=1
        shift
        ;;
      health|check|checkhealth|caches|docker|login|projects|purge|maintenance)
        mh_err "'$1' is not a watch target (too slow or mutates state)"
        mh_err "Use: mac-health watch memory"
        return 1
        ;;
      *)
        mh_err "Unknown argument: $1"
        mh_cmd_watch_usage
        return 1
        ;;
    esac
  done

  if mh_json_mode; then
    mh_err "watch does not support --json (one-shot: mac-health memory --json)"
    return 1
  fi

  if [[ ! -t 1 ]]; then
    mh_err "watch needs a TTY (stdout is not a terminal)"
    return 1
  fi

  local _mh_watch_stop=0
  # Alternate screen + hide cursor (restore on exit — no scroll spam)
  printf '\033[?1049h\033[?25l\033[H\033[2J'
  trap '_mh_watch_stop=1' INT TERM
  trap 'printf "\033[?25h\033[?1049l"' EXIT

  local frame stamp
  while (( ! _mh_watch_stop )); do
    stamp="$(date '+%H:%M:%S')"
    case "$target" in
      memory)
        frame="$(mh_watch_memory_frame "$top_n" "$interval" "$stamp")" || frame="(frame failed)"
        ;;
      *)
        printf '\033[?25h\033[?1049l'
        trap - INT TERM EXIT
        mh_err "Unsupported watch target: ${target}"
        return 1
        ;;
    esac
    mh_watch_paint "$frame"
    (( _mh_watch_stop )) && break
    /bin/sleep "$interval"
  done

  trap - INT TERM EXIT
  printf '\033[?25h\033[?1049l'
  mh_ok "watch stopped"
  return 0
}
