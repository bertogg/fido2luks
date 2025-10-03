#!/bin/sh

# Copyright (C) 2024-2025 Alberto Garcia <berto@igalia.com>
# SPDX-License-Identifier: GPL-2.0-or-later

cleanup () {
    rm -f "$ASSERT_PARAMS" "$LUKS_TOKEN" "$LUKS_TOKEN_LIST"
}

ASSERT_PARAMS=$(mktemp -t params.XXXXXX)
LUKS_TOKEN_LIST=$(mktemp -t tokenlist.XXXXXX)
LUKS_TOKEN=$(mktemp -t token.XXXXXX)
trap cleanup INT EXIT

try_fido2_unlock () {
    # Get all tokens from the LUKS header with FIDO2 credentials.
    # Sort the array, placing entries with "fido2-uv-required: true" at the end.
    if ! cryptsetup luksDump --dump-json-metadata "$CRYPTTAB_SOURCE" | \
            jq -e '[.tokens[] | select(."fido2-credential" != null)] | sort_by(."fido2-uv-required")' > "$LUKS_TOKEN_LIST"; then
        echo "*** Error reading LUKS header in $CRYPTTAB_SOURCE" >&2
        return 1
    fi

    # Count how many tokens we have.
    NTOKENS=$(jq length "$LUKS_TOKEN_LIST")
    if [ -z "$NTOKENS" ] || [ "$NTOKENS" = "0" ]; then
        echo "*** No FIDO2 credentials found in $CRYPTTAB_SOURCE" >&2
        return 1
    fi

    # Check if the FIDO2 authenticator is inserted
    echo "*** Waiting for a FIDO2 authenticator..." >&2
    for _f in $(seq 5); do
        FIDO2_AUTHENTICATOR=$(fido2-token -L)
        sleep 1
        [ -n "$FIDO2_AUTHENTICATOR" ] && break
    done

    if [ -z "$FIDO2_AUTHENTICATOR" ]; then
        echo "*** No FIDO2 authenticator found" >&2
        return 1
    fi

    echo "*** Found FIDO2 authenticator $FIDO2_AUTHENTICATOR" >&2
    FIDO2_DEV=${FIDO2_AUTHENTICATOR%%:*}

    # Look for a credential that is valid for the inserted FIDO2
    # authenticator. For that we try to get an assertion from the
    # device, with 'up' and 'pin' set to false, so it requires no user
    # interaction.
    for i in $(seq "$NTOKENS"); do
        jq ".[$i-1]" "$LUKS_TOKEN_LIST" > "$LUKS_TOKEN"
        jq -r '"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
               ."fido2-rp",
               ."fido2-credential",
               ."fido2-salt"' "$LUKS_TOKEN" > "$ASSERT_PARAMS"
        REQ_UV=$(jq -r '."fido2-uv-required"' "$LUKS_TOKEN")
        # If a credential has the 'uv' option set then unfortunately
        # we cannot check if it's valid for the inserted FIDO2
        # authenticator without requiring user interaction.
        # So this is what we do:
        # - The array of credentials is sorted, those that require UV
        #   are at the end.
        # - All credentials that don't require UV are tested first,
        #   we can do that silently with the fido2-assert call.
        # - Once we find a credential that requires UV we assume
        #   that we can use it with the inserted authenticator.
        # - Not all authenticators support 'uv' so pass '-t uv' only
        #   when needed using the UV_OPT variable.
        if [ "$REQ_UV" = "true" ]; then
            UV_OPT="-t uv=true"
            break
        else
            UV_OPT=""
            if fido2-assert -G -t up=false -t pin=false -i "$ASSERT_PARAMS" \
                            -o /dev/null "$FIDO2_DEV" 2> /dev/null; then
                break
            fi
        fi
        rm -f "$LUKS_TOKEN" "$ASSERT_PARAMS"
    done

    if [ ! -f "$LUKS_TOKEN" ] || [ ! -f "$ASSERT_PARAMS" ]; then
        echo "*** No valid credential found for this FIDO2 authenticator" >&2
        return 1
    fi

    # Now that we have a valid credential use it to compute the
    # hmac-secret, which is what unlocks the LUKS volume.
    REQ_PIN=$(jq -r '."fido2-clientPin-required"' "$LUKS_TOKEN")
    REQ_UP=$(jq -r '."fido2-up-required"' "$LUKS_TOKEN")

    if [ "$REQ_PIN" = "true" ]; then
        stty -echo
    fi

    SECRET=$(fido2-assert -G -h -t up="$REQ_UP" -t pin="$REQ_PIN" $UV_OPT \
                          -i "$ASSERT_PARAMS" "$FIDO2_DEV" | tail -n 1)

    if [ "$REQ_PIN" = "true" ]; then
        stty echo
    fi

    if [ -z "$SECRET" ]; then
        echo "*** Error obtaining secret from $FIDO2_DEV" >&2
        return 1
    fi

    echo >&2
    printf "%s" "$SECRET"
    return 0
}

# Main execution
if try_fido2_unlock; then
    exit 0
fi

echo "*** Unlocking $CRYPTTAB_NAME using a regular passphrase" >&2
/usr/lib/cryptsetup/askpass "Enter passphrase: "
