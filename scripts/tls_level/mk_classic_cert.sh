#!/usr/bin/env bash
set -euo pipefail

# TLS-level: Generate a self-signed classical server certificate.
#
# Usage:
#   ./scripts/tls_level/mk_classic_cert.sh ecdsa_p256 artifacts/certs/server_classic
#   ./scripts/tls_level/mk_classic_cert.sh rsa_2048  artifacts/certs/server_classic
#
# Output:
#   <prefix>.key
#   <prefix>.crt

MODE="${1:-ecdsa_p256}"    # ecdsa_p256 | ecdsa_p384 | ecdsa_p521 | rsa_2048 | rsa_3072 | rsa_4096
OUT="${2:-server_classic}"
DAYS="${3:-7}"

mkdir -p "$(dirname "$OUT")"

case "$MODE" in
  ecdsa_p256)
    openssl ecparam -name prime256v1 -genkey -noout -out "${OUT}.key"
    ;;
  ecdsa_p384)
    openssl ecparam -name secp384r1 -genkey -noout -out "${OUT}.key"
    ;;
  ecdsa_p521)
    openssl ecparam -name secp521r1 -genkey -noout -out "${OUT}.key"
    ;;
  rsa_2048)
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "${OUT}.key"
    ;;
  rsa_3072)
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "${OUT}.key"
    ;;
  rsa_4096)
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "${OUT}.key"
    ;;
  *)
    echo "Unknown MODE: $MODE" >&2
    exit 1
    ;;
esac

openssl req -new -x509 -key "${OUT}.key" -out "${OUT}.crt" \
  -days "$DAYS" -subj "/CN=localhost"

ls -l "${OUT}.key" "${OUT}.crt"
echo "OK: generated ${OUT}.crt / ${OUT}.key with $MODE"


