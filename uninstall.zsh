#!/usr/bin/env zsh
# Local uninstall wrapper.
# Prefer the remote one-liner when you do not have a clone:
#   curl -fsSL https://raw.githubusercontent.com/galaxous/mac-health/main/uninstall.sh | bash
#
# Usage: ./uninstall.zsh

emulate -L zsh
setopt err_return

ROOT="${0:A:h}"
exec "${ROOT}/uninstall.sh"
