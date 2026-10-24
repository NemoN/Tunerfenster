#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bootstrap_env="${1:-}"
if [ "$bootstrap_env" = "--no-bootstrap" ]; then bootstrap_env=""; fi
architecture="${TARGET_ARCH:-$(uname -m)}"
case "$architecture" in arm64|x86_64) ;; *) printf 'Unsupported architecture: %s\n' "$architecture" >&2; exit 2 ;; esac
# Resolve once before building. A missing pinned certificate must not silently
# change the app's identity or leave a complete build waiting for configuration.
export SIGNING_MODE="${SIGNING_MODE:-local}"
SIGN_IDENTITY=$(./scripts/signing-identity.sh)
export SIGN_IDENTITY
build_options=(-c release --triple "$architecture-apple-macosx14.0" --scratch-path "$PWD/.build/$architecture")
if [ "$SIGNING_MODE" = local ]; then
    # Local network privacy also tracks LC_UUID. Keep each newly linked local
    # executable distinct from separately packaged test apps (Apple TN3179).
    build_options+=(-Xlinker -random_uuid)
fi
swift build "${build_options[@]}"
bin_dir=$(swift build "${build_options[@]}" --show-bin-path)
app_dir="${APP_BUNDLE:-$PWD/dist/Tunerfenster.app}"
mkdir -p "$PWD/dist"
staging_dir=$(mktemp -d "$PWD/dist/.Tunerfenster-build.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
staged_app="$staging_dir/Tunerfenster.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$bin_dir/Tunerfenster" "$staged_app/Contents/MacOS/Tunerfenster"
ditto "$bin_dir/Tunerfenster_Tunerfenster.bundle" "$staged_app/Contents/Resources/Tunerfenster_Tunerfenster.bundle"
for language in en de; do
    ditto "Sources/Tunerfenster/Resources/$language.lproj" "$staged_app/Contents/Resources/$language.lproj"
done
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$staged_app/Contents/Resources/AppIcon.icns"; fi
python3 - "$staged_app" "$bootstrap_env" <<'PY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
info = {
    'CFBundleName': 'Tunerfenster', 'CFBundleDisplayName': 'Tunerfenster',
    'CFBundleIdentifier': 'de.local.Tunerfenster', 'CFBundleExecutable': 'Tunerfenster',
    'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '1.10.0',
    'CFBundleDevelopmentRegion': 'en', 'CFBundleLocalizations': ['en', 'de'],
    'CFBundleIconFile': 'AppIcon',
    'CFBundleVersion': '13', 'LSMinimumSystemVersion': '14.0',
    'NSPrincipalClass': 'NSApplication', 'NSHighResolutionCapable': True,
    'NSLocalNetworkUsageDescription': 'Tunerfenster liest den Status deines TVHeadend-Servers und zeigt laufende TV-Streams im lokalen Netzwerk.',
    'NSAppTransportSecurity': {'NSAllowsArbitraryLoads': True},
}
with (app / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump(info, f)
# Only a local path is embedded, never the environment file or its secrets.
if sys.argv[2]:
    with (app / 'Contents/Resources/Bootstrap.plist').open('wb') as f:
        plistlib.dump({'EnvironmentFile': str(pathlib.Path(sys.argv[2]).resolve())}, f)
PY
./scripts/bundle-vlc.sh "$staged_app" "$architecture"
./sign-app.sh "$staged_app"
# Replace only the generated output after the complete new bundle has passed signing.
rm -rf "$app_dir"
mkdir -p "$(dirname "$app_dir")"
mv "$staged_app" "$app_dir"
printf 'Fertig: %s\n' "$app_dir"
