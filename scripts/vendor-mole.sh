#!/bin/bash
#
# vendor-mole.sh — fetch the pinned Mole release into Vendor/mole.
#
# Mop Up's cleaning engine is Mole (https://github.com/tw93/Mole, GPL-3.0) by
# tw93. This downloads the tagged source (shell scripts + lib) and the prebuilt
# Go helpers for both architectures, checks every download against a pinned
# SHA-256, and assembles a relocatable copy:
#
#   Vendor/mole/mole, bin/*.sh, lib/**   from the source tag
#   Vendor/mole/bin/analyze-go           universal (lipo arm64 + x86_64)
#   Vendor/mole/bin/status-go            universal
#   Vendor/mole/LICENSE, VERSION
#   Vendor/Mole-<version>-source.tar.gz  the exact source, for GPL source offers
#
# To move to a new Mole release: change MOLE_VERSION, run with --print-hashes,
# paste the printed hashes below, re-run, then test the app.
set -euo pipefail

MOLE_VERSION="1.61.0"
SRC_SHA256="8621a60633493f552ebcc33a2a954acaff1557f84f032157d33987b885eb27ef"
# From the release's SHA256SUMS
ANALYZE_ARM64_SHA256="7d25c9999c93de489c4aa2c2f538873145de8d5f77eb67f32a5942785d4351b8"
ANALYZE_AMD64_SHA256="918b9051ff51518445c2759b4a7f08ed029319373b9ea0f70df82dc877c02119"
STATUS_ARM64_SHA256="75402ecb15dfb40ae348b27cdff3a9d5024941bb130d2951a8544be40f97e820"
STATUS_AMD64_SHA256="9e0dc50459902d0b114ea1430d5611aab4982a689f3a8cd5231efe716ca3a954"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO/Vendor/mole"
BASE="https://github.com/tw93/Mole"

fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }

# Already vendored at this version: nothing to do (keeps Xcode builds fast).
if [[ "${1:-}" != "--force" && "${1:-}" != "--print-hashes" && -f "$OUT/VERSION" ]] \
   && [[ "$(cat "$OUT/VERSION")" == "$MOLE_VERSION" ]] \
   && [[ -x "$OUT/bin/analyze-go" && -x "$OUT/bin/status-go" ]]; then
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() { curl -fsSL --retry 3 -o "$2" "$1" || fail "download failed: $1"; }
sha() { shasum -a 256 "$1" | awk '{print $1}'; }

fetch "$BASE/archive/refs/tags/V$MOLE_VERSION.tar.gz" "$TMP/src.tar.gz"
for tool in analyze status; do
  for arch in arm64 amd64; do
    fetch "$BASE/releases/download/V$MOLE_VERSION/$tool-darwin-$arch" "$TMP/$tool-$arch"
  done
done

if [[ "${1:-}" == "--print-hashes" ]]; then
  echo "SRC_SHA256=\"$(sha "$TMP/src.tar.gz")\""
  echo "ANALYZE_ARM64_SHA256=\"$(sha "$TMP/analyze-arm64")\""
  echo "ANALYZE_AMD64_SHA256=\"$(sha "$TMP/analyze-amd64")\""
  echo "STATUS_ARM64_SHA256=\"$(sha "$TMP/status-arm64")\""
  echo "STATUS_AMD64_SHA256=\"$(sha "$TMP/status-amd64")\""
  exit 0
fi

check() { [[ "$(sha "$1")" == "$2" ]] || fail "checksum mismatch for $(basename "$1")"; }
check "$TMP/src.tar.gz" "$SRC_SHA256"
check "$TMP/analyze-arm64" "$ANALYZE_ARM64_SHA256"
check "$TMP/analyze-amd64" "$ANALYZE_AMD64_SHA256"
check "$TMP/status-arm64" "$STATUS_ARM64_SHA256"
check "$TMP/status-amd64" "$STATUS_AMD64_SHA256"

tar xzf "$TMP/src.tar.gz" -C "$TMP"
SRC="$TMP/Mole-$MOLE_VERSION"
[[ -f "$SRC/mole" && -d "$SRC/lib" && -d "$SRC/bin" ]] || fail "unexpected source layout"

rm -rf "$OUT"
mkdir -p "$OUT/bin"
cp "$SRC/mole" "$SRC/LICENSE" "$OUT/"
cp -R "$SRC/lib" "$OUT/lib"
cp "$SRC"/bin/*.sh "$OUT/bin/"
lipo -create "$TMP/analyze-arm64" "$TMP/analyze-amd64" -output "$OUT/bin/analyze-go"
lipo -create "$TMP/status-arm64" "$TMP/status-amd64" -output "$OUT/bin/status-go"
chmod 755 "$OUT/mole" "$OUT"/bin/*

# Our one change to Mole: its admin-password dialog (shown when there's no
# terminal) takes its title from MOLE_DIALOG_TITLE, so it can say "Mop Up".
SUDO_SH="$OUT/lib/core/sudo.sh"
/usr/bin/sed -i '' 's/with title \\"Mole\\"/with title \\"${MOLE_DIALOG_TITLE:-Mole}\\"/' "$SUDO_SH"
grep -q 'MOLE_DIALOG_TITLE' "$SUDO_SH" || fail "could not patch the dialog title in sudo.sh"
cat > "$OUT/MODIFICATIONS" <<EOF
This is Mole $MOLE_VERSION by tw93 (https://github.com/tw93/Mole), GPL-3.0.
Mop Up changes one line of it: in lib/core/sudo.sh the admin-password dialog
title reads \${MOLE_DIALOG_TITLE:-Mole} instead of "Mole". Nothing else is
modified. The unmodified source is published with each Mop Up release.
EOF

echo "$MOLE_VERSION" > "$OUT/VERSION"

rm -f "$REPO"/Vendor/Mole-*-source.tar.gz
cp "$TMP/src.tar.gz" "$REPO/Vendor/Mole-$MOLE_VERSION-source.tar.gz"

echo "Vendored Mole $MOLE_VERSION into $OUT"
