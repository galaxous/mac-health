# cmd: caches — safe cache cleanup (subcommands)

mh_cmd_caches_usage() {
  cat <<'EOF'
Usage: mac-health caches <target>

Targets:
  all         Run all safe cache cleanups below
  spotify     ~/Library/Caches/com.spotify.client
  chrome      ~/Library/Caches/Google/Chrome
  npm         npm cache clean --force (+ ~/.npm size report)
  composer    composer clear-cache
  brew        brew cleanup -s
  cursor      Cursor Cache + CachedData (quit Cursor first)
  typescript  ~/Library/Caches/typescript
  node-gyp    ~/Library/Caches/node-gyp
  logs        ~/Library/Logs (contents)
  list        Show sizes only (no delete)
EOF
}

mh_cmd_caches_list() {
  mh_section "Cache sizes"
  local -A map=(
    [spotify]="$MH_CACHE_SPOTIFY"
    [chrome]="$MH_CACHE_CHROME"
    [google-caches]="$MH_CACHE_GOOGLE"
    [npm]="$MH_NPM_CACHE"
    [composer]="$MH_CACHE_COMPOSER"
    [homebrew]="$MH_CACHE_HOMEBREW"
    [cursor-cache]="$MH_CURSOR_CACHE"
    [cursor-cached-data]="$MH_CURSOR_CACHED_DATA"
    [cursor-support]="$MH_CURSOR_SUPPORT"
    [code-support]="$MH_CODE_SUPPORT"
    [typescript]="$MH_CACHE_TYPESCRIPT"
    [node-gyp]="$MH_CACHE_NODE_GYP"
    [chrome-sw]="$MH_CHROME_SW"
    [logs]="$MH_LOGS"
    [all-caches]="$MH_CACHES"
  )
  local key
  for key in ${(k)map}; do
    printf "  %-22s %-50s %s\n" "$key" "${map[$key]}" "$(mh_human_size "${map[$key]}")"
  done
}

mh_cmd_caches_spotify() {
  mh_section "Spotify cache"
  mh_require_app_closed spotify || return 1
  mh_safe_rm_contents "$MH_CACHE_SPOTIFY" "Spotify cache"
}

mh_cmd_caches_chrome() {
  mh_section "Chrome cache"
  mh_require_app_closed chrome || return 1
  mh_safe_rm_contents "$MH_CACHE_CHROME" "Chrome cache"
}

mh_cmd_caches_npm() {
  mh_section "npm cache"
  local before
  before="$(mh_human_size "$MH_NPM_CACHE")"
  mh_log "~/.npm was $before"
  if mh_run_if_cmd npm cache clean --force; then
    mh_ok "npm cache cleaned (now $(mh_human_size "$MH_NPM_CACHE"))"
  fi
}

mh_cmd_caches_composer() {
  mh_section "Composer cache"
  if mh_run_if_cmd composer clear-cache; then
    mh_ok "composer clear-cache done (cache dir now $(mh_human_size "$MH_CACHE_COMPOSER"))"
  fi
}

mh_cmd_caches_brew() {
  mh_section "Homebrew cleanup"
  if mh_run_if_cmd brew cleanup -s; then
    mh_ok "brew cleanup done (cache now $(mh_human_size "$MH_CACHE_HOMEBREW"))"
  fi
}

mh_cmd_caches_cursor() {
  mh_section "Cursor caches"
  mh_require_app_closed cursor || return 1
  mh_safe_rm_contents "$MH_CURSOR_CACHE" "Cursor/Cache"
  mh_safe_rm_contents "$MH_CURSOR_CACHED_DATA" "Cursor/CachedData"
}

mh_cmd_caches_typescript() {
  mh_section "TypeScript cache"
  mh_safe_rm_contents "$MH_CACHE_TYPESCRIPT" "typescript cache"
}

mh_cmd_caches_node_gyp() {
  mh_section "node-gyp cache"
  mh_safe_rm_contents "$MH_CACHE_NODE_GYP" "node-gyp cache"
}

mh_cmd_caches_logs() {
  mh_section "User logs"
  if ! mh_confirm "Delete contents of $MH_LOGS?"; then
    mh_warn "Cancelled"
    return 1
  fi
  mh_safe_rm_contents "$MH_LOGS" "Library/Logs"
}

mh_cmd_caches_all() {
  mh_section "All safe caches"
  mh_warn "Will skip targets whose apps are still running."
  if ! mh_confirm "Clean spotify/chrome/npm/composer/brew/cursor/typescript/node-gyp?"; then
    mh_warn "Cancelled"
    return 1
  fi

  local failed=0
  mh_cmd_caches_spotify || failed=1
  mh_cmd_caches_chrome || failed=1
  mh_cmd_caches_npm || failed=1
  mh_cmd_caches_composer || failed=1
  mh_cmd_caches_brew || failed=1
  mh_cmd_caches_cursor || failed=1
  mh_cmd_caches_typescript || failed=1
  mh_cmd_caches_node_gyp || failed=1

  if (( failed )); then
    mh_warn "Finished with some skips/failures"
    return 1
  fi
  mh_ok "All cache cleanups finished"
}

mh_cmd_caches() {
  local target="${1:-}"
  case "$target" in
    ""|-h|--help|help) mh_cmd_caches_usage ;;
    list) mh_cmd_caches_list ;;
    all) mh_cmd_caches_all ;;
    spotify) mh_cmd_caches_spotify ;;
    chrome) mh_cmd_caches_chrome ;;
    npm) mh_cmd_caches_npm ;;
    composer) mh_cmd_caches_composer ;;
    brew|homebrew) mh_cmd_caches_brew ;;
    cursor) mh_cmd_caches_cursor ;;
    typescript) mh_cmd_caches_typescript ;;
    node-gyp|node_gyp) mh_cmd_caches_node_gyp ;;
    logs) mh_cmd_caches_logs ;;
    *)
      mh_err "Unknown caches target: $target"
      mh_cmd_caches_usage
      return 1
      ;;
  esac
}
