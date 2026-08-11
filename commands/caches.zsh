# cmd: caches — safe cache cleanup (subcommands)

mh_cmd_caches_usage() {
  cat <<'EOF'
Usage: mac-health caches <target>

Targets:
  all           Run safe cache cleanups (not *-deep)
  list          Show sizes only (no delete); includes IDE breakdown
  spotify       ~/Library/Caches/com.spotify.client
  chrome        ~/Library/Caches/Google/Chrome
  chrome-sw     Chrome Service Worker cache (quit Chrome first)
  npm           npm cache clean --force
  composer      composer clear-cache
  brew          brew cleanup -s
  cursor        Cursor Cache + CachedData (quit Cursor first)
  cursor-deep   + Cursor User/workspaceStorage + History (settings kept)
  code          VS Code safe caches (quit Code first; settings kept)
  code-deep     + Code User/workspaceStorage + History (settings kept)
  typescript    ~/Library/Caches/typescript
  node-gyp      ~/Library/Caches/node-gyp
  logs          ~/Library/Logs (contents)

Notes:
  all-caches in list is a size summary only — never deleted as a whole.
  *-deep does not delete settings.json / keybindings / globalStorage.
EOF
}

mh_cmd_caches_list() {
  mh_section "Cache sizes"
  local -A map=(
    [spotify]="$MH_CACHE_SPOTIFY"
    [chrome]="$MH_CACHE_CHROME"
    [chrome-sw]="$MH_CHROME_SW"
    [google-caches]="$MH_CACHE_GOOGLE"
    [npm]="$MH_NPM_CACHE"
    [composer]="$MH_CACHE_COMPOSER"
    [homebrew]="$MH_CACHE_HOMEBREW"
    [typescript]="$MH_CACHE_TYPESCRIPT"
    [node-gyp]="$MH_CACHE_NODE_GYP"
    [logs]="$MH_LOGS"
    [all-caches]="$MH_CACHES"
  )
  local key
  for key in ${(ko)map}; do
    printf "  %-28s %-55s %s\n" "$key" "${map[$key]}" "$(mh_human_size "${map[$key]}")"
  done

  mh_section "VS Code (Application Support/Code)"
  local -A code_map=(
    [code-support]="$MH_CODE_SUPPORT"
    [code-cache]="$MH_CODE_CACHE"
    [code-cached-data]="$MH_CODE_CACHED_DATA"
    [code-vsix]="$MH_CODE_CACHED_VSIX"
    [code-service-worker]="$MH_CODE_SERVICE_WORKER"
    [code-web-storage]="$MH_CODE_WEB_STORAGE"
    [code-workspace-storage]="$MH_CODE_WORKSPACE_STORAGE"
    [code-history]="$MH_CODE_HISTORY"
  )
  for key in ${(ko)code_map}; do
    printf "  %-28s %-55s %s\n" "$key" "${code_map[$key]}" "$(mh_human_size "${code_map[$key]}")"
  done

  mh_section "Cursor (Application Support/Cursor)"
  local -A cursor_map=(
    [cursor-support]="$MH_CURSOR_SUPPORT"
    [cursor-cache]="$MH_CURSOR_CACHE"
    [cursor-cached-data]="$MH_CURSOR_CACHED_DATA"
    [cursor-workspace-storage]="$MH_CURSOR_WORKSPACE_STORAGE"
    [cursor-history]="$MH_CURSOR_HISTORY"
  )
  for key in ${(ko)cursor_map}; do
    printf "  %-28s %-55s %s\n" "$key" "${cursor_map[$key]}" "$(mh_human_size "${cursor_map[$key]}")"
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

mh_cmd_caches_chrome_sw() {
  mh_section "Chrome Service Worker"
  mh_require_app_closed chrome || return 1
  mh_safe_rm_contents "$MH_CHROME_SW" "Chrome Service Worker"
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
  mh_section "Cursor caches (safe)"
  mh_require_app_closed cursor || return 1
  mh_safe_rm_contents "$MH_CURSOR_CACHE" "Cursor/Cache"
  mh_safe_rm_contents "$MH_CURSOR_CACHED_DATA" "Cursor/CachedData"
}

mh_cmd_caches_cursor_deep() {
  mh_section "Cursor deep (workspaceStorage + History)"
  mh_warn "Keeps settings/keybindings; clears per-workspace state and local file history."
  mh_require_app_closed cursor || return 1
  if ! mh_confirm "Clear Cursor workspaceStorage + History?"; then
    mh_warn "Cancelled"
    return 1
  fi
  mh_safe_rm_contents "$MH_CURSOR_WORKSPACE_STORAGE" "Cursor/User/workspaceStorage"
  mh_safe_rm_contents "$MH_CURSOR_HISTORY" "Cursor/User/History"
}

mh_cmd_caches_code() {
  mh_section "VS Code caches (safe)"
  mh_require_app_closed code || return 1
  mh_safe_rm_contents "$MH_CODE_CACHE" "Code/Cache"
  mh_safe_rm_contents "$MH_CODE_CACHED_DATA" "Code/CachedData"
  mh_safe_rm_contents "$MH_CODE_CACHED_EXTENSIONS" "Code/CachedExtensions"
  mh_safe_rm_contents "$MH_CODE_CACHED_VSIX" "Code/CachedExtensionVSIXs"
  mh_safe_rm_contents "$MH_CODE_CODE_CACHE" "Code/Code Cache"
  mh_safe_rm_contents "$MH_CODE_GPU_CACHE" "Code/GPUCache"
  mh_safe_rm_contents "$MH_CODE_SERVICE_WORKER" "Code/Service Worker"
  mh_safe_rm_contents "$MH_CODE_WEB_STORAGE" "Code/WebStorage"
  mh_safe_rm_contents "$MH_CODE_LOGS" "Code/logs"
}

mh_cmd_caches_code_deep() {
  mh_section "VS Code deep (workspaceStorage + History)"
  mh_warn "Keeps settings/keybindings; clears per-workspace state and local file history."
  mh_require_app_closed code || return 1
  if ! mh_confirm "Clear VS Code workspaceStorage + History?"; then
    mh_warn "Cancelled"
    return 1
  fi
  mh_safe_rm_contents "$MH_CODE_WORKSPACE_STORAGE" "Code/User/workspaceStorage"
  mh_safe_rm_contents "$MH_CODE_HISTORY" "Code/User/History"
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
  mh_warn "Will skip targets whose apps are still running. Does not run *-deep."
  if ! mh_confirm "Clean spotify/chrome/chrome-sw/npm/composer/brew/cursor/code/typescript/node-gyp?"; then
    mh_warn "Cancelled"
    return 1
  fi

  local failed=0
  mh_cmd_caches_spotify || failed=1
  mh_cmd_caches_chrome || failed=1
  mh_cmd_caches_chrome_sw || failed=1
  mh_cmd_caches_npm || failed=1
  mh_cmd_caches_composer || failed=1
  mh_cmd_caches_brew || failed=1
  mh_cmd_caches_cursor || failed=1
  mh_cmd_caches_code || failed=1
  mh_cmd_caches_typescript || failed=1
  mh_cmd_caches_node_gyp || failed=1

  if (( failed )); then
    mh_warn "Finished with some skips/failures"
    return 1
  fi
  mh_ok "All safe cache cleanups finished"
}

mh_cmd_caches() {
  local target="${1:-}"
  case "$target" in
    ""|-h|--help|help) mh_cmd_caches_usage ;;
    list) mh_cmd_caches_list ;;
    all) mh_cmd_caches_all ;;
    spotify) mh_cmd_caches_spotify ;;
    chrome) mh_cmd_caches_chrome ;;
    chrome-sw|chrome_sw) mh_cmd_caches_chrome_sw ;;
    npm) mh_cmd_caches_npm ;;
    composer) mh_cmd_caches_composer ;;
    brew|homebrew) mh_cmd_caches_brew ;;
    cursor) mh_cmd_caches_cursor ;;
    cursor-deep|cursor_deep) mh_cmd_caches_cursor_deep ;;
    code|vscode) mh_cmd_caches_code ;;
    code-deep|code_deep|vscode-deep) mh_cmd_caches_code_deep ;;
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
