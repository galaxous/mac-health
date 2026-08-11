#!/usr/bin/env zsh
# Install mac-health into ~/bin so it is on PATH.
# Usage: ./install.zsh

emulate -L zsh
setopt err_return

ROOT="${0:A:h}"
BIN_DIR="${HOME}/bin"
TARGET="${BIN_DIR}/mac-health"

mkdir -p "${BIN_DIR}"

if [[ -L "${TARGET}" || -e "${TARGET}" ]]; then
  rm -f "${TARGET}"
fi

ln -s "${ROOT}/mac-health" "${TARGET}"
chmod +x "${ROOT}/mac-health"

print "Linked: ${TARGET} → ${ROOT}/mac-health"

if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
  print ""
  print "Add to ~/.zshrc:"
  print "  export PATH=\"\$HOME/bin:\$PATH\""
fi

print ""
print "Try: mac-health help"
print "     mac-health health"
