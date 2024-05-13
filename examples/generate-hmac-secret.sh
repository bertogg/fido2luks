#!/bin/bash

set -eu

# Set CREDENTIAL_ID and PUBLIC_KEY to the values that you got
# from generate-cred.sh, otherwise this won't work

RELYING_PARTY_ID="org.test.some_app"
CREDENTIAL_ID="E2NDqozxIGOlcUhlrg6+XIjZSRC8i5C69PgOiHzWXGBZTJ6No9fa6fEcPvQjxL5slKGVr7ioYBcxKwPREJnuMA=="
SALT="The HMAC secret depends on this value"
CLIENT_DATA="" # This can be empty

# Set these to true or false
REQUIRE_PIN=false
REQUIRE_USER_PRESENCE=true

# The public key is only needed to verify the result, see below
PUBLIC_KEY='
-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEjX1Eiv/1H39f+b+MmSTymbdR8l3+
GqJHf3X0CyREljyHi7mS5LgkmsyvO0fgc6SryYCUKG6MREdnKirNilXLYQ==
-----END PUBLIC KEY-----
'

FIDO2_DEVICE=$(fido2-token -L | head -n 1 | cut -d : -f 1)

if [ -z "$FIDO2_DEVICE" ]; then
    echo "ERROR: no FIDO2 device found"
    exit 1
fi

ASSERT_PARAMS="$(mktemp /tmp/cred-params.XXXXXX)"
ASSERT_DATA="$(mktemp /tmp/cred-data.XXXXXX)"
trap "rm -f $ASSERT_PARAMS $ASSERT_DATA" INT EXIT

printf "%s\n%s\n%s\n%s\n" \
       $(echo -n "$CLIENT_DATA" | openssl sha256 -binary | base64) \
       "$RELYING_PARTY_ID" \
       "$CREDENTIAL_ID" \
       $(echo -n "$SALT" | openssl sha256 -binary | base64) > "$ASSERT_PARAMS"

fido2-assert -G -h \
   -t up="$REQUIRE_USER_PRESENCE" -t pin="$REQUIRE_PIN" \
   -i "$ASSERT_PARAMS" -o "$ASSERT_DATA" "$FIDO2_DEVICE"

# If you want to verify the result with the public key:
# fido2-assert -V -h -i "$ASSERT_DATA" <(echo "$PUBLIC_KEY") es256

HMAC_SECRET="$(tail -n 1 "$ASSERT_DATA")"
echo "The generated secret is $HMAC_SECRET"
