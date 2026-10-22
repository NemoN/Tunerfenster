#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

method="${1:---profile}"
case "$method" in
    --prepare) ;;
    --profile|--resume) profile="${2:?Provide a notarytool Keychain profile name.}" ;;
    *) printf 'Usage: ./release-dmg.sh --prepare | --profile PROFILE | --resume PROFILE\n' >&2; exit 2 ;;
esac

architecture="${TARGET_ARCH:-$(uname -m)}"
case "$architecture" in arm64|x86_64) ;; *) printf 'Unsupported architecture.\n' >&2; exit 2 ;; esac
app="${APP_BUNDLE:-$PWD/dist/$architecture/Tunerfenster.app}"
output="$PWD/dist/release"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
dmg="$output/Tunerfenster-$version-$architecture.dmg"
submission_file="$dmg.submission.json"
pending="$dmg.pending.sha256"
mkdir -p "$output"

work=$(mktemp -d "$output/.dmg-build.XXXXXX")
mounted=false
cleanup() {
    if [ "$mounted" = true ]; then
        if ! diskutil eject "$work/mount"; then
            printf 'Temporary image is still mounted at %s; keeping its files.\n' "$work/mount" >&2
            return
        fi
    fi
    rm -rf "$work"
}
trap cleanup EXIT

verify_contents() {
    diskutil image attach --readOnly --nobrowse --mountPoint "$work/mount" "$dmg"
    mounted=true
    test "$(readlink "$work/mount/Applications")" = /Applications
    test -f "$work/mount/.DS_Store"
    test -f "$work/mount/Tunerfenster.app/Contents/Frameworks/VLCKit.framework/VLCKit"
    lipo -verify_arch "$architecture" "$work/mount/Tunerfenster.app/Contents/MacOS/Tunerfenster"
    lipo -verify_arch "$architecture" "$work/mount/Tunerfenster.app/Contents/Frameworks/VLCKit.framework/VLCKit"
    # Test the same copy operation that a drag into Applications performs.
    ditto "$work/mount/Tunerfenster.app" "$work/installed/Tunerfenster.app"
    codesign --verify --deep --strict --verbose=2 "$work/installed/Tunerfenster.app"
    xcrun stapler validate "$work/installed/Tunerfenster.app"
    spctl --assess --type execute --verbose=2 "$work/installed/Tunerfenster.app"
    /usr/bin/arch "-$architecture" "$work/installed/Tunerfenster.app/Contents/MacOS/Tunerfenster" --check-vlc
    if [ -n "${PLAYBACK_CHECK_FILE:-}" ]; then
        /usr/bin/arch "-$architecture" "$work/installed/Tunerfenster.app/Contents/MacOS/Tunerfenster" --check-playback "$PLAYBACK_CHECK_FILE"
    fi
    diskutil eject "$work/mount"
    mounted=false
}

if [ "$method" = --prepare ] || { [ "$method" = --profile ] && [ ! -f "$dmg" ]; }; then
    if [ -f "$pending" ]; then
        printf 'This DMG has a pending submission. Use --resume PROFILE before rebuilding.\n' >&2
        exit 1
    fi
    codesign --verify --deep --strict --verbose=2 "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose=2 "$app"
    test ! -e "$app/Contents/Resources/Bootstrap.plist"
    codesign -dvv "$app" 2> "$work/app-signature.txt"
    identity="${SIGN_IDENTITY:-$(sed -n 's/^Authority=\(Developer ID Application:.*\)/\1/p' "$work/app-signature.txt" | head -n 1)}"
    case "$identity" in
        'Developer ID Application:'*) ;;
        *) printf 'DMG signing requires a Developer ID Application identity.\n' >&2; exit 1 ;;
    esac
    # Populate a mounted image explicitly: folder-to-image conversion omits .DS_Store.
    # This packaging command requires macOS 27+. The shipped app still supports macOS 14+.
    app_kb=$(du -sk "$app" | awk '{print $1}')
    size_mb=$(( (app_kb + 1023) / 1024 + 64 ))
    diskutil image create blank --size "${size_mb}M" --volumeName Tunerfenster "$work/writable.dmg"
    diskutil image attach --nobrowse --mountPoint "$work/mount" "$work/writable.dmg"
    mounted=true
    ditto "$app" "$work/mount/Tunerfenster.app"
    ln -s /Applications "$work/mount/Applications"
    cp Resources/DMGLayout.bin "$work/mount/.DS_Store"
    diskutil eject "$work/mount"
    mounted=false
    diskutil image create from --format UDZO "$work/writable.dmg" "$work/release.dmg"
    codesign --force --timestamp --identifier de.local.Tunerfenster.diskimage --sign "$identity" "$work/release.dmg"
    codesign --verify --strict --verbose=2 "$work/release.dmg"
    mv -f "$work/release.dmg" "$dmg"
    rm -f "$submission_file" "$dmg.sha256" "$dmg.notarization-log.json" "$dmg.status.json"
fi

codesign --verify --strict --verbose=2 "$dmg"
if [ "$method" = --prepare ]; then
    verify_contents
    printf 'Signed DMG prepared (container notarization still required): %s\n' "$dmg"
    printf 'Continue with: ./release-dmg.sh --profile PROFILE\n'
    exit 0
fi

if [ -f "$pending" ]; then
    shasum -a 256 --check "$pending"
elif [ "$method" = --resume ]; then
    printf 'No pending DMG submission. Use --profile PROFILE to submit.\n' >&2
    exit 1
else
    xcrun notarytool submit "$dmg" --keychain-profile "$profile" --no-wait --output-format json > "$work/submission.json"
    # Keep both the submission ID and immutable upload hash for resumable waits.
    python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["id"]' "$work/submission.json"
    mv "$work/submission.json" "$submission_file"
    shasum -a 256 "$dmg" > "$pending"
fi

submission=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$submission_file")
printf 'Apple DMG submission: %s\n' "$submission"
xcrun notarytool wait "$submission" --keychain-profile "$profile" --timeout 20m --output-format json > "$dmg.status.json"
xcrun notarytool log "$submission" --keychain-profile "$profile" "$dmg.notarization-log.json"
python3 - "$dmg.status.json" <<'PY'
import json, sys
status = json.load(open(sys.argv[1]))
if status.get('status') != 'Accepted':
    raise SystemExit(f"DMG notarization has not been accepted: {status.get('status')}. See the notarization log.")
PY
xcrun stapler staple "$dmg"
# Stapling changes the file hash; retain a resumable checkpoint for later checks.
shasum -a 256 "$dmg" > "$pending"
xcrun stapler validate "$dmg"
codesign --verify --strict --verbose=2 "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
verify_contents
(
    cd "$output"
    shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256"
)
rm -f "$pending"
printf 'Signed, notarized and verified DMG: %s\n' "$dmg"
