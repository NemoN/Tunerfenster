#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ "${1:-}" != --profile ] || [ -z "${2:-}" ]; then
    printf 'Usage: ./release-all.sh --profile KEYCHAIN_PROFILE\n' >&2
    exit 2
fi
for architecture in arm64 x86_64; do
    printf '\nBuilding, signing and notarizing %s.\n' "$architecture"
    TARGET_ARCH="$architecture" ./release-app.sh --profile "$2"
    TARGET_ARCH="$architecture" ./release-dmg.sh --profile "$2"
done
./scripts/generate-update-feeds.sh
