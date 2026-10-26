#!/bin/bash
# Run only as part of an explicitly requested release, after both DMGs passed.
set -euo pipefail
cd "$(dirname "$0")/.."
tools="$PWD/.build/arm64/artifacts/sparkle/Sparkle/bin"
if [ ! -x "$tools/generate_appcast" ]; then tools="$PWD/.build/artifacts/sparkle/Sparkle/bin"; fi
key=$("$tools/generate_keys" --account Tunerfenster -p)
expected_key=$(tr -d '\r\n' < Resources/SparklePublicKey.txt)
if [ "$key" != "$expected_key" ]; then
    printf 'Sparkle signing key does not match the public key in the app.\n' >&2
    exit 1
fi
work=$(mktemp -d "$PWD/dist/release/.appcasts.XXXXXX")
trap 'rm -rf "$work"' EXIT
for architecture in arm64 x86_64; do
    app="$PWD/dist/$architecture/Tunerfenster.app"
    version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
    app_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app/Contents/Info.plist")
    test "$app_key" = "$key"
    dmg="$PWD/dist/release/Tunerfenster-$version-$architecture.dmg"
    xcrun stapler validate "$dmg"
    directory="$work/$architecture"
    mkdir -p "$directory"
    cp "$dmg" "$directory/"
    notes="docs/releases/$version.md"
    if [ ! -f "$notes" ]; then notes="docs/releases/v$version.md"; fi
    if [ -f "$notes" ]; then cp "$notes" "$directory/Tunerfenster-$version-$architecture.md"; fi
    "$tools/generate_appcast" --account Tunerfenster --maximum-deltas 0 --maximum-versions 1 \
        --download-url-prefix "https://github.com/NemoN/Tunerfenster/releases/download/v$version/" \
        --link "https://github.com/NemoN/Tunerfenster/releases/tag/v$version" \
        --embed-release-notes -o "$directory/appcast.xml" "$directory"
    "$tools/sign_update" --account Tunerfenster "$directory/appcast.xml"
    python3 scripts/validate-update-feed.py "$directory/appcast.xml" "$dmg" "$app" "$tools/sign_update"
    cp "$directory/appcast.xml" "$PWD/dist/release/appcast-$architecture.xml"
done
printf 'Signed update feeds ready: dist/release/appcast-{arm64,x86_64}.xml\n'
