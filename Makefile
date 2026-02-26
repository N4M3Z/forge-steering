# forge-steering Makefile

LIB_DIR = $(or $(FORGE_LIB),lib)

.PHONY: help build test lint check init clean

help:
	@echo "forge-steering targets:"
	@echo "  make build   Build dispatch binary"
	@echo "  make test    Run Rust + shell tests"
	@echo "  make lint    cargo fmt --check + clippy + shellcheck"
	@echo "  make check   Verify module structure"
	@echo "  make clean   Remove build artifacts"

init:
	@if [ ! -d $(LIB_DIR)/mk ]; then \
	  echo "Initializing forge-lib submodule..."; \
	  git submodule update --init $(LIB_DIR); \
	fi

# --- Rust ---

build:
	cargo build --release --manifest-path Cargo.toml

test:
	cargo test --manifest-path Cargo.toml

lint:
	cargo fmt --manifest-path Cargo.toml --check
	cargo clippy --manifest-path Cargo.toml -- -D warnings

clean:
	cargo clean --manifest-path Cargo.toml 2>/dev/null || true

# --- Shell (from forge-lib) ---

ifneq ($(wildcard $(LIB_DIR)/mk/shell.mk),)
  include $(LIB_DIR)/mk/shell.mk
endif
