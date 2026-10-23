# Building and releasing Tunerfenster

[English README](../README.md) · [Deutsche Anleitung](../README.de.md)

## Requirements

- macOS with Xcode or compatible command-line tools and Swift 5.9 or later.
- macOS 27 or later for the current DMG packaging commands.
- A Developer ID Application certificate and its private key in Keychain to
  sign a release. Local builds can use a pinned signing certificate or an ad-hoc
  signature.
- A `notarytool` Keychain profile to notarize a release.
- Rosetta when testing an Intel build on Apple Silicon.

The app runs on macOS 14 or later. The build downloads the VideoLAN framework
over HTTPS from the pinned URL in `scripts/bundle-vlc.sh`, then checks it against
VideoLAN's published SHA-256 checksum.

## Local build

```bash
chmod +x ./*.sh scripts/*.sh
./build-app.sh --no-bootstrap
open dist/Tunerfenster.app
```

To keep Keychain access across local rebuilds, select a signing certificate once:

```bash
security find-identity -v -p codesigning
printf '%s\n' 'YOUR_40_CHARACTER_CERTIFICATE_SHA1' > .local-signing-identity
```

Use the certificate fingerprint from the command output. This local file is
ignored by Git and contains no private key. Keep using the same certificate
and bundle identifier. When switching from ad-hoc signing, macOS may ask once
more for access to the saved password; choose **Always Allow** to retain access.

Local builds use the pinned identity without a timestamp. If the pinned identity
is unavailable or invalid, the build stops. Without a pin, local builds use
ad-hoc signing, which can require a new Keychain approval after each change.
`SIGN_IDENTITY` explicitly overrides either choice; `SIGN_IDENTITY=-` requests
an ad-hoc build.

Each newly linked local executable gets a random Mach-O UUID. Keep the bundle
identifier and signing certificate stable, and link a separate executable for
any test app with a different bundle identifier. Reusing an executable UUID
across apps can confuse local network permissions; see
[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

By default, the build uses your Mac's architecture. Set the architecture and
output path for a different build without changing the source:

```bash
TARGET_ARCH=arm64 APP_BUNDLE="$PWD/dist/arm64/Tunerfenster.app" ./build-app.sh --no-bootstrap
TARGET_ARCH=x86_64 APP_BUNDLE="$PWD/dist/x86_64/Tunerfenster.app" ./build-app.sh --no-bootstrap
```

The scripts sign the framework, then the resource bundle and app. Certificate
signatures use Hardened Runtime and standard library validation. The release
script explicitly sets `SIGNING_MODE=release`, ignores the local pin and selects
the Developer ID Application identity in Keychain unless `SIGN_IDENTITY` is set.
Releases require that certificate and a secure timestamp. Local builds do not
notarize, package a DMG, change the version or publish anything.

## Connection configuration

Normal builds and releases contain no server settings or credentials. Enter
them in the app's Settings. To use a local configuration file instead, copy
`.env.example` outside the repository and launch:

```bash
dist/Tunerfenster.app/Contents/MacOS/Tunerfenster --env-file /absolute/path/to/local.env
```

`./build-app.sh /absolute/path/to/local.env` creates a private bootstrap build
that stores the local file path in the app. It does not copy the file or its
contents. `--no-bootstrap` disables this. Keep bootstrap builds private.

## Tests and playback checks

```bash
swift test
# Optional read-only integration against your own TVHeadend server:
TVH_INTEGRATION_ENV=/absolute/path/to/local.env swift test
# Optional read-only check against the public GitHub release API:
TUNERFENSTER_LIVE_UPDATES=1 swift test
```

Tests cover status matching, stream lifecycle, EPG, picons, localization,
layout, playback tickets and saved channel and viewing choices. The optional
TVHeadend test reads the server APIs without starting a stream or changing
the server configuration.

```bash
dist/arm64/Tunerfenster.app/Contents/MacOS/Tunerfenster --check-vlc
dist/arm64/Tunerfenster.app/Contents/MacOS/Tunerfenster --check-playback /path/to/test.ts
arch -x86_64 dist/x86_64/Tunerfenster.app/Contents/MacOS/Tunerfenster --check-vlc
```

The playback check decodes frames from a local file containing audio and video.
It uses dummy outputs, opens no window and reads no TVHeadend credentials.
For GUI checks, `scripts/qa-server.py` runs a local HTTP test server with Digest
authentication. Pass `--showcase` to load the screenshot demo.

## Notarized releases

Create a Keychain profile once. Enter the app-specific password at the protected
terminal prompt. Keep it out of command arguments and repository files:

```bash
xcrun notarytool store-credentials Tunerfenster \
  --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

Once your Developer ID Application certificate is available, run:

```bash
./release-all.sh --profile Tunerfenster
```

The script builds, signs and notarizes the app for each CPU architecture, then
staples its ticket. It creates a DMG with an Applications shortcut for drag-and-drop
installation, signs and notarizes that DMG separately, then staples its ticket.
It checks signatures, tickets and Gatekeeper, including a fresh copy of the app
from the mounted DMG. Set `PLAYBACK_CHECK_FILE=/path/to/test.ts` to check decoding
in both the final app and the copy from the DMG.

Outputs:

```text
dist/release/Tunerfenster-<version>-arm64.dmg
dist/release/Tunerfenster-<version>-x86_64.dmg
dist/release/<architecture>/Tunerfenster-<version>-<architecture>.zip
```

Each DMG comes with a SHA-256 file and Apple's submission and status logs. These
contain no passwords or signing keys. Keep the logs locally and upload the
installers and checksums you want to publish to the GitHub release.

Individual stages:

```bash
TARGET_ARCH=arm64 ./release-app.sh --profile Tunerfenster
TARGET_ARCH=arm64 ./release-dmg.sh --profile Tunerfenster
TARGET_ARCH=arm64 ./release-dmg.sh --resume Tunerfenster
```

For a pending DMG submission, the script saves the uploaded file's hash. It
checks that hash before resuming, so the file can stay uploaded while Apple
processes it. You can also use `release-app.sh --xcode` with the Apple Account
signed into Xcode. Use `--resume` to continue that Xcode export.

## Third-party source and local modifications

The [VideoLAN notices](../Resources/ThirdPartyNotices.txt) list the official
package, checksum, source revisions and LGPL terms. The build selects one CPU
slice and applies the distribution signature; it makes no other binary changes
to the framework. To replace the library locally, re-sign the framework first,
then the app. Include the third-party notices when redistributing a copy.

## GitHub update metadata

The updater reads the public `NemoN/Tunerfenster` latest-release API. Use a
stable tag such as `v1.9.0` that matches the app's `CFBundleShortVersionString`.
Attach both installers before publishing:

```text
Tunerfenster-1.9.0-arm64.dmg
Tunerfenster-1.9.0-x86_64.dmg
```

The app ignores drafts, pre-releases, invalid version numbers and older
versions. It accepts downloads only from the expected repository and tag, with
the filename for the detected CPU architecture. If the matching installer is
missing, the app links to the release page and says which download is missing.
Use these filenames for future releases.

Update checks use a separate URLSession without cookies, cached credentials or
TVHeadend configuration. Automatic attempts run at least 24 hours apart, even
after a failed check. You can retry manually at any time. On launch, the app
compares locally cached release data with the installed version and the Mac's
hardware. It detects Apple Silicon even from an Intel process under Rosetta.
The user downloads and installs updates manually.

API and platform references: [GitHub Releases API](https://docs.github.com/en/rest/releases/releases)
and [Apple's Rosetta translation detection](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment).
