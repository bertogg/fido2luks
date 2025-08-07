#!/bin/sh

cleanup () {
    rm -f "$ASSERT_PARAMS" "$LUKS_TOKEN" "$LUKS_TOKEN_LIST"
}

ASSERT_PARAMS=$(mktemp -t params.XXXXXX)
LUKS_TOKEN_LIST=$(mktemp -t tokenlist.XXXXXX)
LUKS_TOKEN=$(mktemp -t token.XXXXXX)
trap cleanup INT EXIT

try_fido2_unlock () {
    cryptsetup luksDump --dump-json-metadata "$CRYPTTAB_SOURCE" | \
        jq -e '[.tokens[] | select(."fido2-credential" != null)]' > "$LUKS_TOKEN_LIST"

    NTOKENS=$(jq length "$LUKS_TOKEN_LIST")
    if [ -z "$NTOKENS" ] || [ "$NTOKENS" = "0" ]; then
        echo "*** No FIDO2 credentials found in $CRYPTTAB_SOURCE" >&2
        return 1
    fi

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

    for i in $(seq "$NTOKENS"); do
        jq ".[$i-1]" "$LUKS_TOKEN_LIST" > "$LUKS_TOKEN"
        jq -r '"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
               ."fido2-rp",
               ."fido2-credential",
               ."fido2-salt"' "$LUKS_TOKEN" > "$ASSERT_PARAMS"
        if fido2-assert -G -t up=false -t pin=false -i "$ASSERT_PARAMS" \
                        -o /dev/null "$FIDO2_DEV" 2> /dev/null; then
            break
        fi
        rm -f "$LUKS_TOKEN" "$ASSERT_PARAMS"
    done

    if [ ! -f "$LUKS_TOKEN" ] || [ ! -f "$ASSERT_PARAMS" ]; then
        echo "*** No valid credential found for this FIDO2 authenticator" >&2
        return 1
    fi

    REQ_PIN=$(jq -r '."fido2-clientPin-required"' "$LUKS_TOKEN")
    REQ_UP=$(jq -r '."fido2-up-required"' "$LUKS_TOKEN")

    if [ "$REQ_PIN" = "true" ]; then
        stty -echo
    fi

    SECRET=$(fido2-assert -G -h -t up="$REQ_UP" -t pin="$REQ_PIN" \
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
/lib/cryptsetup/askpass "Enter passphrase: "
