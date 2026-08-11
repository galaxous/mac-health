# cmd: purge — instant relief (macOS purge reclaimable pages)

mh_cmd_purge() {
  mh_section "Instant memory purge"
  mh_warn "This only reclaims inactive/file-backed pages. Not a permanent fix."
  mh_warn "Requires sudo."

  if ! mh_confirm "Run sudo purge now?"; then
    mh_warn "Cancelled"
    return 1
  fi

  if sudo purge; then
    mh_ok "purge finished"
    print
    memory_pressure 2>/dev/null | tail -6 || true
  else
    mh_err "purge failed"
    return 1
  fi
}
