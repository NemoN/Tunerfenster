# Building and releasing Tunerfenster

[English README](../README.md) · [Deutsche Anleitung](../README.de.md)

## Requirements

- macOS with Xcode or compatible command-line tools and Swift 5.9 or later.
- macOS 27 or later for the current DMG packaging commands.
- Developer ID Application certificate and private key in Keychain for a
  distributable release. Local builds can use an ad-hoc signature.
- A `notarytool` Keychain profile for Apple notarization.
- Rosetta when testing an Intel build on Apple Silicon.

The shipped app targets macOS 14 or later. Its bundled VideoLAN framework is
downloaded over HTTPS from the pinned URL in `scripts/bundle-vlc.sh` and checked
against VideoLAN's published SHA-256 checksum.

## Local build

```bash
chmod +x ./*.sh scripts/*.sh
SIGN_IDENTITY=- ./build-app.sh
open dist/Tunerfenster.app
```

The default architecture is the build machine's architecture. An explicit
architecture and output location can be supplied without changing the source:

```bash
TARGET_ARCH=arm64 APP_BUNDLE="$PWD/dist/arm64/Tunerfenster.app" ./build-app.sh --no-bootstrap
TARGET_ARCH=x86_64 APP_BUNDLE="$PWD/dist/x86_64/Tunerfenster.app" ./build-app.sh --no-bootstrap
```

`sign-app.sh` uses `SIGN_IDENTITY` when set. Otherwise it uses the sole available
Developer ID Application identity, falls back to ad-hoc signing when none is
available, and asks for an explicit choice if multiple identities exist.
The framework is signed before the resource bundle and app. Release builds use
Hardened Runtime, a secure timestamp and standard library validation.

## Connection configuration

Normal builds and releases contain no server configuration or credentials.
Enter these in the app's Settings. For an optional local configuration, copy
`.env.example` to a file outside the repository and launch:

```bash
dist/Tunerfenster.app/Contents/MacOS/Tunerfenster --env-file /absolute/path/to/local.env
```

`./build-app.sh /absolute/path/to/local.env` can embed only that local file path
for a private bootstrap build. The file and its contents are not copied into the
app. `--no-bootstrap` explicitly disables this. Do not distribute bootstrap builds.

## Tests and playback checks

```bash
swift test
# Optional read-only integration against your own TVHeadend server:
TVH_INTEGRATION_ENV=/absolute/path/to/local.env swift test
# Optional read-only check against the public GitHub release API:
TUNERFENSTER_LIVE_UPDATES=1 swift test
```

The tests cover status matching, preview lifecycle, EPG, picons, localization,
layout, tickets and persistent channel/viewing state. The optional live test
does not start a stream or change server configuration.

```bash
dist/arm64/Tunerfenster.app/Contents/MacOS/Tunerfenster --check-vlc
dist/arm64/Tunerfenster.app/Contents/MacOS/Tunerfenster --check-playback /path/to/test.ts
arch -x86_64 dist/x86_64/Tunerfenster.app/Contents/MacOS/Tunerfenster --check-vlc
```

The playback check requires a local file with audio and video and confirms
decoded frames. It uses dummy outputs, opens no window and reads no TVHeadend
credentials. `scripts/qa-server.py` supplies a local Digest-authenticated HTTP
fixture for GUI checks; pass `--showcase` for the screenshot demo.

## Notarized releases

Create a Keychain profile once. Enter an **app-specific password** only at the
protected terminal prompt, not in a command argument or repository file:

```bash
xcrun notarytool store-credentials Tunerfenster \
  --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

With your Developer ID Application certificate available:

```bash
./release-all.sh --profile Tunerfenster
```

This builds and notarizes the app for each CPU architecture, staples its ticket,
creates a signed drag-and-drop DMG, notarizes the DMG separately and staples its
ticket. Verification covers signatures, tickets, Gatekeeper and a fresh app copy
from the mounted image. Set `PLAYBACK_CHECK_FILE=/path/to/test.ts` to include a
decode check on the final app and the copy extracted from the DMG.

Outputs:

```text
dist/release/Tunerfenster-<version>-arm64.dmg
dist/release/Tunerfenster-<version>-x86_64.dmg
dist/release/<architecture>/Tunerfenster-<version>-<architecture>.zip
```

Each DMG has a SHA-256 file and Apple submission/status logs. No passwords or
signing keys are included. Keep these logs locally; upload only the intended
installers and checksums to a GitHub release.

Individual stages:

```bash
TARGET_ARCH=arm64 ./release-app.sh --profile Tunerfenster
TARGET_ARCH=arm64 ./release-dmg.sh --profile Tunerfenster
TARGET_ARCH=arm64 ./release-dmg.sh --resume Tunerfenster
```

A pending DMG submission is protected by an upload hash and can be resumed
without uploading again. `release-app.sh --xcode` alternatively uses the Apple
Account signed into Xcode; `--resume` continues that Xcode export workflow.

## Third-party source and local modifications

See [VideoLAN notices](../Resources/ThirdPartyNotices.txt) for the exact official
package, checksum, source revisions and LGPL terms. The framework's only binary
changes are selecting one CPU slice and applying the distribution signature.
Library replacement for local use requires re-signing the framework and then
the app. Keep the third-party notices with redistributed copies.

## GitHub update metadata

The updater reads the public `NemoN/Tunerfenster` latest-release API. Publish a
stable tag such as `v1.8.0` that matches the app's `CFBundleShortVersionString`,
with both generated installers attached before publishing:

```text
Tunerfenster-1.8.0-arm64.dmg
Tunerfenster-1.8.0-x86_64.dmg
```

Drafts, pre-releases, malformed versions and older versions are not offered.
Each download must belong to that exact repository and tag and have the
expected CPU-specific filename. If an installer is missing, the app offers
the release page and explains the missing download. Keep this filename
contract when preparing future releases.

Checks use an isolated URLSession without cookies, cached credentials or
TVHeadend configuration. Automatic attempts are spaced at least 24 hours
apart, including failed attempts. Manual checks can retry immediately. Known
release metadata is cached locally and re-evaluated against the installed
version and current hardware on launch. Apple Silicon is detected even from
an Intel process under Rosetta. Downloads and installation require user action.

API and platform references: [GitHub Releases API](https://docs.github.com/en/rest/releases/releases)
and [Apple's Rosetta translation detection](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment).
