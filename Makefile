.PHONY: test check

test:
	@command -v bats >/dev/null 2>&1 || { echo "bats is required: https://bats-core.readthedocs.io/en/stable/installation.html" >&2; exit 1; }
	bats test

check:
	bash -n monitor.sh install.sh uninstall.sh
