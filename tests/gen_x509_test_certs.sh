#!/usr/bin/env bash
#
# Generate the certificates used by the Windows client's X.509 trust-anchor
# unit tests (client/windows/src/main.rs, #[cfg(test)] mod tests). These mirror
# the server's Luminum::Setup::prepare_ssl / prepare_signing:
#
#   luminum-ca.crt                RSA 2048 self-signed CA (the TLS root)
#   server.crt                    RSA 2048 leaf issued by the CA (CA:FALSE,
#                                 serverAuth; the presented certificate)
#   server-signing.crt            Ed25519, issued by luminum-ca.crt (generate mode)
#   server-signing-selfsigned.crt Ed25519, self-signed (import mode)
#   other-root.crt                a different RSA CA (must NOT validate the
#                                 server-signing.crt chain)
#   *.pub.hex                     raw 32-byte Ed25519 public key (ground truth,
#                                 extracted with openssl)
#
# Usage: bash tests/gen_x509_test_certs.sh [outdir]
#
set -euo pipefail

OUT="${1:-$HOME/luminum-x509-test}"
rm -rf "$OUT"
mkdir -p "$OUT"
cd "$OUT"

CN="luminum.test"

# --- luminum-ca.crt: RSA 2048 self-signed CA (mirrors prepare_ssl) -----------
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
	-keyout luminum-ca.key -out luminum-ca.crt \
	-subj "/CN=Luminum Server CA" \
	-addext "basicConstraints=critical,CA:TRUE" \
	-addext "keyUsage=critical,keyCertSign" 2>/dev/null

# --- server.crt: RSA 2048 leaf issued by the CA (prepare_ssl generate/new) ---
openssl genpkey -algorithm rsa -pkeyopt rsa_keygen_bits:2048 -out server.key 2>/dev/null
cat > leaf.ext <<EOF
subjectAltName=DNS:$CN
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF
openssl req -new -key server.key -subj "/CN=$CN" -out server.csr 2>/dev/null
openssl x509 -req -in server.csr \
	-CA luminum-ca.crt -CAkey luminum-ca.key \
	-set_serial "0x$(openssl rand -hex 8)" \
	-days 365 -extfile leaf.ext -out server.crt 2>/dev/null
rm -f server.csr leaf.ext

# --- Ed25519 signing key + cert issued by the CA (prepare_signing) -----------
openssl genpkey -algorithm ed25519 -out server-signing.key 2>/dev/null
cat > signing.ext <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
EOF
openssl req -new -key server-signing.key -subj "/CN=$CN" -out server-signing.csr 2>/dev/null
openssl x509 -req -in server-signing.csr \
	-CA luminum-ca.crt -CAkey luminum-ca.key \
	-set_serial "0x$(openssl rand -hex 8)" \
	-days 365 -extfile signing.ext -out server-signing.crt 2>/dev/null
rm -f server-signing.csr signing.ext

# --- self-signed Ed25519 signing cert (import mode) --------------------------
openssl genpkey -algorithm ed25519 -out server-signing-selfsigned.key 2>/dev/null
openssl req -x509 -key server-signing-selfsigned.key -days 365 \
	-subj "/CN=$CN" -out server-signing-selfsigned.crt 2>/dev/null

# --- other-root.crt: a different RSA CA (negative test) ----------------------
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
	-keyout other-root.key -out other-root.crt \
	-subj "/CN=other.test" \
	-addext "basicConstraints=critical,CA:TRUE" \
	-addext "keyUsage=critical,keyCertSign" 2>/dev/null

# --- ground truth: raw 32-byte Ed25519 public keys ---------------------------
# The Ed25519 SPKI DER is 44 bytes (12-byte prefix + 32-byte key); the last 64
# hex chars of the DER are the raw key.
for c in server-signing server-signing-selfsigned; do
	openssl x509 -in "$c.crt" -pubkey -noout 2>/dev/null \
		| openssl pkey -pubin -outform DER 2>/dev/null \
		| od -An -v -tx1 | tr -d ' \n' | tail -c 64 > "$c.pub.hex"
done

echo "Generated test certificates in $OUT:"
ls -1 "$OUT"
echo
echo "server-signing.pub.hex:            $(cat server-signing.pub.hex)"
echo "server-signing-selfsigned.pub.hex: $(cat server-signing-selfsigned.pub.hex)"
