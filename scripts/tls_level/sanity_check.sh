#!/usr/bin/env bash
set -euo pipefail

# TLS-level environment sanity check.
#
echo "[1] OpenSSL version:"
openssl version -v

echo "[2] Providers:"
openssl list -providers | sed -n '1,120p'

echo "[3] PQ signature algos (ML-DSA):"
openssl list -signature-algorithms | grep -E 'ML-DSA|MLDSA|Dilithium' || true

echo "[4] PQ KEMs (ML-KEM):"
openssl list -kem-algorithms | grep -E 'ML-KEM|MLKEM|Kyber' || true

echo "OK"


