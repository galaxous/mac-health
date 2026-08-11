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
  mh_section "Docker disk usage"
  printf "  %-55s %s\n" "$MH_DOCKER_CONTAINERS" "$(mh_human_size "$MH_DOCKER_CONTAINERS")"
  printf "  %-55s %s\n" "$MH_DOCKER_HOME" "$(mh_human_size "$MH_DOCKER_HOME")"

  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      docker system df
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
    mh_ok "Docker does not appear to be running"
    return 0
  fi
  if ! mh_confirm "Quit Docker Desktop now?"; then
    mh_warn "Cancelled"
    return 1
  fi
  osascript -e 'quit app "Docker"' 2>/dev/null \
    || osascript -e 'quit app "Docker Desktop"' 2>/dev/null \
    || true
  sleep 2
  mh_ok "Quit signal sent"
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
    mh_warn "Cancelled"
    return 1
  fi
  docker system prune -f
  mh_ok "Soft prune done"
  docker system df
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
    mh_warn "Cancelled"
    return 1
  fi
  docker system prune -a --volumes -f
  mh_ok "Full prune done"
  docker system df
  printf "  %-55s %s\n" "$MH_DOCKER_CONTAINERS" "$(mh_human_size "$MH_DOCKER_CONTAINERS")"
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
