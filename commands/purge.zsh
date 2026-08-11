# cmd: purge — instant relief (macOS purge reclaimable pages)

mh_cmd_purge() {
  mh_section "Instant memory purge"
  mh_warn "This only reclaims inactive/file-backed pages. Not a permanent fix."
  mh_warn "Requires sudo."

  if ! mh_confirm "Run sudo purge now?"; then
    if mh_json_mode; then
      mh_json_doc <<'PY'
doc = {"command": "purge", "ok": False, "cancelled": True}
PY
    else
      mh_warn "Cancelled"
    fi
    return 1
  fi

  if sudo purge; then
    local pressure_out
    pressure_out="$(memory_pressure 2>/dev/null | tail -6 || true)"
    if mh_json_mode; then
      MH_JSON_PRESSURE="$pressure_out" mh_json_doc <<'PY'
import os
doc = {
    "command": "purge",
    "ok": True,
    "pressure_raw": (os.environ.get("MH_JSON_PRESSURE") or "").strip() or None,
}
PY
      return 0
    fi
    mh_ok "purge finished"
    print
    [[ -n "$pressure_out" ]] && print "$pressure_out"
  else
    if mh_json_mode; then
      mh_json_doc <<'PY'
doc = {"command": "purge", "ok": False, "error": "purge failed"}
PY
    else
      mh_err "purge failed"
    fi
    return 1
  fi
}
