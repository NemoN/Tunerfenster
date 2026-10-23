#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:?Usage: bundle-vlc.sh APP ARCH}"
architecture="${2:?Provide arm64 or x86_64.}"
case "$architecture" in arm64|x86_64) ;; *) exit 2 ;; esac

# Version and checksum from VideoLAN's VLCKit 3.7.4 podspec, pinned for releases.
archive=VLCKit-3.0-20260922-1444.tar.xz
sha256=d57a80455900e031ec87b08bdc684ba58989f9cec317b04739b2ee6b1d7a1868
cache="$PWD/.cache/vlckit"
package="$cache/3.7.4/VLCKit - binary package"
mkdir -p "$cache"
if [ ! -f "$cache/$archive" ]; then
    curl --fail --location --retry 2 --connect-timeout 20 \
        "https://download.videolan.org/pub/cocoapods/prod/$archive" -o "$cache/$archive.partial"
    mv "$cache/$archive.partial" "$cache/$archive"
fi
printf '%s  %s\n' "$sha256" "$cache/$archive" | shasum -a 256 --check
if [ ! -d "$package/VLCKit.xcframework" ]; then
    mkdir -p "$cache/3.7.4"
    tar -xf "$cache/$archive" -C "$cache/3.7.4"
fi
framework="$app/Contents/Frameworks/VLCKit.framework"
test ! -e "$framework"
mkdir -p "$app/Contents/Frameworks" "$app/Contents/Resources/Licenses"
ditto "$package/VLCKit.xcframework/macos-arm64_x86_64/VLCKit.framework" "$framework"
binary="$framework/Versions/A/VLCKit"
lipo "$binary" -thin "$architecture" -output "$binary.thin"
mv "$binary.thin" "$binary"
chmod 755 "$binary"
# Headers and module maps are development files; runtime resources remain intact.
rm -rf "$framework/Versions/A/Headers" "$framework/Versions/A/PrivateHeaders" "$framework/Versions/A/Modules"
rm -f "$framework/Headers" "$framework/PrivateHeaders" "$framework/Modules"
cp "$package/COPYING.txt" "$app/Contents/Resources/Licenses/VLCKit-LGPL-2.1.txt"
cp Resources/ThirdPartyNotices.txt "$app/Contents/Resources/Licenses/ThirdPartyNotices.txt"
cp Resources/Credits.rtf "$app/Contents/Resources/Credits.rtf"
printf 'Bundled VLCKit 3.7.4 (%s).\n' "$architecture"
