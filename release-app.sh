#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
method="${1:---xcode}"
if [ "$method" != "--xcode" ] && [ "$method" != "--profile" ] && [ "$method" != "--resume" ]; then
    printf 'Usage: ./release-app.sh [--xcode | --profile KEYCHAIN_PROFILE | --resume]\n' >&2
    exit 2
fi
if [ "$method" = "--profile" ]; then
    profile="${2:?Provide a notarytool Keychain profile name.}"
fi
if [ "${SIGN_IDENTITY:-}" = "-" ]; then
    printf 'Notarization requires a Developer ID Application identity.\n' >&2
    exit 2
fi

architecture="${TARGET_ARCH:-$(uname -m)}"
case "$architecture" in arm64|x86_64) ;; *) printf 'Unsupported architecture.\n' >&2; exit 2 ;; esac
app_dir="${APP_BUNDLE:-$PWD/dist/$architecture/Tunerfenster.app}"
output_dir="$PWD/dist/release/$architecture"
archive="$output_dir/Tunerfenster.xcarchive"
mkdir -p "$output_dir"
if [ "$method" != "--resume" ]; then
    if [ -e "$output_dir/xcode-uploaded" ]; then
        printf 'An uploaded archive is waiting. Finish it with ./release-app.sh --resume before rebuilding.\n' >&2
        exit 1
    fi
    TARGET_ARCH="$architecture" APP_BUNDLE="$app_dir" ./build-app.sh --no-bootstrap
    /usr/bin/arch "-$architecture" "$app_dir/Contents/MacOS/Tunerfenster" --check-vlc
    codesign -dvv "$app_dir" 2> "$output_dir/signature.txt"
    if ! /usr/bin/grep -q '^Authority=Developer ID Application:' "$output_dir/signature.txt"; then
        printf 'The build is not signed with a Developer ID Application certificate.\n' >&2
        exit 1
    fi
    if ! /usr/bin/grep -q 'flags=.*runtime' "$output_dir/signature.txt"; then
        printf 'Hardened Runtime is missing.\n' >&2
        exit 1
    fi

    rm -rf "$archive"
    mkdir -p "$archive/Products/Applications"
    ditto "$app_dir" "$archive/Products/Applications/Tunerfenster.app"
    python3 - "$archive" "$output_dir" "$architecture" <<'PY'
import datetime, pathlib, plistlib, re, sys
archive, output = map(pathlib.Path, sys.argv[1:3])
architecture = sys.argv[3]
with (archive / 'Products/Applications/Tunerfenster.app/Contents/Info.plist').open('rb') as f:
    info = plistlib.load(f)
signature = (output / 'signature.txt').read_text()
identity = re.search(r'^Authority=(Developer ID Application:.+)$', signature, re.M).group(1)
team = re.search(r'^TeamIdentifier=(\S+)$', signature, re.M).group(1)
document = {
    'ArchiveVersion': 2, 'CreationDate': datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
    'Name': 'Tunerfenster', 'SchemeName': 'Tunerfenster',
    'ApplicationProperties': {
        'ApplicationPath': 'Applications/Tunerfenster.app', 'Architectures': [architecture],
        'CFBundleIdentifier': info['CFBundleIdentifier'],
        'CFBundleShortVersionString': info['CFBundleShortVersionString'],
        'CFBundleVersion': info['CFBundleVersion'], 'SigningIdentity': identity, 'Team': team,
    },
}
with (archive / 'Info.plist').open('wb') as f:
    plistlib.dump(document, f)
with (output / 'ExportOptions.plist').open('wb') as f:
    plistlib.dump({'method': 'developer-id', 'destination': 'upload', 'teamID': team,
                  'signingStyle': 'manual', 'signingCertificate': identity,
                  'manageAppVersionAndBuildNumber': False}, f)
PY
fi

if [ "$method" = "--xcode" ] || [ "$method" = "--resume" ]; then
    # Reuse Xcode's signed-in Apple Account. No new API key or password is exported.
    if [ "$method" = "--xcode" ]; then
        xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$output_dir/ExportOptions.plist" -exportPath "$output_dir/upload"
        touch "$output_dir/xcode-uploaded"
    else
        test -d "$archive/Submissions"
    fi
    export_stage=$(mktemp -d "$output_dir/.notarized-export.XXXXXX")
    trap 'rm -rf "$export_stage"' EXIT
    export_ready=false
    for ((attempt = 1; attempt <= 40; attempt++)); do
        if xcodebuild -exportNotarizedApp -archivePath "$archive" -exportPath "$export_stage/product" > "$output_dir/notarized-export.log" 2>&1; then
            export_ready=true
            break
        fi
        if ! /usr/bin/grep -q 'is processing and not ready for distribution' "$output_dir/notarized-export.log"; then
            cat "$output_dir/notarized-export.log" >&2
            exit 1
        fi
        printf 'Apple is processing the archive (check %s/40).\n' "$attempt"
        sleep 30
    done
    if [ "$export_ready" != true ]; then
        printf 'Apple is still processing. Resume without another upload: ./release-app.sh --resume\n' >&2
        exit 75
    fi
    rm -rf "$output_dir/notarized"
    mv "$export_stage/product" "$output_dir/notarized"
    ditto "$output_dir/notarized/Tunerfenster.app" "$app_dir"
else
    upload_zip="$output_dir/Tunerfenster-upload.zip"
    ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$upload_zip"
    xcrun notarytool submit "$upload_zip" --keychain-profile "$profile" --no-wait --output-format json > "$output_dir/submission.json"
    submission=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$output_dir/submission.json")
    printf 'Apple submission: %s\n' "$submission"
    xcrun notarytool wait "$submission" --keychain-profile "$profile" --timeout 20m --output-format json > "$output_dir/status.json"
    xcrun notarytool log "$submission" --keychain-profile "$profile" "$output_dir/notarization-log.json"
    python3 - "$output_dir/status.json" <<'PY'
import json, sys
status = json.load(open(sys.argv[1]))
if status.get('status') != 'Accepted':
    raise SystemExit(f"Notarization has not been accepted: {status.get('status')}. See dist/release/notarization-log.json.")
PY
fi

xcrun stapler staple "$app_dir"
xcrun stapler validate "$app_dir"
codesign --verify --deep --strict --verbose=2 "$app_dir"
spctl --assess --type execute --verbose=2 "$app_dir"
/usr/bin/arch "-$architecture" "$app_dir/Contents/MacOS/Tunerfenster" --check-vlc
if [ -n "${PLAYBACK_CHECK_FILE:-}" ]; then
    /usr/bin/arch "-$architecture" "$app_dir/Contents/MacOS/Tunerfenster" --check-playback "$PLAYBACK_CHECK_FILE"
fi
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
zip_name="Tunerfenster-$version-$architecture.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$output_dir/$zip_name"
(
    cd "$output_dir"
    shasum -a 256 "$zip_name" > "$zip_name.sha256"
)
rm -f "$output_dir/xcode-uploaded"
printf 'Signed, notarized and verified: %s\n' "$output_dir/$zip_name"
