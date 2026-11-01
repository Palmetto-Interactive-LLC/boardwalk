# `make ci` is the one command CI runs (Depot CI and a laptop alike).
# The macOS app build stays in .github/workflows/build.yml (Depot CI has no macOS runners).
GITLEAKS_VERSION ?= 8.30.1
GITLEAKS ?= $(or $(shell command -v gitleaks),.cache/gitleaks/gitleaks)

.PHONY: ci shell secrets

ci: shell secrets

shell:
	bash -n scripts/build.sh scripts/signing-identity.sh setup.sh

# Scans the full git history. Downloads a pinned, checksum-verified gitleaks when none is installed.
secrets:
	@if [ ! -x "$(GITLEAKS)" ]; then \
	  set -e; arch=$$(uname -m | sed 's/aarch64/arm64/;s/x86_64/x64/'); os=$$(uname -s | tr A-Z a-z); \
	  art=gitleaks_$(GITLEAKS_VERSION)_$${os}_$${arch}.tar.gz; \
	  base=https://github.com/gitleaks/gitleaks/releases/download/v$(GITLEAKS_VERSION); \
	  mkdir -p .cache/gitleaks; \
	  curl -fsSLo .cache/gitleaks/$$art $$base/$$art; \
	  curl -fsSLo .cache/gitleaks/sums.txt $$base/gitleaks_$(GITLEAKS_VERSION)_checksums.txt; \
	  (cd .cache/gitleaks && grep "  $$art$$" sums.txt | sha256sum -c -); \
	  tar -xzf .cache/gitleaks/$$art -C .cache/gitleaks gitleaks; \
	fi
	$(GITLEAKS) detect --source . --redact --no-banner
