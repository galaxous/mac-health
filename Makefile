# mac-health — local clone helpers
#
# Remote one-liners (no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/galaxous/mac-health/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/galaxous/mac-health/main/uninstall.sh | bash
#
# From this repo:
#   make install
#   make uninstall

.PHONY: help install uninstall remove version check health

help:
	@echo "mac-health — Makefile targets"
	@echo ""
	@echo "  make install     Install from this clone (~/.mac-health + ~/bin/mac-health)"
	@echo "  make uninstall   Remove install (symlink, prefix, PATH block)"
	@echo "  make remove      Alias for uninstall"
	@echo "  make version     Print version via ./mac-health"
	@echo "  make check       Run health check via ./mac-health"
	@echo "  make health      Alias for check"
	@echo "  make help        Show this help (default)"
	@echo ""
	@echo "Remote install/uninstall (no clone): see README or comments at top of this file."

install:
	./install.sh --local

uninstall remove:
	./uninstall.sh

version:
	./mac-health version

check health:
	./mac-health health
