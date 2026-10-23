#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${SIGNING_MODE:-local}"
case "$mode" in local|release) ;; *) printf 'SIGNING_MODE must be local or release.\n' >&2; exit 2 ;; esac
if [ -n "${SIGN_IDENTITY:-}" ]; then
    printf '%s\n' "$SIGN_IDENTITY"
    exit 0
fi

if [ "$mode" = local ]; then
    # Pin the certificate, not the binary hash, so rebuilt apps retain their identity.
    if [ -f .local-signing-identity ]; then
        identity=$(tr -d '\r\n' < .local-signing-identity)
        if ! [[ "$identity" =~ ^[[:xdigit:]]{40}$ ]]; then
            printf '.local-signing-identity must contain one certificate SHA-1 fingerprint.\n' >&2
            exit 2
        fi
        if ! security find-identity -v -p codesigning | /usr/bin/grep -Fqi " $identity \""; then
            printf 'The pinned local signing certificate is unavailable. Check Keychain; no ad-hoc fallback was used.\n' >&2
            exit 2
        fi
        printf '%s\n' "$identity"
    else
        printf '%s\n' '-'
    fi
    exit 0
fi

identities=()
while IFS= read -r identity; do
    [ -n "$identity" ] && identities+=("$identity")
done < <(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p')
case "${#identities[@]}" in
    0) printf 'A release requires a Developer ID Application identity.\n' >&2; exit 2 ;;
    1) printf '%s\n' "${identities[0]}" ;;
    *) printf 'Multiple Developer ID Application identities found. Set SIGN_IDENTITY explicitly.\n' >&2; exit 2 ;;
esac
