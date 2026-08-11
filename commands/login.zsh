# cmd: login — launch agents / login items inspection

mh_cmd_login_usage() {
  cat <<'EOF'
Usage: mac-health login <action>

Actions:
  list      Show user LaunchAgents + Login Items
  checkpoint  Show Check Point related agents (common CPU hog)
EOF
}

mh_cmd_login_list() {
  local -a agents=()
  if [[ -d "$MH_LAUNCH_AGENTS" ]]; then
    local f
    for f in "$MH_LAUNCH_AGENTS"/*(N); do
      agents+=("${f:t}")
    done
  fi

  local items_raw items_ok=0
  items_raw="$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null)" && items_ok=1

  if mh_json_mode; then
    {
      print "dir=${MH_LAUNCH_AGENTS}"
      print "items_ok=${items_ok}"
      print -r -- "===agents==="
      printf '%s\n' "${agents[@]}"
      print -r -- "===items==="
      if (( items_ok )) && [[ -n "$items_raw" ]]; then
        # osascript returns comma-separated names
        print -r -- "$items_raw" | tr ',' '\n' | sed 's/^ *//;s/ *$//'
      fi
    } | python3 -c '
import json, sys
meta = {}
agents = []
items = []
section = "meta"
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "===agents===":
        section = "agents"
        continue
    if line == "===items===":
        section = "items"
        continue
    if section == "meta":
        if "=" in line:
            k, v = line.split("=", 1)
            meta[k] = v
    elif section == "agents":
        if line:
            agents.append(line)
    elif section == "items":
        if line:
            items.append(line)
doc = {
    "command": "login",
    "action": "list",
    "launch_agents_dir": meta.get("dir"),
    "launch_agents": agents,
    "login_items_available": meta.get("items_ok") == "1",
    "login_items": items,
}
print(json.dumps(doc, indent=2, ensure_ascii=False))
'
    return 0
  fi

  mh_section "LaunchAgents ($MH_LAUNCH_AGENTS)"
  if [[ -d "$MH_LAUNCH_AGENTS" ]]; then
    ls -la "$MH_LAUNCH_AGENTS"
  else
    mh_warn "No LaunchAgents directory"
  fi

  mh_section "Login Items (System Events)"
  if (( items_ok )); then
    print -r -- "$items_raw"
  else
    mh_warn "Could not read login items (permissions?)"
  fi
}

mh_cmd_login_checkpoint() {
  local -a found=()
  local f
  for f in "$MH_LAUNCH_AGENTS"/com.checkpoint.*(.N); do
    found+=("$f")
  done

  if mh_json_mode; then
    {
      print "count=${#found}"
      print -r -- "===agents==="
      printf '%s\n' "${found[@]}"
    } | python3 -c '
import json, sys
meta = {}
agents = []
section = "meta"
for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line == "===agents===":
        section = "agents"
        continue
    if section == "meta":
        if "=" in line:
            k, v = line.split("=", 1)
            meta[k] = v
    elif section == "agents":
        if line:
            agents.append(line)
doc = {
    "command": "login",
    "action": "checkpoint",
    "count": int(meta.get("count") or 0),
    "agents": agents,
}
print(json.dumps(doc, indent=2, ensure_ascii=False))
'
    return 0
  fi

  mh_section "Check Point agents"
  if (( ${#found} == 0 )); then
    mh_ok "No Check Point LaunchAgents found"
  else
    mh_warn "Found Check Point agents. Disable only if you do not need the VPN:"
    for f in "${found[@]}"; do
      print "  $f"
    done
    print "  launchctl bootout gui/\$(id -u) ~/Library/LaunchAgents/com.checkpoint.cshell.plist"
    print "  # or move the plist out of LaunchAgents"
  fi
}

mh_cmd_login() {
  local action="${1:-list}"
  case "$action" in
    -h|--help|help) mh_cmd_login_usage ;;
    list) mh_cmd_login_list ;;
    checkpoint|cp) mh_cmd_login_checkpoint ;;
    *)
      mh_err "Unknown login action: $action"
      mh_cmd_login_usage
      return 1
      ;;
  esac
}
