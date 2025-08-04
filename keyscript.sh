#!/bin/sh

cleanup () {
    rm -f "$ASSERT_PARAMS" "$LUKS_TOKEN"
}

ASSERT_PARAMS=$(mktemp -t params.XXXXXX)
LUKS_TOKEN=$(mktemp -t token.XXXXXX)
trap cleanup INT EXIT

cryptsetup luksDump --dump-json-metadata "$CRYPTTAB_SOURCE" | \
    jq -e '[.tokens[] | select(."fido2-credential" != null)][0]' > "$LUKS_TOKEN"

if [ $? -ne 0 ]; then
    echo "*** No FIDO2 credentials found in $CRYPTTAB_SOURCE" >&2
else
    echo "*** Waiting for a FIDO2 authenticator..." >&2
    for _f in $(seq 5); do
        FIDO2_AUTHENTICATOR=$(fido2-token -L)
        [ -n "$FIDO2_AUTHENTICATOR" ] && break
        sleep 1
    done

    if [ -n "$FIDO2_AUTHENTICATOR" ]; then
        echo "*** Found FIDO2 authenticator $FIDO2_AUTHENTICATOR" >&2
        FIDO2_DEV=${FIDO2_AUTHENTICATOR%%:*}

        REQ_PIN=$(jq -r '."fido2-clientPin-required"' "$LUKS_TOKEN")
        REQ_UP=$(jq -r '."fido2-up-required"' "$LUKS_TOKEN")

        jq -r '"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
               ."fido2-rp",
               ."fido2-credential",
               ."fido2-salt"' "$LUKS_TOKEN" > "$ASSERT_PARAMS"

        if [ "$REQ_PIN" = "true" ]; then
            stty -echo
        fi

        sleep 2

        SECRET=$(fido2-assert -G -h -t up="$REQ_UP" -t pin="$REQ_PIN" \
                              -i "$ASSERT_PARAMS" "$FIDO2_DEV" | tail -n 1)

        if [ "$REQ_PIN" = "true" ]; then
            stty echo
        fi

        if [ -n "$SECRET" ]; then
            echo >&2
            printf "%s" "$SECRET"
            exit 0
        else
            echo "*** Error obtaining secret from $FIDO2_DEV" >&2
        fi
    else
        echo "*** No FIDO2 authenticator found" >&2
    fi
fi

echo "*** Unlocking $CRYPTTAB_NAME using a regular passphrase" >&2

/lib/cryptsetup/askpass "Enter passphrase: "
