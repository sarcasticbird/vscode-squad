#!/bin/bash
set -euo pipefail

CERT_NAME="CodeSquad Dev"

if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "Certificate '$CERT_NAME' already exists."
    exit 0
fi

echo "Creating self-signed code signing certificate: '$CERT_NAME'"
echo "You may be prompted for your login keychain password."

# Create a certificate signing request and self-signed cert via Security framework
cat > /tmp/codesquad-cert.cfg <<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_dn
prompt             = no
[ req_dn ]
CN = $CERT_NAME
[ v3_codesign ]
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = CA:false
EOF

# Generate key and self-signed cert
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout /tmp/codesquad-key.pem \
    -out /tmp/codesquad-cert.pem \
    -days 3650 \
    -config /tmp/codesquad-cert.cfg \
    -extensions v3_codesign \
    2>/dev/null

# Bundle into p12
openssl pkcs12 -export \
    -out /tmp/codesquad-cert.p12 \
    -inkey /tmp/codesquad-key.pem \
    -in /tmp/codesquad-cert.pem \
    -passout pass: \
    2>/dev/null

# Import into login keychain with trust for code signing
security import /tmp/codesquad-cert.p12 \
    -k ~/Library/Keychains/login.keychain-db \
    -P "" \
    -T /usr/bin/codesign

# Set the certificate as trusted for code signing
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db \
    /tmp/codesquad-cert.pem

# Clean up temp files
rm -f /tmp/codesquad-cert.cfg /tmp/codesquad-key.pem /tmp/codesquad-cert.pem /tmp/codesquad-cert.p12

echo ""
echo "Certificate '$CERT_NAME' created and trusted for code signing."
echo "AX permissions will now persist across rebuilds."
echo ""
echo "Run: scripts/build.sh"
