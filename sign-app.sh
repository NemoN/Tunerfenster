#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app_dir="${1:?Usage: ./sign-app.sh /path/to/Tunerfenster.app}"
identity=$(./scripts/signing-identity.sh)
test -f "$app_dir/Contents/MacOS/Tunerfenster"

# Resource bundles are signed inside out. --deep is used for verification only.
resource_bundle="$app_dir/Contents/Resources/Tunerfenster_Tunerfenster.bundle"
framework="$app_dir/Contents/Frameworks/VLCKit.framework"
test -f "$framework/VLCKit"
if [ "$identity" = "-" ]; then
    codesign --force --sign - "$framework"
    codesign --force --sign - "$resource_bundle"
    codesign --force --sign - "$app_dir"
else
    codesign --force --timestamp --options runtime --sign "$identity" "$framework"
    codesign --force --timestamp --sign "$identity" "$resource_bundle"
    codesign --force --timestamp --options runtime --sign "$identity" "$app_dir"
fi
codesign --verify --deep --strict --verbose=2 "$app_dir"
