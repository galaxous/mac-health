#!/usr/bin/env zsh
# Local/dev install: copy this clone into ~/.mac-health and link ~/bin.
# Prefer the remote one-liner for machines without a clone:
#   curl -fsSL https://raw.githubusercontent.com/galaxous/mac-health/main/install.sh | bash
#
# Usage: ./install.zsh

emulate -L zsh
setopt err_return

ROOT="${0:A:h}"
exec "${ROOT}/install.sh" --local
