.PHONY: release upload-desktop upload-desktop-linux upload-node-runtime terminal-local-manual terminal-local-e2e terminal-prod-e2e

## release: tag this commit and push the tag — CI builds macOS + Linux, publishes to GCS, and cuts
## the GitHub Release. The version is bumped from max(last git tag, live metadata.json), because
## publishing by hand used to move the manifest without ever tagging. ARGS="--dry-run" to preview.
release:
	bash scripts/release-desktop.sh $(ARGS)

## upload-desktop: build, sign, notarize, and publish a macOS release straight from this machine.
## ESCAPE HATCH, not the normal path — use `make release`. This one bumps from the remote manifest and
## creates NO git tag, so the repo stops reflecting what is published; that is how one tag (v1.0.52)
## ended up nine releases behind the manifest. If you use it, cut a `make release` afterwards to bring
## the tag back in line.
upload-desktop:
	bash scripts/upload-desktop.sh $(ARGS)

## upload-desktop-linux: same escape hatch for Linux ARM64 or x64 (amd64 is an x64 alias).
## Defaults to the current host. Examples: ARCH=arm64, ARCH=x64, ARCH=amd64.
upload-desktop-linux:
	TARGET_ARCH="$(ARCH)" bash scripts/upload-desktop-linux.sh $(ARGS)

## upload-node-runtime: publish checksum-verified managed Node runtimes for desktop bootstrap.
upload-node-runtime:
	bash scripts/publish-managed-node-runtime.sh $(ARGS)

## terminal-local-manual: start the local backend/CLI stack and open the desktop fixture.
terminal-local-manual:
	bash scripts/start-terminal-local-manual.sh

## terminal-local-e2e: run the local end-to-end terminal test.
terminal-local-e2e:
	bash scripts/test-terminal-local-e2e.sh

## terminal-prod-e2e: run the opt-in production terminal test with explicit evidence variables.
terminal-prod-e2e:
	bash scripts/test-terminal-prod-e2e.sh
