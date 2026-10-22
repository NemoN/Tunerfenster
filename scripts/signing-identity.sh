#!/bin/bash
set -euo pipefail
if [ -n "${SIGN_IDENTITY:-}" ]; then
    printf '%s\n' "$SIGN_IDENTITY"
    exit 0
fi
identities=()
while IFS= read -r identity; do
    [ -n "$identity" ] && identities+=("$identity")
done < <(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p')
case "${#identities[@]}" in
    0) printf '%s\n' '-' ;;
    1) printf '%s\n' "${identities[0]}" ;;
    *) printf 'Multiple Developer ID Application identities found. Set SIGN_IDENTITY explicitly.\n' >&2; exit 2 ;;
esac
