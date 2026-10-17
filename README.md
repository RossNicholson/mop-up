<p align="center"><img src="docs/icon.png" width="128" alt="Mop Up's mascot: a soapy bucket with a mop"></p>

# Mop Up

**A free, open-source Mac cleaner with a friendly window.** Mop Up clears out caches, logs and leftovers, uninstalls apps along with the files they leave behind, tunes up macOS and shows you where your disk space has gone. Nothing is removed until you say so, and uninstalled apps go to the Trash so you can get them back.

Mop Up is a native SwiftUI app for macOS 14 and later. Its cleaning engine is [Mole](https://github.com/tw93/Mole) by tw93 (see [Credits](#credits)).

## What it does

- **Home**: your Mac's health score, free disk space, memory and processor use, updated live.
- **Clean Up**: scans app caches, logs, browser leftovers, developer files (Xcode, npm, pip, Homebrew…) and files left behind by apps you've deleted. You see everything it found, file by file, before anything is cleaned. Big things it won't touch on its own (simulators, Time Machine snapshots) are listed separately so you can decide.
- **Uninstall**: lists your apps by size. Pick some, see exactly which files would go, then move them to the Trash. Apps that are still open have to be quit first, so nothing unsaved is lost.
- **Tune Up**: refreshes Finder, Spotlight and network caches, checks preferences and login items and repairs what it safely can. You can check first without changing anything.
- **Disk Space**: the biggest places on your Mac. Open folders to look inside, show items in Finder or move them to the Trash.
- **History**: every clean-up, uninstall and tune-up.
- **Menu bar**: free space at a glance, with a panel showing health, memory and processor and shortcuts to clean up, uninstall, tune up or check disk space. Closing the window keeps Mop Up in the menu bar; it can also open at login. Both are in Settings.

## Install

```sh
brew trust --cask rossnicholson/tap/mopup
brew install --cask rossnicholson/tap/mopup
```

Or download the DMG from [Releases](https://github.com/RossNicholson/mop-up/releases). Mop Up is signed and notarized by Apple.

**Full Disk Access.** macOS hides some folders from apps until you allow it. Without Full Disk Access, Mop Up still works but skips the Trash, some caches and app leftovers it can't check fully. Turn it on in System Settings → Privacy & Security → Full Disk Access (Mop Up has a button that takes you there).

**Admin password.** Some tune-up steps and some app removals need your password. macOS asks for it in a dialog titled "Mop Up"; it goes straight to macOS and Mop Up never stores it.

## Credits

Mop Up is a front end for **[Mole](https://github.com/tw93/Mole)**, the open-source Mac cleaner by [tw93](https://github.com/tw93). Every scan, clean, uninstall and tune-up is done by Mole; Mop Up runs it in the background and turns its results into the screens you see. If you like the terminal, use Mole directly. tw93 also makes a paid native app, [Mole for Mac](https://mole.fit).

A pinned Mole release is bundled inside the app (`scripts/vendor-mole.sh` downloads it and checks every file against a pinned SHA-256). Mop Up changes one line of it: the title of the admin-password dialog. Each Mop Up release includes the exact Mole source it ships with.

Fonts: [Barlow Condensed](https://github.com/jpt/barlow) and [Geist Mono](https://github.com/vercel/geist-font), SIL Open Font License.

## Building

You need Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and an internet connection the first time (to fetch Mole).

```sh
xcodegen generate
open MopUp.xcodeproj
```

`make run` builds and opens a development copy signed with the Developer ID, so macOS remembers the permissions you give it between builds (an unsigned or ad-hoc build looks like a new app every time). Without that certificate, build from Xcode as usual.

The build downloads Mole into `Vendor/` (git-ignored), copies it into the app and signs its two Go helpers. `make test` runs the tests; the engine tests run the bundled Mole with read-only commands (status, app list, previews) and never delete anything.

Releasing is one command; see [RELEASING.md](RELEASING.md).

## Licence

Mop Up is free software under the [GNU General Public License v3](LICENSE), the same licence as Mole.
