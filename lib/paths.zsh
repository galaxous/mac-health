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
typeset -g MH_CODE_SUPPORT="${MH_APP_SUPPORT}/Code"
typeset -g MH_CHROME_SW="${MH_APP_SUPPORT}/Google/Chrome/Default/Service Worker"

# Package managers / Docker
typeset -g MH_NPM_CACHE="${MH_HOME}/.npm"
typeset -g MH_DOCKER_HOME="${MH_HOME}/.docker"
typeset -g MH_DOCKER_CONTAINERS="${MH_LIBRARY}/Containers/com.docker.docker"

# Projects (size reports)
typeset -g MH_PROJECTS="${MH_HOME}/Desktop/Projects.nosync"

# Process names for "is running?" checks
typeset -gA MH_APP_PROCESS=(
  [spotify]="Spotify"
  [chrome]="Google Chrome"
  [cursor]="Cursor"
  [code]="Code"
  [docker]="Docker"
)
