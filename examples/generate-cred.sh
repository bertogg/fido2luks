#!/bin/sh

set -eu

RELYING_PARTY_ID="org.test.some_app"
USER_NAME="User Name"
USER_ID="User ID"
CLIENT_DATA="" # This can be empty

FIDO2_DEVICE=$(fido2-token -L | head -n 1 | cut -d : -f 1)

if [ -z "$FIDO2_DEVICE" ]; then
    echo "ERROR: no FIDO2 device found"
    exit 1
fi

CRED_PARAMS="$(mktemp /tmp/cred-params.XXXXXX)"
CRED_DATA="$(mktemp /tmp/cred-data.XXXXXX)"
CRED_VERIFY="$(mktemp /tmp/cred-verify.XXXXXX)"
trap "rm -f $CRED_PARAMS $CRED_DATA $CRED_VERIFY" INT EXIT

printf "%s\n%s\n%s\n%s\n" \
       $(echo -n "$CLIENT_DATA" | openssl sha256 -binary | base64) \
       "$RELYING_PARTY_ID" \
       "$USER_NAME" \
       $(echo -n "$USER_ID" | openssl sha256 -binary | base64) > "$CRED_PARAMS"

fido2-cred -M -h -i "$CRED_PARAMS" -o "$CRED_DATA" "$FIDO2_DEVICE"
fido2-cred -V -h -i "$CRED_DATA" -o "$CRED_VERIFY"

CRED_ID=$(head -n 1 "$CRED_VERIFY")

echo "A new credential has been generated"
echo "ID: $CRED_ID"
echo "Public key:"
tail -n +2 "$CRED_VERIFY"
