.PHONY: fmt format-check lint lint-all build-check test check install-hooks

fmt:
	forge fmt

format-check:
	forge fmt --check

lint:
	forge lint --deny warnings

lint-all:
	forge lint --severity high med low info gas code-size

# Compiler diagnostics are not replayed when a permissive build is cached.
build-check:
	forge build --sizes --deny warnings --no-lint --no-cache

test:
	forge test -vvv

# Recursive invocations keep checks ordered even when make is called with -j.
check:
	+$(MAKE) format-check
	+$(MAKE) lint
	+$(MAKE) build-check
	+$(MAKE) test

install-hooks:
	git config --local core.hooksPath .githooks
	@printf '%s\n' 'Installed repository hooks from .githooks.'
