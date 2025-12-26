#!/usr/bin/env bash
set -euo pipefail

# Algorithm-level benchmark driver.
#
# This mirrors the TLS-level style: one entrypoint script that writes all outputs under
# an --out directory (default: runs/algorithm_level/<tag>) and delegates to
# scripts/algorithm_level/* runners.
#
# Usage:
#   ./scripts/algorithm_level/run_all.sh --tag wsl_try1
#   ./scripts/algorithm_level/run_all.sh --out runs/algorithm_level/custom --no-avx2
#
# Notes:
# - Kyber + Dilithium runners will clone upstream repos into <out>/work/ by default.
# - AVX2 runs are auto-enabled only on Linux x86_64 (your original WSL setup).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TAG=""
OUT=""
WORKDIR=""
PIN_CORE="0"
AVX2_MODE="auto" # auto|yes|no
RUN_KYBER="yes"
RUN_DILITHIUM="yes"
RUN_OPENSSL_SPEED="yes"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    --pin-core) PIN_CORE="$2"; shift 2 ;;
    --avx2) AVX2_MODE="$2"; shift 2 ;; # auto|yes|no
    --no-avx2) AVX2_MODE="no"; shift 1 ;;
    --only)
      # Comma-separated: kyber,dilithium,openssl
      RUN_KYBER="no"; RUN_DILITHIUM="no"; RUN_OPENSSL_SPEED="no"
      IFS=, read -r -a parts <<<"$2"
      for p in "${parts[@]}"; do
        case "$p" in
          kyber) RUN_KYBER="yes" ;;
          dilithium) RUN_DILITHIUM="yes" ;;
          openssl|openssl_speed) RUN_OPENSSL_SPEED="yes" ;;
          *) echo "ERROR: unknown --only entry: $p (use kyber,dilithium,openssl)" >&2; exit 1 ;;
        esac
      done
      shift 2
      ;;
    -h|--help)
      sed -n '1,200p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$OUT" ]]; then
  if [[ -z "$TAG" ]]; then
    TAG="$(date -u +%Y%m%dT%H%M%SZ)"
  fi
  OUT="$ROOT_DIR/runs/algorithm_level/$TAG"
fi

mkdir -p "$OUT"

if [[ -z "$WORKDIR" ]]; then
  WORKDIR="$OUT/work"
fi

echo "[INFO] out=$OUT"
echo "[INFO] workdir=$WORKDIR"
echo "[INFO] pin_core=$PIN_CORE avx2=$AVX2_MODE"

if [[ "$RUN_KYBER" == "yes" ]]; then
  echo "[INFO] === Kyber ==="
  bash "$ROOT_DIR/scripts/algorithm_level/run_kyber.sh" \
    --out "$OUT/kyber" \
    --workdir "$WORKDIR" \
    --pin-core "$PIN_CORE" \
    --avx2 "$AVX2_MODE"
fi

if [[ "$RUN_DILITHIUM" == "yes" ]]; then
  echo "[INFO] === Dilithium ==="
  bash "$ROOT_DIR/scripts/algorithm_level/run_dilithium.sh" \
    --out "$OUT/dilithium" \
    --workdir "$WORKDIR" \
    --pin-core "$PIN_CORE" \
    --avx2 "$AVX2_MODE"
fi

if [[ "$RUN_OPENSSL_SPEED" == "yes" ]]; then
  echo "[INFO] === OpenSSL speed ==="
  bash "$ROOT_DIR/scripts/algorithm_level/run_openssl_speed.sh" \
    --out "$OUT/openssl_speed" \
    --pin-core "$PIN_CORE"
fi

echo "[INFO] Done. Outputs under: $OUT"


