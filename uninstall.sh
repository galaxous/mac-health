#!/usr/bin/env bash
# Uninstall mac-health (mirror of install.sh).
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/galaxous/mac-health/main/uninstall.sh | bash
#
# Env:
#   PREFIX  — install root, default: ~/.mac-health (same as install.sh)
#   FORCE=1 — allow removing PREFIX outside $HOME (safety gate)
#
# Local clone:
#   ./uninstall.sh

set -euo pipefail

PREFIX="${PREFIX:-${HOME}/.mac-health}"
BIN_DIR="${HOME}/bin"
LINK="${BIN_DIR}/mac-health"
MARKER='# mac-health PATH'
PATH_LINE='export PATH="$HOME/bin:$PATH"'
RC="${HOME}/.zshrc"
FORCE="${FORCE:-0}"

echo "mac-health uninstaller"
echo "  prefix: ${PREFIX}"
echo

# Refuse to wipe an unexpected PREFIX unless FORCE=1
case "${PREFIX}" in
  "${HOME}"|"${HOME}/"|"/"|"")
    echo "error: refusing to remove PREFIX=${PREFIX}" >&2
    exit 1
    ;;
esac
if [[ "${PREFIX}" != "${HOME}"/* && "${FORCE}" != "1" ]]; then
  echo "error: PREFIX (${PREFIX}) is outside \$HOME; set FORCE=1 to proceed" >&2
  exit 1
fi

removed_any=0

remove_link() {
  if [[ ! -e "${LINK}" && ! -L "${LINK}" ]]; then
    echo "skip: ${LINK} not present"
    return 0
  fi

  if [[ -L "${LINK}" ]]; then
    local target base
    target="$(readlink "${LINK}" || true)"
    base="$(basename "${target}")"
    # Safe: only remove if link target looks like mac-health
    if [[ "${base}" == "mac-health" ]] \
      || [[ "${target}" == "${PREFIX}/mac-health" ]] \
      || [[ "${target}" == *mac-health* ]]; then
      rm -f "${LINK}"
      echo "removed: ${LINK} → ${target}"
      removed_any=1
    else
      echo "skip: ${LINK} points elsewhere (${target}); not removing"
    fi
    return 0
  fi

  # Regular file/dir named mac-health — only with FORCE
  if [[ "$(basename "${LINK}")" == "mac-health" && "${FORCE}" == "1" ]]; then
    rm -rf "${LINK}"
    echo "removed: ${LINK} (FORCE)"
    removed_any=1
  else
    echo "skip: ${LINK} is not a mac-health symlink (set FORCE=1 to remove)"
  fi
}

remove_path_block() {
  if [[ ! -f "${RC}" ]]; then
    echo "skip: ${RC} not found"
    return 0
  fi
  if ! grep -Fq "${MARKER}" "${RC}" 2>/dev/null; then
    echo "skip: PATH marker not in ${RC}"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  # Remove marker line and the following export PATH line install.sh wrote.
  # If the next line is unrelated, keep it (only drop the marker).
  awk -v marker="${MARKER}" -v expected="${PATH_LINE}" '
    $0 == marker {
      if ((getline nxt) > 0) {
        if (nxt == expected) next
        print nxt
      }
      next
    }
    { print }
  ' "${RC}" > "${tmp}"

  mv "${tmp}" "${RC}"
  echo "removed: PATH block (${MARKER}) from ${RC}"
  removed_any=1
}

remove_prefix() {
  if [[ ! -e "${PREFIX}" ]]; then
    echo "skip: ${PREFIX} not present"
    return 0
  fi
  rm -rf "${PREFIX}"
  echo "removed: ${PREFIX}"
  removed_any=1
}

# Order: unlink first, then shell config, then install tree last
# (so an in-tree CLI can still finish if it copied this script to temp).
remove_link
remove_path_block
remove_prefix

echo
if [[ "${removed_any}" -eq 1 ]]; then
  echo "Uninstalled mac-health."
else
  echo "Nothing to remove (already clean)."
fi
echo "Reload shell if needed: source ~/.zshrc"
