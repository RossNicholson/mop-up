# Releasing Mop Up

Releases are automated. **One command:**

```
make release VERSION=1.2.3
```

That bumps the version, commits, tags `v1.2.3`, and pushes. GitHub Actions then
builds, **signs**, **notarizes**, **staples**, publishes the GitHub release, and
bumps the Homebrew cask — then re-downloads the asset and verifies its sha256 +
notarization before declaring success.

**Don't** run `scripts/release.sh --publish` by hand: pushing a tag already
triggers CI, which is the single source of truth. To build a local notarized
test DMG, use `make build` (or `scripts/release.sh` with no arguments).

## Why this is hard to get wrong
- `make release` refuses to run on a dirty tree, off `main`, with a malformed
  version, or a tag that already exists.
- CI fails fast with a clear message if any required secret is missing.
- CI aborts if the pushed tag doesn't match the version that was actually built.
- Notarization is a hard gate — an un-notarized build cannot ship.
- The publish step is idempotent (safe to re-run after a transient failure).
- After publishing, CI re-downloads the asset and checks its sha256 + notarization.

## Required repo secrets
Settings → Secrets and variables → Actions. The same six are used by BrewDock,
ClawdBar and Mop Up:

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | base64 of the Developer ID Application `.p12` |
| `P12_PASSWORD` | the `.p12` export password |
| `NOTARY_API_KEY_P8_BASE64` | base64 of the App Store Connect `.p8` |
| `NOTARY_KEY_ID` | the notary key's ID |
| `NOTARY_ISSUER_ID` | the notary issuer ID |
| `TAP_PUSH_TOKEN` | fine-grained PAT, `contents:write` on `RossNicholson/homebrew-tap` only. One token, "Homebrew tap push (all apps)", is shared by BrewDock, ClawdBar and Mop Up; it expires 17 Oct 2027 |


## Mop Up specifics
- **Mole is fetched at build time.** `scripts/vendor-mole.sh` downloads the
  pinned Mole release into `Vendor/` and checks each file's SHA-256. CI needs
  network access for this (GitHub only).
- **Updating Mole:** change `MOLE_VERSION` in `scripts/vendor-mole.sh`, run
  `scripts/vendor-mole.sh --print-hashes`, paste the hashes in, run `make
  vendor && make test`, then click through every screen. Mole's text output is
  what the parsers read, so a new Mole can change it: the engine tests catch
  most of that.
- **Signing:** Mole's `analyze-go` and `status-go` are Mach-O files inside
  `Contents/Resources/mole/bin`. The "Bundle Mole engine" build phase signs
  them with the hardened runtime, and `release.sh` refuses to ship unless both
  are Developer ID signed.
- **GPL source:** every GitHub release gets the exact Mole source tarball
  (`Mole-x.y.z-source.tar.gz`) attached next to the DMG.
- **Local notarized build:** `make build` uses the `notarytool` keychain
  profile, or the App Store Connect API key when `NOTARY_KEY_P8`,
  `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID` are set.
- The DMG has an Applications shortcut, and its file name is `MopUp-x.y.z.dmg`
  (no space) although the app is `Mop Up.app`.
