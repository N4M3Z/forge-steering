# forge-steering Makefile

LIB_DIR = $(or $(FORGE_LIB),lib)

.PHONY: help test lint check init

help:
	@echo "forge-steering targets:"
	@echo "  make test    Run shell tests"
	@echo "  make lint    Shellcheck all scripts"
	@echo "  make check   Verify module structure"

init:
	@if [ ! -d $(LIB_DIR)/mk ]; then \
	  echo "Initializing forge-lib submodule..."; \
	  git submodule update --init $(LIB_DIR); \
	fi

ifneq ($(wildcard $(LIB_DIR)/mk/shell.mk),)
  include $(LIB_DIR)/mk/shell.mk
endif
