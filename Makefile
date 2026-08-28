.PHONY: upload-desktop upload-node-runtime terminal-local-manual terminal-local-e2e terminal-prod-e2e

## upload-desktop: build, sign, notarize, and publish a macOS desktop release.
upload-desktop:
	bash scripts/upload-desktop.sh $(ARGS)

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
