#!/usr/bin/env bash
# Install mac-health system-wide (no git clone required).
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/galaxous/mac-health/main/install.sh | bash
#
# Env:
#   REF / MAC_HEALTH_REF  — git ref (branch or tag), default: main
#   PREFIX                — install root, default: ~/.mac-health
#
# Local clone (optional):
#   ./install.sh --local

set -euo pipefail

OWNER="galaxous"
REPO="mac-health"
REF="${MAC_HEALTH_REF:-${REF:-main}}"
PREFIX="${PREFIX:-${HOME}/.mac-health}"
BIN_DIR="${HOME}/bin"
LINK="${BIN_DIR}/mac-health"
LOCAL=0

if [[ "${1:-}" == "--local" ]]; then
  LOCAL=1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl is required" >&2
  exit 1
fi
if ! command -v tar >/dev/null 2>&1; then
  echo "error: tar is required" >&2
  exit 1
fi

ensure_path() {
  mkdir -p "${BIN_DIR}"
  local line='export PATH="$HOME/bin:$PATH"'
  local marker='# mac-health PATH'
  local rc="${HOME}/.zshrc"

  if [[ ":${PATH}:" == *":${BIN_DIR}:"* ]]; then
    return 0
  fi

  if [[ -f "${rc}" ]] && grep -Fq "${marker}" "${rc}" 2>/dev/null; then
    echo "PATH note: restart your shell (or: source ~/.zshrc)"
    return 0
  fi

  {
    echo ""
    echo "${marker}"
    echo "${line}"
  } >> "${rc}"
  echo "Appended PATH to ${rc}"
  echo "Reload: source ~/.zshrc"
}

install_from_dir() {
  local src="$1"
  if [[ ! -x "${src}/mac-health" ]]; then
    echo "error: mac-health entry not found in ${src}" >&2
    exit 1
  fi

  mkdir -p "${PREFIX}"
  # Replace install tree but keep PREFIX itself
  find "${PREFIX}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  # Copy toolkit files (exclude .git)
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude '.git' "${src}/" "${PREFIX}/"
  else
    tar -C "${src}" --exclude '.git' -cf - . | tar -C "${PREFIX}" -xf -
  fi
  chmod +x "${PREFIX}/mac-health"
  if [[ -f "${PREFIX}/install.sh" ]]; then
    chmod +x "${PREFIX}/install.sh"
  fi
  if [[ -f "${PREFIX}/install.zsh" ]]; then
    chmod +x "${PREFIX}/install.zsh"
  fi

  rm -f "${LINK}"
  ln -s "${PREFIX}/mac-health" "${LINK}"
}

echo "mac-health installer"
echo "  ref:    ${REF}"
echo "  prefix: ${PREFIX}"
echo

if [[ "${LOCAL}" -eq 1 ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  echo "Installing from local clone: ${SCRIPT_DIR}"
  install_from_dir "${SCRIPT_DIR}"
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "${TMP}"' EXIT

  # Prefer tag archive URL when REF looks like a tag (v*), else heads/
  if [[ "${REF}" == v* ]]; then
    ARCHIVE_URL="https://github.com/${OWNER}/${REPO}/archive/refs/tags/${REF}.tar.gz"
  else
    ARCHIVE_URL="https://github.com/${OWNER}/${REPO}/archive/refs/heads/${REF}.tar.gz"
  fi

  echo "Downloading ${ARCHIVE_URL}"
  if ! curl -fsSL "${ARCHIVE_URL}" -o "${TMP}/mac-health.tgz"; then
    # Fallback: try the other archive style
    if [[ "${REF}" == v* ]]; then
      ARCHIVE_URL="https://github.com/${OWNER}/${REPO}/archive/refs/heads/${REF}.tar.gz"
    else
      ARCHIVE_URL="https://github.com/${OWNER}/${REPO}/archive/refs/tags/${REF}.tar.gz"
    fi
    echo "Retry: ${ARCHIVE_URL}"
    curl -fsSL "${ARCHIVE_URL}" -o "${TMP}/mac-health.tgz"
  fi

  tar -xzf "${TMP}/mac-health.tgz" -C "${TMP}"
  SRC="$(find "${TMP}" -mindepth 1 -maxdepth 1 -type d | head -1)"
  if [[ -z "${SRC}" ]]; then
    echo "error: archive extracted empty" >&2
    exit 1
  fi
  install_from_dir "${SRC}"
fi

ensure_path

echo
echo "Installed:"
echo "  ${PREFIX}"
echo "  ${LINK} → ${PREFIX}/mac-health"
if [[ -f "${PREFIX}/VERSION" ]]; then
  echo "  version: $(tr -d '[:space:]' < "${PREFIX}/VERSION")"
fi
echo
echo "Try:"
echo "  mac-health help"
echo "  mac-health health"
echo "  mac-health version"
