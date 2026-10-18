#!/bin/bash
#
# release.sh — build, sign, notarize, staple, verify, and (optionally) publish.
#
# The CANONICAL way to release is:  make release VERSION=x.y.z
# (that bumps the version, commits, tags, and pushes — CI then runs this script
# with --publish on a clean macOS runner). Run this WITHOUT --publish locally to
# produce a notarized test DMG. Do NOT run --publish by hand unless CI is down:
# the tag push triggers CI, which would publish the same version.
#
# Fails hard on any signing / notarization / verification problem.
set -euo pipefail

# ---- per-app config ----
APP="Mop Up"                   # the .app name (has a space: always quote it)
PROJECT="MopUp"                # .xcodeproj name
SCHEME="MopUp"
DMG_NAME="MopUp"               # DMG file name (no spaces, for clean URLs)
CASK="mopup"
GH_REPO="RossNicholson/mop-up"
USE_XCODEGEN=1                 # 1 = regenerate the .xcodeproj from project.yml
RUN_TESTS=1                    # 1 = run unit tests before archiving
DMG_APPLICATIONS_SYMLINK=1     # 1 = add an /Applications symlink in the DMG
DEVELOPMENT_TEAM=""            # set (non-XcodeGen projects) to sign the archive via args
# -------------------------

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP="$(cd "$REPO/.." && pwd)/homebrew-tap"
PROFILE="notarytool"
cd "$REPO"

PUBLISH=0
[[ "${1:-}" == "--publish" ]] && PUBLISH=1

step() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
fail() { printf '\n\033[1;31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

step "Preflight"
command -v xcrun >/dev/null    || fail "Xcode command line tools not found"
[[ -f ExportOptions.plist ]]   || fail "ExportOptions.plist missing (it must be committed)"
if [[ "$USE_XCODEGEN" -eq 1 ]]; then
  command -v xcodegen >/dev/null || fail "xcodegen not installed (brew install xcodegen)"
  xcodegen generate
fi
PROJ="$PROJECT.xcodeproj"
[[ -d "$PROJ" ]] || fail "$PROJ not found"

if [[ "$RUN_TESTS" -eq 1 ]]; then
  step "Running tests"
  xcodebuild test -project "$PROJ" -scheme "$SCHEME" \
    -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -quiet || fail "tests failed"
fi

step "Archiving (Release)"
rm -rf "build/$PROJECT.xcarchive" build/export build/dmg-staging
ARCHIVE_ARGS=(-project "$PROJ" -scheme "$SCHEME" -configuration Release -archivePath "build/$PROJECT.xcarchive" archive -quiet)
[[ -n "$DEVELOPMENT_TEAM" ]] && ARCHIVE_ARGS+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
xcodebuild "${ARCHIVE_ARGS[@]}" || fail "archive failed"

step "Exporting signed app"
xcodebuild -exportArchive -archivePath "build/$PROJECT.xcarchive" \
  -exportPath build/export -exportOptionsPlist ExportOptions.plist -quiet || fail "export failed"

APPBUNDLE="build/export/$APP.app"
# Capture then string-match: piping codesign into `grep -q` races under pipefail.
SIGN_INFO="$(codesign -dvvv "$APPBUNDLE" 2>&1)"
[[ "$SIGN_INFO" == *"Authority=Developer ID Application"* ]] || fail "app is not Developer ID signed"
# Mole's Go helpers are separate Mach-O files inside Resources: each needs its
# own Developer ID signature with the hardened runtime, or notarization fails.
for helper in analyze-go status-go; do
  HELPER_INFO="$(codesign -dvvv "$APPBUNDLE/Contents/Resources/mole/bin/$helper" 2>&1)"
  [[ "$HELPER_INFO" == *"Authority=Developer ID Application"* && "$HELPER_INFO" == *"runtime"* ]] \
    || fail "bundled Mole helper $helper is not Developer ID signed with the hardened runtime"
done
codesign --verify --deep --strict "$APPBUNDLE" || fail "app signature does not verify"
MOLE_SOURCE="$(ls Vendor/Mole-*-source.tar.gz 2>/dev/null | head -1)"
[[ -f "$MOLE_SOURCE" ]] || fail "Mole source tarball missing (scripts/vendor-mole.sh writes it)"

# Version comes from the built app — works whether or not the project is XcodeGen.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APPBUNDLE/Contents/Info.plist")"
[[ -n "$VERSION" ]] || fail "could not read version from the built app"
step "Built $APP $VERSION"

# Guard: a tag-triggered CI run must match the version that was actually built.
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  [[ "${GITHUB_REF_NAME:-}" == "v$VERSION" ]] \
    || fail "tag ${GITHUB_REF_NAME:-?} != built version v$VERSION (bump the version to match the tag)"
fi

DMG="build/$DMG_NAME-$VERSION.dmg"
step "Building DMG ($DMG)"
mkdir -p build/dmg-staging
cp -R "$APPBUNDLE" build/dmg-staging/
[[ "$DMG_APPLICATIONS_SYMLINK" -eq 1 ]] && ln -s /Applications build/dmg-staging/Applications
rm -f "$DMG"
hdiutil create -volname "$APP" -srcfolder build/dmg-staging -ov -format UDZO "$DMG" >/dev/null
rm -rf build/dmg-staging

step "Notarizing (this can take a few minutes)"
# CI passes an App Store Connect API key via env; locally we use the keychain profile.
if [[ -n "${NOTARY_KEY_P8:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
  SUBMIT="$(xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_P8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait 2>&1)"
else
  SUBMIT="$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1)"
fi
echo "$SUBMIT"
[[ "$SUBMIT" == *"status: Accepted"* ]] || fail "notarization was not Accepted"

step "Stapling and verifying"
xcrun stapler staple "$DMG"            || fail "stapling failed"
# Validation right after stapling occasionally fails while Apple's ticket
# propagates (v1.2.0 hit this), so retry briefly before giving up.
for attempt in 1 2 3 4 5; do
  xcrun stapler validate "$DMG" >/dev/null 2>&1 && break
  [[ "$attempt" -eq 5 ]] && fail "staple validation failed"
  echo "staple validation not ready yet, retrying in 15s ($attempt/5)"
  sleep 15
done
# The volume name has a space, so take everything from /Volumes/ to the end
MP="$(hdiutil attach -nobrowse -readonly "$DMG" | grep -o '/Volumes/.*$' | head -1)"
ASSESS="$(spctl -a -vvv -t exec "$MP/$APP.app" 2>&1 || true)"
hdiutil detach "$MP" -quiet
[[ "$ASSESS" == *"Notarized Developer ID"* ]] || { echo "$ASSESS"; fail "app inside the DMG is not notarized/accepted"; }

SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
step "Done: notarized DMG ready — $DMG  (sha256 $SHA)"

if [[ "$PUBLISH" -eq 0 ]]; then
  echo ""
  echo "Local build only (not published). To release: make release VERSION=$VERSION"
  exit 0
fi

# ---- publish (idempotent: safe to re-run) ----
step "Publishing v$VERSION to GitHub"
command -v gh >/dev/null || fail "gh not installed"
if ! git rev-parse "v$VERSION" >/dev/null 2>&1; then
  git tag "v$VERSION"
  git push origin "v$VERSION"
fi
if gh release view "v$VERSION" --repo "$GH_REPO" >/dev/null 2>&1; then
  gh release upload "v$VERSION" "$DMG" "$MOLE_SOURCE" --repo "$GH_REPO" --clobber
else
  # Mole is GPL: ship the exact source of the bundled copy with every release
  gh release create "v$VERSION" "$DMG" "$MOLE_SOURCE" --repo "$GH_REPO" --title "v$VERSION" --generate-notes
fi

step "Bumping Homebrew tap cask"
if [[ ! -d "$TAP" ]]; then
  [[ -n "${TAP_PUSH_TOKEN:-}" ]] || fail "tap not found at $TAP and no TAP_PUSH_TOKEN to clone it"
  git clone "https://x-access-token:${TAP_PUSH_TOKEN}@github.com/RossNicholson/homebrew-tap.git" "$TAP"
fi
CASKFILE="$TAP/Casks/$CASK.rb"
if [[ ! -f "$CASKFILE" && -f "docs/$CASK.rb" ]]; then
  # First release: add the cask from docs/ (its header comment is for this repo only)
  mkdir -p "$TAP/Casks"
  grep -v '^#' "docs/$CASK.rb" > "$CASKFILE"
  git -C "$TAP" add "Casks/$CASK.rb"
fi
[[ -f "$CASKFILE" ]] || fail "cask not found: $CASKFILE"
/usr/bin/sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASKFILE"
if ! git -C "$TAP" diff --quiet -- "Casks/$CASK.rb" || ! git -C "$TAP" diff --cached --quiet -- "Casks/$CASK.rb"; then
  git -C "$TAP" add "Casks/$CASK.rb"
  git -C "$TAP" commit -m "Bump $CASK to v$VERSION"
  git -C "$TAP" push origin main
fi

# ---- post-publish verification: prove what users will actually download ----
step "Verifying the published release"
TMP="$(mktemp -d)"
URL="https://github.com/$GH_REPO/releases/download/v$VERSION/$DMG_NAME-$VERSION.dmg"
curl -sSL -o "$TMP/dl.dmg" "$URL" || fail "could not download the published asset"
DL_SHA="$(shasum -a 256 "$TMP/dl.dmg" | awk '{print $1}')"
[[ "$DL_SHA" == "$SHA" ]] || fail "published asset sha256 ($DL_SHA) != cask sha256 ($SHA)"
# Apple's ticket can take a moment to reach every server, so retry before failing
for attempt in 1 2 3 4 5; do
  xcrun stapler validate "$TMP/dl.dmg" >/dev/null 2>&1 && break
  [[ "$attempt" -eq 5 ]] && fail "published asset is not stapled/notarized"
  echo "published asset validation failed, retrying in 15s ($attempt/5)"
  sleep 15
done
rm -rf "$TMP"

step "Published v$VERSION ✅  (downloaded asset matches sha256 and is notarized)"
