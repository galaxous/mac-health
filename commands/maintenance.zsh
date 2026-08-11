# cmd: maintenance — monthly / batch cleanup route

mh_cmd_maintenance_usage() {
  cat <<'EOF'
Usage: mac-health maintenance <action>

Actions:
  monthly   Guided monthly route: list → brew/npm/composer → docker soft → caches list
  report    Size report only (no deletes)
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

  mh_section "Monthly size report"
  mh_cmd_caches_list
  print
  mh_cmd_docker_status
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

  mh_log "Step 4/5 — Docker soft prune"
  if mh_confirm "Run docker soft prune? (daemon must be running)"; then
    mh_cmd_docker_soft
  fi

  mh_log "Step 5/5 — App caches (spotify/chrome/cursor)"
  if mh_confirm "Clean app caches? (quit those apps first)"; then
    local MH_YES_BAK="${MH_YES:-0}"
    # keep confirmations per-app via require_app_closed
    mh_cmd_caches_spotify || true
    mh_cmd_caches_chrome || true
    mh_cmd_caches_cursor || true
    MH_YES="$MH_YES_BAK"
  fi

  mh_ok "Monthly maintenance route finished"
}

mh_cmd_maintenance() {
  local action="${1:-monthly}"
  case "$action" in
    -h|--help|help) mh_cmd_maintenance_usage ;;
    monthly|run) mh_cmd_maintenance_monthly ;;
    report) mh_cmd_maintenance_report ;;
    *)
      mh_err "Unknown maintenance action: $action"
      mh_cmd_maintenance_usage
      return 1
      ;;
  esac
}
