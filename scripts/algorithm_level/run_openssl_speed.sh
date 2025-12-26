#!/usr/bin/env bash
set -euo pipefail

# OpenSSL "speed" runs (classical baseline), matching terminal_log_algorithm_level.txt:
# - rsa2048
# - ecdsa
# - ecdh
#
# Usage:
#   ./scripts/algorithm_level/run_openssl_speed.sh --out results/algorithm_level/myrun
#
# Output:
#   --out/openssl_speed_rsa2048.txt
#   --out/openssl_speed_ecdsa.txt
#   --out/openssl_speed_ecdh.txt

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

OUT=""
PIN_CORE="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --pin-core) PIN_CORE="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,120p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$OUT" ]]; then
  echo "ERROR: --out is required" >&2
  exit 1
fi

need_cmd openssl

mkdir -p "$OUT"

PIN=()
PIN_STR="$(read_pin_array "$PIN_CORE")"
if [[ -n "$PIN_STR" ]]; then
  # shellcheck disable=SC2206
  PIN=( $PIN_STR )
else
  echo "[WARN] taskset not found; running without CPU pinning."
fi

run_speed() {
  local label="$1"
  shift
  local outfile="$OUT/$label"
  echo "[INFO] Running: openssl $*"
  echo "[INFO] writing $outfile"
  if [[ ${#PIN[@]} -gt 0 ]]; then
    (
      echo "+ ${PIN[*]} openssl $*"
      "${PIN[@]}" openssl "$@"
    ) >"$outfile" 2>&1
  else
    (
      echo "+ openssl $*"
      openssl "$@"
    ) >"$outfile" 2>&1
  fi
}

run_speed "openssl_speed_rsa2048.txt" speed rsa2048
run_speed "openssl_speed_ecdsa.txt" speed ecdsa
run_speed "openssl_speed_ecdh.txt" speed ecdh

echo "[INFO] OpenSSL speed done. Outputs under: $OUT"


