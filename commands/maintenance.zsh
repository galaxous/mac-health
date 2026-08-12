# cmd: maintenance — weekly / monthly guided routes + inspect report

mh_cmd_maintenance_usage() {
  cat <<'EOF'
Usage: mac-health maintenance <action>

Actions:
  weekly    Light route: analyze → optional trash / brew / logs / docker prune images
  monthly   Heavier guided route: report → brew/npm/composer → docker prune images → app caches
  report    Size report only (caches list + docker status; no deletes)

JSON:
  report / weekly are inspect-oriented (weekly embeds analyze; no mutations).
  monthly stays interactive (human); use report --json for automation.

Examples:
  mac-health maintenance weekly
  mac-health maintenance monthly
  mac-health --json maintenance weekly
  mac-health --json maintenance report
EOF
}

mh_cmd_maintenance_report() {
  if mh_json_mode; then
    {
      print '===CACHES==='
      mh_cmd_caches_list
      print '===DOCKER==='
      mh_cmd_docker_status
    } | python3 -c '
import json, sys
chunks = {"caches": [], "docker": []}
cur = None
buf = []
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "===CACHES===":
        if cur and buf:
            chunks[cur] = "".join(buf)
        cur = "caches"
        buf = []
        continue
    if line == "===DOCKER===":
        if cur and buf:
            chunks[cur] = "".join(buf)
        cur = "docker"
        buf = []
        continue
    if cur is not None:
        buf.append(raw)
if cur and buf:
    chunks[cur] = "".join(buf)
doc = {
    "command": "maintenance",
    "action": "report",
    "caches": json.loads(chunks["caches"]) if chunks.get("caches") else None,
    "docker": json.loads(chunks["docker"]) if chunks.get("docker") else None,
}
print(json.dumps(doc, indent=2, ensure_ascii=False))
'
    return 0
  fi

  mh_section "Maintenance size report"
  mh_cmd_caches_list
  print
  mh_cmd_docker_status
}

# Light weekly: advice first, then optional safe cleanups (always confirm).
mh_cmd_maintenance_weekly() {
  if mh_json_mode; then
    {
      print '===ANALYZE==='
      mh_cmd_analyze
      print '===TRASH==='
      mh_cmd_trash_status
    } | python3 -c '
import json, sys
chunks = {"analyze": "", "trash": ""}
cur = None
buf = []
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "===ANALYZE===":
        if cur and buf:
            chunks[cur] = "".join(buf)
        cur = "analyze"
        buf = []
        continue
    if line == "===TRASH===":
        if cur and buf:
            chunks[cur] = "".join(buf)
        cur = "trash"
        buf = []
        continue
    if cur is not None:
        buf.append(raw)
if cur and buf:
    chunks[cur] = "".join(buf)
analyze = json.loads(chunks["analyze"]) if chunks.get("analyze") else None
trash = json.loads(chunks["trash"]) if chunks.get("trash") else None
actions = (analyze or {}).get("actions") or []
doc = {
    "command": "maintenance",
    "action": "weekly",
    "analyze": analyze,
    "trash": trash,
    "suggested": actions,
    "note": "Inspect only in --json. Run suggested commands explicitly (with -y if destructive).",
}
print(json.dumps(doc, indent=2, ensure_ascii=False))
'
    return 0
  fi

  mh_section "Weekly maintenance (light)"
  mh_log "Step 1/5 — analyze (inspect)"
  mh_cmd_analyze

  mh_log "Step 2/5 — Trash"
  mh_cmd_trash_status
  if mh_confirm "Empty Trash now?"; then
    # already confirmed once; avoid double prompt
    local MH_YES_BAK="${MH_YES:-0}"
    MH_YES=1
    mh_cmd_trash_empty || true
    MH_YES="$MH_YES_BAK"
  fi

  mh_log "Step 3/5 — Homebrew"
  if mh_confirm "Run brew cleanup -s?"; then
    mh_cmd_caches_brew || true
  fi

  mh_log "Step 4/5 — Old logs (>14 days)"
  if mh_confirm "Delete Library/Logs files older than 14 days?"; then
    local MH_YES_BAK="${MH_YES:-0}"
    MH_YES=1
    mh_cmd_caches_logs --older 14 || true
    MH_YES="$MH_YES_BAK"
  fi

  mh_log "Step 5/5 — Docker unused images"
  if mh_confirm "Preview unused Docker images (dry-run)?"; then
    mh_cmd_docker_prune images --dry-run || true
    if mh_confirm "REMOVE unused images now? (volumes kept)"; then
      mh_cmd_docker_images || true
    fi
  fi

  mh_ok "Weekly route finished — for heavier cleanup: mac-health maintenance monthly"
}

mh_cmd_maintenance_monthly() {
  mh_section "Monthly maintenance route"
  mh_log "Step 1/5 — size report"
  mh_cmd_maintenance_report

  mh_log "Step 2/5 — Homebrew"
  if mh_confirm "Run brew cleanup -s?"; then
    mh_cmd_caches_brew
  fi

  mh_log "Step 3/5 — npm + composer"
  if mh_confirm "Clean npm + composer caches?"; then
    mh_cmd_caches_npm
    mh_cmd_caches_composer
  fi

  mh_log "Step 4/5 — Docker prune images"
  if mh_confirm "REMOVE unused Docker images with: docker prune images? (volumes kept)"; then
    mh_cmd_docker_images
  fi

  mh_log "Step 5/5 — App caches (spotify/chrome/cursor)"
  if mh_confirm "Clean app caches? (quit those apps first)"; then
    mh_cmd_caches_spotify || true
    mh_cmd_caches_chrome || true
    mh_cmd_caches_cursor || true
  fi

  mh_ok "Monthly maintenance route finished"
}

mh_cmd_maintenance() {
  local action="${1:-weekly}"
  [[ $# -gt 0 ]] && shift
  case "$action" in
    -h|--help|help) mh_cmd_maintenance_usage ;;
    weekly|light) mh_cmd_maintenance_weekly "$@" ;;
    monthly|run) mh_cmd_maintenance_monthly "$@" ;;
    report) mh_cmd_maintenance_report "$@" ;;
    *)
      mh_err "Unknown maintenance action: $action"
      mh_cmd_maintenance_usage
      return 1
      ;;
  esac
}
