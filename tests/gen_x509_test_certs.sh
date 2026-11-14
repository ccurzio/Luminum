#!/usr/bin/env bash
#
# Generate the certificates used by the Windows client's X.509 trust-anchor
# unit tests (client/windows/src/main.rs, #[cfg(test)] mod tests). These mirror
# the server's Luminum::Setup::prepare_ssl / prepare_signing:
#
#   server.crt                    RSA 2048 self-signed, CA:TRUE (the TLS root)
#   server-signing.crt            Ed25519, issued by server.crt (generate mode)
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

# --- server.crt: RSA 2048 self-signed CA (mirrors prepare_ssl generate/new) ---
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
	-keyout server.key -out server.crt \
	-subj "/CN=$CN" \
	-addext "subjectAltName=DNS:$CN" \
	-addext "basicConstraints=critical,CA:TRUE" 2>/dev/null

# --- Ed25519 signing key + cert issued by server.crt (prepare_signing) -------
openssl genpkey -algorithm ed25519 -out server-signing.key 2>/dev/null
cat > signing.ext <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
EOF
openssl req -new -key server-signing.key -subj "/CN=$CN" -out server-signing.csr 2>/dev/null
openssl x509 -req -in server-signing.csr \
	-CA server.crt -CAkey server.key \
	-set_serial "0x$(openssl rand -hex 8)" \
	-days 3650 -extfile signing.ext -out server-signing.crt 2>/dev/null

# --- self-signed Ed25519 signing cert (import mode) --------------------------
openssl genpkey -algorithm ed25519 -out server-signing-selfsigned.key 2>/dev/null
openssl req -x509 -key server-signing-selfsigned.key -days 3650 \
	-subj "/CN=$CN" -out server-signing-selfsigned.crt 2>/dev/null

# --- other-root.crt: a different RSA CA (negative test) ----------------------
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
	-keyout other-root.key -out other-root.crt \
	-subj "/CN=other.test" \
	-addext "basicConstraints=critical,CA:TRUE" 2>/dev/null

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
