# cmd: trash — inspect / empty ~/.Trash

mh_cmd_trash_usage() {
  cat <<'EOF'
Usage: mac-health trash [status|empty] [--json] [-y]

Actions:
  status   Show Trash size (default)
  empty    Empty ~/.Trash (confirm, or -y)

Examples:
  mac-health trash
  mac-health trash empty
  mac-health -y trash empty
  mac-health --json trash status
EOF
}

mh_cmd_trash_status() {
  local bytes human
  bytes="$(mh_dir_size_bytes "$MH_TRASH")"
  human="$(mh_human_size "$MH_TRASH")"

  if mh_json_mode; then
    MH_JSON_BYTES="$bytes" MH_JSON_HUMAN="$human" MH_JSON_PATH="$MH_TRASH" mh_json_doc <<'PY'
import os
doc = {
    "command": "trash",
    "action": "status",
    "path": os.environ["MH_JSON_PATH"],
    "bytes": int(os.environ.get("MH_JSON_BYTES") or 0),
    "human": os.environ.get("MH_JSON_HUMAN") or "—",
}
PY
    return 0
  fi

  mh_section "Trash"
  printf "  %-20s %s\n" "Path" "$MH_TRASH"
  printf "  %-20s %s\n" "Size" "$human"
  if [[ ! -d "$MH_TRASH" ]]; then
    mh_warn "Trash folder missing"
  elif (( bytes == 0 )); then
    mh_ok "Trash is empty"
  else
    mh_log "Empty with: mac-health trash empty"
  fi
}

mh_cmd_trash_empty() {
  if [[ ! -d "$MH_TRASH" ]]; then
    mh_warn "Trash folder missing: $MH_TRASH"
    if mh_json_mode; then
      mh_json_doc <<'PY'
doc = {"command": "trash", "action": "empty", "ok": True, "already_empty": True, "missing": True}
PY
    fi
    return 0
  fi

  local before_b before_h
  before_b="$(mh_dir_size_bytes "$MH_TRASH")"
  before_h="$(mh_human_size "$MH_TRASH")"

  if (( before_b == 0 )); then
    if mh_json_mode; then
      MH_JSON_HUMAN="$before_h" mh_json_doc <<'PY'
import os
doc = {
    "command": "trash",
    "action": "empty",
    "ok": True,
    "already_empty": True,
    "bytes_before": 0,
    "human_before": os.environ.get("MH_JSON_HUMAN") or "—",
}
PY
      return 0
    fi
    mh_ok "Trash already empty"
    return 0
  fi

  mh_section "Empty Trash"
  mh_log "About to remove contents of $MH_TRASH (was $before_h)"
  if ! mh_confirm "Empty Trash now?"; then
    mh_warn "Aborted"
    if mh_json_mode; then
      mh_json_doc <<'PY'
doc = {"command": "trash", "action": "empty", "ok": False, "aborted": True}
PY
    fi
    return 1
  fi

  find "$MH_TRASH" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  local after_b after_h
  after_b="$(mh_dir_size_bytes "$MH_TRASH")"
  after_h="$(mh_human_size "$MH_TRASH")"

  if mh_json_mode; then
    MH_JSON_BB="$before_b" MH_JSON_BH="$before_h" MH_JSON_AB="$after_b" MH_JSON_AH="$after_h" mh_json_doc <<'PY'
import os
doc = {
    "command": "trash",
    "action": "empty",
    "ok": True,
    "bytes_before": int(os.environ.get("MH_JSON_BB") or 0),
    "human_before": os.environ.get("MH_JSON_BH"),
    "bytes_after": int(os.environ.get("MH_JSON_AB") or 0),
    "human_after": os.environ.get("MH_JSON_AH"),
}
PY
    return 0
  fi

  mh_ok "Trash emptied (now $after_h)"
}

mh_cmd_trash() {
  local action="${1:-status}"
  [[ $# -gt 0 ]] && shift
  case "$action" in
    -h|--help|help) mh_cmd_trash_usage ;;
    status|"") mh_cmd_trash_status "$@" ;;
    empty|clear) mh_cmd_trash_empty "$@" ;;
    *)
      mh_err "Unknown trash action: $action"
      mh_cmd_trash_usage
      return 1
      ;;
  esac
}
