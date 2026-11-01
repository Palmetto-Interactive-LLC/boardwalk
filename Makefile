.PHONY: ci
ci:
	@for f in scripts/*.sh setup.sh; do bash -n "$$f" || exit 1; done
	@command -v shellcheck >/dev/null && shellcheck scripts/*.sh setup.sh || echo "shellcheck not installed, skipped"
	gitleaks detect --source . --no-banner --redact
