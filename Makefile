.PHONY: release build test vendor run screenshots

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

# Build and open a development copy. It's signed with the Developer ID (like
# releases) instead of "ad hoc": an ad-hoc signature changes on every build, so
# macOS would treat each build as a new app and ask for permissions again.
run:
	@xcodegen generate >/dev/null && xcodebuild -project MopUp.xcodeproj -scheme MopUp \
		-configuration Debug -destination 'platform=macOS' -derivedDataPath build/dd \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
		DEVELOPMENT_TEAM=5HQ5V9NP82 -quiet build
	@pkill -x "Mop Up" || true
	@sleep 1
	@open "build/dd/Build/Products/Debug/Mop Up.app"

# Render the website screenshots (demo data, light and dark) into build/screenshots.
screenshots:
	@xcodegen generate >/dev/null && TEST_RUNNER_MOPUP_SCREENSHOTS="$(CURDIR)/build/screenshots" \
		xcodebuild test -project MopUp.xcodeproj -scheme MopUp -destination 'platform=macOS' \
		CODE_SIGNING_ALLOWED=NO -only-testing:MopUpTests/ScreenshotTests -quiet
	@echo "Screenshots in build/screenshots"
