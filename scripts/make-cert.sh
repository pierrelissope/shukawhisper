#!/usr/bin/env bash
# Creates a self-signed code-signing certificate in your login keychain.
#
# Why: macOS ties Accessibility and Microphone permissions to the app's signature.
# Ad-hoc signed builds get a new signature on every build, so you'd have to re-grant
# permissions each time. Signing with a stable local certificate avoids that.
set -euo pipefail

NAME="${SIGNING_IDENTITY:-ShukaWhisper Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "✓ Certificate \"$NAME\" already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TMP/cert.conf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/identity.p12" -passout pass:shukawhisper 2>/dev/null

security import "$TMP/identity.p12" -k "$KEYCHAIN" -P shukawhisper -T /usr/bin/codesign >/dev/null
echo "✓ Created code-signing certificate \"$NAME\" in your login keychain."
echo "  (If macOS asks whether codesign may use the key, choose \"Always Allow\".)"
