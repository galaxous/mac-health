# Central paths for mac-health toolkit.
# MH_ROOT must be set by the main entry before sourcing this file.

: "${MH_ROOT:?MH_ROOT must be set before sourcing paths.zsh}"

typeset -g MH_HOME="${HOME}"
typeset -g MH_LIBRARY="${MH_HOME}/Library"
typeset -g MH_CACHES="${MH_LIBRARY}/Caches"
typeset -g MH_APP_SUPPORT="${MH_LIBRARY}/Application Support"
typeset -g MH_LOGS="${MH_LIBRARY}/Logs"
typeset -g MH_LAUNCH_AGENTS="${MH_LIBRARY}/LaunchAgents"
typeset -g MH_TRASH="${MH_HOME}/.Trash"

# App caches
typeset -g MH_CACHE_SPOTIFY="${MH_CACHES}/com.spotify.client"
typeset -g MH_CACHE_CHROME="${MH_CACHES}/Google/Chrome"
typeset -g MH_CACHE_GOOGLE="${MH_CACHES}/Google"
typeset -g MH_CACHE_HOMEBREW="${MH_CACHES}/Homebrew"
typeset -g MH_CACHE_COMPOSER="${MH_CACHES}/composer"
typeset -g MH_CACHE_TYPESCRIPT="${MH_CACHES}/typescript"
typeset -g MH_CACHE_NODE_GYP="${MH_CACHES}/node-gyp"

# App support / tool data
typeset -g MH_CURSOR_SUPPORT="${MH_APP_SUPPORT}/Cursor"
typeset -g MH_CURSOR_CACHE="${MH_CURSOR_SUPPORT}/Cache"
typeset -g MH_CURSOR_CACHED_DATA="${MH_CURSOR_SUPPORT}/CachedData"
typeset -g MH_CURSOR_USER="${MH_CURSOR_SUPPORT}/User"
typeset -g MH_CURSOR_WORKSPACE_STORAGE="${MH_CURSOR_USER}/workspaceStorage"
typeset -g MH_CURSOR_HISTORY="${MH_CURSOR_USER}/History"

typeset -g MH_CODE_SUPPORT="${MH_APP_SUPPORT}/Code"
typeset -g MH_CODE_CACHE="${MH_CODE_SUPPORT}/Cache"
typeset -g MH_CODE_CACHED_DATA="${MH_CODE_SUPPORT}/CachedData"
typeset -g MH_CODE_CACHED_EXTENSIONS="${MH_CODE_SUPPORT}/CachedExtensions"
typeset -g MH_CODE_CACHED_VSIX="${MH_CODE_SUPPORT}/CachedExtensionVSIXs"
typeset -g MH_CODE_CODE_CACHE="${MH_CODE_SUPPORT}/Code Cache"
typeset -g MH_CODE_GPU_CACHE="${MH_CODE_SUPPORT}/GPUCache"
typeset -g MH_CODE_SERVICE_WORKER="${MH_CODE_SUPPORT}/Service Worker"
typeset -g MH_CODE_WEB_STORAGE="${MH_CODE_SUPPORT}/WebStorage"
typeset -g MH_CODE_LOGS="${MH_CODE_SUPPORT}/logs"
typeset -g MH_CODE_USER="${MH_CODE_SUPPORT}/User"
typeset -g MH_CODE_WORKSPACE_STORAGE="${MH_CODE_USER}/workspaceStorage"
typeset -g MH_CODE_HISTORY="${MH_CODE_USER}/History"

typeset -g MH_CHROME_SW="${MH_APP_SUPPORT}/Google/Chrome/Default/Service Worker"

# Package managers / Docker
typeset -g MH_NPM_CACHE="${MH_HOME}/.npm"
typeset -g MH_PNPM_HOME="${MH_HOME}/Library/pnpm"
typeset -g MH_CACHE_PNPM="${MH_CACHES}/pnpm"
typeset -g MH_CACHE_YARN="${MH_CACHES}/Yarn"
typeset -g MH_BUN_CACHE="${MH_HOME}/.bun/install/cache"
typeset -g MH_DOCKER_HOME="${MH_HOME}/.docker"
typeset -g MH_DOCKER_CONTAINERS="${MH_LIBRARY}/Containers/com.docker.docker"

# Developer / Xcode (disk bloat candidates)
typeset -g MH_DEVELOPER="${MH_LIBRARY}/Developer"
typeset -g MH_XCODE_DERIVED="${MH_DEVELOPER}/Xcode/DerivedData"
typeset -g MH_XCODE_ARCHIVES="${MH_DEVELOPER}/Xcode/Archives"
typeset -g MH_CORESIMULATOR="${MH_DEVELOPER}/CoreSimulator"
typeset -g MH_CONTAINERS="${MH_LIBRARY}/Containers"

# Projects (size reports)
typeset -g MH_PROJECTS="${MH_HOME}/Desktop/Projects.nosync"

# Process names for "is running?" checks
typeset -gA MH_APP_PROCESS=(
  [spotify]="Spotify"
  [chrome]="Google Chrome"
  [cursor]="Cursor"
  [code]="Code"
  [docker]="Docker"
  [xcode]="Xcode"
)
