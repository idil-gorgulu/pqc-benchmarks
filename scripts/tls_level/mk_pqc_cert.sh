#!/usr/bin/env bash
set -euo pipefail

# TLS-level: Generate a self-signed PQC server certificate using ML-DSA.
#
# Usage:
#   ./scripts/tls_level/mk_pqc_cert.sh MLDSA44 artifacts/certs/server_pq
#
# Produces:
#   <prefix>.key
#   <prefix>.crt

SIG="${1:-MLDSA44}"       # MLDSA44 | MLDSA65 | MLDSA87
OUT="${2:-server_pq}"     # output prefix
DAYS="${3:-7}"            # validity

mkdir -p "$(dirname "$OUT")"

openssl genpkey -algorithm "$SIG" -out "${OUT}.key"
openssl req -new -x509 -key "${OUT}.key" -out "${OUT}.crt" \
  -days "$DAYS" -subj "/CN=localhost"

ls -l "${OUT}.key" "${OUT}.crt"
echo "OK: generated ${OUT}.crt / ${OUT}.key with $SIG"


