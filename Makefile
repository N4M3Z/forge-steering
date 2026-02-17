# forge-steering — test and lint

.PHONY: help test lint check

help:
	@echo "forge-steering targets:"
	@echo "  make test    Run shell tests"
	@echo "  make lint    Shellcheck all scripts"
	@echo "  make check   Verify module structure"

test:
	@if [ -f tests/test.sh ]; then bash tests/test.sh; else echo "No tests defined"; fi

lint:
	@if find . -name '*.sh' -not -path '*/target/*' | grep -q .; then \
	  find . -name '*.sh' -not -path '*/target/*' | xargs shellcheck -S warning 2>/dev/null || true; \
	fi

check:
	@test -f module.yaml && echo "  ok module.yaml" || echo "  MISSING module.yaml"
	@test -d hooks && echo "  ok hooks/" || echo "  MISSING hooks/"
