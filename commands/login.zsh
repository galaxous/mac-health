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
  mh_section "LaunchAgents ($MH_LAUNCH_AGENTS)"
  if [[ -d "$MH_LAUNCH_AGENTS" ]]; then
    ls -la "$MH_LAUNCH_AGENTS"
  else
    mh_warn "No LaunchAgents directory"
  fi

  mh_section "Login Items (System Events)"
  osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null \
    || mh_warn "Could not read login items (permissions?)"
}

mh_cmd_login_checkpoint() {
  mh_section "Check Point agents"
  local found=0
  local f
  for f in "$MH_LAUNCH_AGENTS"/com.checkpoint.*(.N); do
    found=1
    print "  $f"
  done
  if (( ! found )); then
    mh_ok "No Check Point LaunchAgents found"
  else
    mh_warn "Found Check Point agents. Disable only if you do not need the VPN:"
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
