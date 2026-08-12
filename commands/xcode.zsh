# cmd: xcode — DerivedData / Simulator / Archives inventory (+ optional derived clean)

mh_cmd_xcode_usage() {
  cat <<'EOF'
Usage: mac-health xcode [status|clean-derived] [--json] [-y]

Inspect Xcode-related disk use. Only clean-derived deletes (DerivedData).

Actions:
  status          Sizes for DerivedData, Archives, CoreSimulator (default)
  clean-derived   Empty DerivedData (quit Xcode first; confirm / -y)

Examples:
  mac-health xcode
  mac-health xcode status
  mac-health xcode clean-derived
  mac-health -y --json xcode clean-derived

Archives and simulators are never deleted by mac-health (see disk bloat hints).
EOF
}

mh_cmd_xcode_status() {
  local -a keys=(
    "derived|${MH_XCODE_DERIVED}|Xcode DerivedData"
    "archives|${MH_XCODE_ARCHIVES}|Xcode Archives"
    "simulator|${MH_CORESIMULATOR}|CoreSimulator"
    "developer|${MH_DEVELOPER}|Library/Developer (total)"
  )

  if mh_json_mode; then
    {
      local row key path label sized bytes human
      for row in "${keys[@]}"; do
        key="${row%%|*}"
        rest="${row#*|}"
        path="${rest%%|*}"
        label="${rest#*|}"
        sized="$(mh_dir_size_timed "$path" 8)"
        bytes="${sized%%|*}"
        human="${sized#*|}"
        print -r -- "${key}|${path}|${label}|${bytes}|${human}"
      done
    } | python3 -c '
import json, sys
items = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    key, path, label, nbytes, human = line.split("|", 4)
    items.append({
        "key": key,
        "path": path,
        "label": label,
        "bytes": int(nbytes or 0),
        "human": human,
    })
print(json.dumps({"command": "xcode", "action": "status", "items": items}, indent=2, ensure_ascii=False))
'
    return 0
  fi

  mh_section "Xcode / Developer disk"
  printf "  %-12s %10s  %s\n" "KEY" "SIZE" "PATH"
  printf "  %-12s %10s  %s\n" "------------" "----------" "----"
  local row key path label sized bytes human
  for row in "${keys[@]}"; do
    key="${row%%|*}"
    rest="${row#*|}"
    path="${rest%%|*}"
    label="${rest#*|}"
    sized="$(mh_dir_size_timed "$path" 8)"
    bytes="${sized%%|*}"
    human="${sized#*|}"
    printf "  %-12s %10s  %s\n" "$key" "$human" "$path"
  done
  print
  mh_log "Clean DerivedData: mac-health xcode clean-derived"
  mh_log "Simulators: xcrun simctl delete unavailable  |  Archives: Xcode Organizer"
  mh_ok "Xcode status complete (inspect only)"
}

mh_cmd_xcode_clean_derived() {
  mh_section "Xcode DerivedData"
  if [[ ! -d "$MH_XCODE_DERIVED" ]]; then
    mh_warn "Missing: $MH_XCODE_DERIVED"
    if mh_json_mode; then
      mh_json_doc <<'PY'
doc = {"command": "xcode", "action": "clean-derived", "ok": True, "missing": True}
PY
    fi
    return 0
  fi

  mh_require_app_closed xcode || return 1

  local before_h
  before_h="$(mh_dir_size_timed "$MH_XCODE_DERIVED" 8)"
  before_h="${before_h#*|}"
  mh_log "DerivedData is ${before_h} — projects will rebuild indexes/caches"
  if ! mh_confirm "Empty Xcode DerivedData now?"; then
    mh_warn "Cancelled"
    if mh_json_mode; then
      mh_json_doc <<'PY'
doc = {"command": "xcode", "action": "clean-derived", "ok": False, "aborted": True}
PY
    fi
    return 1
  fi

  mh_safe_rm_contents "$MH_XCODE_DERIVED" "Xcode DerivedData"
  local after_h
  after_h="$(mh_human_size "$MH_XCODE_DERIVED")"

  if mh_json_mode; then
    MH_JSON_BH="$before_h" MH_JSON_AH="$after_h" mh_json_doc <<'PY'
import os
doc = {
    "command": "xcode",
    "action": "clean-derived",
    "ok": True,
    "human_before": os.environ.get("MH_JSON_BH"),
    "human_after": os.environ.get("MH_JSON_AH"),
}
PY
  fi
  return 0
}

mh_cmd_xcode() {
  local action="${1:-status}"
  [[ $# -gt 0 ]] && shift
  case "$action" in
    -h|--help|help) mh_cmd_xcode_usage ;;
    status|"") mh_cmd_xcode_status "$@" ;;
    clean-derived|clean_derived|derived)
      mh_cmd_xcode_clean_derived "$@"
      ;;
    *)
      mh_err "Unknown xcode action: $action"
      mh_cmd_xcode_usage
      return 1
      ;;
  esac
}
