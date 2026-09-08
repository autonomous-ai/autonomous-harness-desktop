.PHONY: release upload-node-runtime terminal-local-manual terminal-local-e2e terminal-prod-e2e

## release: tag this commit and push the tag — CI builds macOS + Linux, publishes to GCS, and cuts
## the GitHub Release. The version is bumped from max(last git tag, live metadata.json), because
## publishing by hand used to move the manifest without ever tagging. ARGS="--dry-run" to preview.
release:
	bash scripts/release-desktop.sh $(ARGS)

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
