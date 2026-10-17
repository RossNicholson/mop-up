.PHONY: release build test vendor

# Ship a release: bump version, commit, tag, push -> CI builds/notarizes/publishes.
#   make release VERSION=1.2.3
release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=x.y.z"; exit 1; }
	@scripts/cut-release.sh $(VERSION)

# Build a local notarized test DMG (does not publish).
build:
	@scripts/release.sh

# Run the unit tests (the engine tests run the bundled Mole read-only).
test:
	@xcodegen generate >/dev/null && xcodebuild test -project MopUp.xcodeproj \
		-scheme MopUp -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -quiet

# Fetch and verify the pinned Mole release into Vendor/ (the build does this too).
vendor:
	@scripts/vendor-mole.sh --force
