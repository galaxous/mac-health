# cmd: docker — Docker Desktop disk/RAM cleanup

mh_cmd_docker_usage() {
  cat <<'EOF'
Usage: mac-health docker <action>

Actions:
  status    Show docker system df + local data sizes
  prune     docker system prune -a --volumes (destructive; confirms)
  soft      docker system prune (unused containers/networks/images dangling)
  quit      Quit Docker Desktop (frees RAM)
EOF
}

mh_cmd_docker_status() {
  local containers_b home_b
  containers_b="$(mh_dir_size_bytes "$MH_DOCKER_CONTAINERS")"
  home_b="$(mh_dir_size_bytes "$MH_DOCKER_HOME")"

  local cli=0 daemon=0 df_out=""
  if command -v docker >/dev/null 2>&1; then
    cli=1
    if docker info >/dev/null 2>&1; then
      daemon=1
      df_out="$(docker system df 2>/dev/null || true)"
    fi
  fi

  if mh_json_mode; then
    MH_JSON_CB="$containers_b" MH_JSON_HB="$home_b" \
    MH_JSON_CP="$MH_DOCKER_CONTAINERS" MH_JSON_HP="$MH_DOCKER_HOME" \
    MH_JSON_CLI="$cli" MH_JSON_DAEMON="$daemon" MH_JSON_DF="$df_out" \
    mh_json_doc <<'PY'
import os
doc = {
    "command": "docker",
    "action": "status",
    "paths": {
        "containers": {
            "path": os.environ["MH_JSON_CP"],
            "bytes": int(os.environ.get("MH_JSON_CB") or 0),
        },
        "home": {
            "path": os.environ["MH_JSON_HP"],
            "bytes": int(os.environ.get("MH_JSON_HB") or 0),
        },
    },
    "cli_available": os.environ.get("MH_JSON_CLI") == "1",
    "daemon_running": os.environ.get("MH_JSON_DAEMON") == "1",
    "system_df": (os.environ.get("MH_JSON_DF") or "").strip() or None,
}
PY
    return 0
  fi

  mh_section "Docker disk usage"
  printf "  %-55s %s\n" "$MH_DOCKER_CONTAINERS" "$(mh_human_size "$MH_DOCKER_CONTAINERS")"
  printf "  %-55s %s\n" "$MH_DOCKER_HOME" "$(mh_human_size "$MH_DOCKER_HOME")"

  if (( cli )); then
    if (( daemon )); then
      print -r -- "$df_out"
    else
      mh_warn "Docker CLI present but daemon not running"
    fi
  else
    mh_warn "docker not in PATH"
  fi
}

mh_cmd_docker_quit() {
  mh_section "Quit Docker Desktop"
  if ! mh_app_running docker && ! pgrep -f "Docker Desktop" >/dev/null 2>&1; then
    if mh_json_mode; then
      mh_json_doc <<'PY'
doc = {"command": "docker", "action": "quit", "ok": True, "already_stopped": True}
PY
    else
      mh_ok "Docker does not appear to be running"
    fi
    return 0
  fi
  if ! mh_confirm "Quit Docker Desktop now?"; then
    if mh_json_mode; then
      mh_json_doc <<'PY'
doc = {"command": "docker", "action": "quit", "ok": False, "cancelled": True}
PY
    else
      mh_warn "Cancelled"
    fi
    return 1
  fi
  osascript -e 'quit app "Docker"' 2>/dev/null \
    || osascript -e 'quit app "Docker Desktop"' 2>/dev/null \
    || true
  sleep 2
  if mh_json_mode; then
    mh_json_doc <<'PY'
doc = {"command": "docker", "action": "quit", "ok": True}
PY
  else
    mh_ok "Quit signal sent"
  fi
}

mh_cmd_docker_soft() {
  mh_section "Docker soft prune"
  if ! command -v docker >/dev/null 2>&1; then
    mh_err "docker not found"
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    mh_err "Docker daemon not running — start Docker Desktop first"
    return 1
  fi
  if ! mh_confirm "Run: docker system prune -f ?"; then
    if mh_json_mode; then
      mh_json_doc <<'PY'
doc = {"command": "docker", "action": "soft", "ok": False, "cancelled": True}
PY
    else
      mh_warn "Cancelled"
    fi
    return 1
  fi
  local out
  out="$(docker system prune -f 2>&1)" || {
    mh_err "soft prune failed"
    return 1
  }
  local df_out
  df_out="$(docker system df 2>/dev/null || true)"
  if mh_json_mode; then
    MH_JSON_OUT="$out" MH_JSON_DF="$df_out" mh_json_doc <<'PY'
import os
doc = {
    "command": "docker",
    "action": "soft",
    "ok": True,
    "output": (os.environ.get("MH_JSON_OUT") or "").strip() or None,
    "system_df": (os.environ.get("MH_JSON_DF") or "").strip() or None,
}
PY
  else
    print -r -- "$out"
    mh_ok "Soft prune done"
    print -r -- "$df_out"
  fi
}

mh_cmd_docker_prune() {
  mh_section "Docker full prune (images + volumes)"
  mh_warn "Removes unused images AND unused volumes. Backup important volumes first."
  if ! command -v docker >/dev/null 2>&1; then
    mh_err "docker not found"
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    mh_err "Docker daemon not running — start Docker Desktop first"
    return 1
  fi
  if ! mh_confirm "Run: docker system prune -a --volumes -f ?"; then
    if mh_json_mode; then
      mh_json_doc <<'PY'
doc = {"command": "docker", "action": "prune", "ok": False, "cancelled": True}
PY
    else
      mh_warn "Cancelled"
    fi
    return 1
  fi
  local out
  out="$(docker system prune -a --volumes -f 2>&1)" || {
    mh_err "full prune failed"
    return 1
  }
  local df_out
  df_out="$(docker system df 2>/dev/null || true)"
  if mh_json_mode; then
    MH_JSON_OUT="$out" MH_JSON_DF="$df_out" \
    MH_JSON_CB="$(mh_dir_size_bytes "$MH_DOCKER_CONTAINERS")" \
    MH_JSON_CP="$MH_DOCKER_CONTAINERS" \
    mh_json_doc <<'PY'
import os
doc = {
    "command": "docker",
    "action": "prune",
    "ok": True,
    "output": (os.environ.get("MH_JSON_OUT") or "").strip() or None,
    "system_df": (os.environ.get("MH_JSON_DF") or "").strip() or None,
    "containers_path": {
        "path": os.environ.get("MH_JSON_CP"),
        "bytes": int(os.environ.get("MH_JSON_CB") or 0),
    },
}
PY
  else
    print -r -- "$out"
    mh_ok "Full prune done"
    print -r -- "$df_out"
    printf "  %-55s %s\n" "$MH_DOCKER_CONTAINERS" "$(mh_human_size "$MH_DOCKER_CONTAINERS")"
  fi
}

mh_cmd_docker() {
  local action="${1:-status}"
  case "$action" in
    -h|--help|help) mh_cmd_docker_usage ;;
    status|df) mh_cmd_docker_status ;;
    soft) mh_cmd_docker_soft ;;
    prune|full) mh_cmd_docker_prune ;;
    quit|stop) mh_cmd_docker_quit ;;
    *)
      mh_err "Unknown docker action: $action"
      mh_cmd_docker_usage
      return 1
      ;;
  esac
}
