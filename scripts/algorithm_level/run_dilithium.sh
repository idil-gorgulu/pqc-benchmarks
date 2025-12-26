#!/usr/bin/env bash
set -euo pipefail

# Algorithm-level Dilithium microbench runner (pq-crystals/dilithium).
#
# What it does (mirrors terminal_log_algorithm_level.txt):
# - clones pq-crystals/dilithium (or reuses an existing checkout)
# - builds + runs:
#   - ref/test: test_dilithium{2,3,5} and test_speed{2,3,5}
#   - avx2: make speed + make, then run test/test_speed{2,3,5} and test/test_dilithium{2,3,5} (x86_64 Linux only)
# - prints cpu MHz lines between runs if /proc/cpuinfo exists (Linux)
# - writes stdout logs to files under --out
#
# Notes:
# - AVX2 build requires Linux x86_64 and a toolchain that supports -mavx2 (typically gcc/clang).
# - CPU pinning uses taskset when available; otherwise runs unpinned.
#
# Usage:
#   ./scripts/algorithm_level/run_dilithium.sh --out results/algorithm_level/myrun

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

OUT=""
WORKDIR=""
REPO_URL="https://github.com/pq-crystals/dilithium.git"
RUN_AVX2="auto"  # auto|yes|no
PIN_CORE="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    --repo-url) REPO_URL="$2"; shift 2 ;;
    --avx2) RUN_AVX2="$2"; shift 2 ;; # auto|yes|no
    --pin-core) PIN_CORE="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,180p' "$0"
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

need_cmd make

mkdir -p "$OUT"

if [[ -z "$WORKDIR" ]]; then
  WORKDIR="$OUT/work"
fi
mkdir -p "$WORKDIR"

DILITHIUM_DIR="$WORKDIR/dilithium"
ensure_git_clone "$REPO_URL" "$DILITHIUM_DIR"

PIN=()
PIN_STR="$(read_pin_array "$PIN_CORE")"
if [[ -n "$PIN_STR" ]]; then
  # shellcheck disable=SC2206
  PIN=( $PIN_STR )
else
  echo "[WARN] taskset not found; running without CPU pinning."
fi

run_in_dir_log() {
  local dir="$1"
  local label="$2"
  shift 2
  local logfile="$OUT/${label}.log"
  echo "[INFO] $label: $dir"
  echo "[INFO] writing $logfile"
  (
    cd "$dir"
    echo "+ $*"
    "$@"
  ) >"$logfile" 2>&1
}

run_bin_log() {
  local dir="$1"
  local label="$2"
  local bin="$3"
  local logfile="$OUT/${label}.log"
  echo "[INFO] $label: $dir/$bin"
  echo "[INFO] writing $logfile"
  (
    cd "$dir"
    print_cpu_mhz_like_log
    if [[ ${#PIN[@]} -gt 0 ]]; then
      echo "+ ${PIN[*]} ./$bin"
      "${PIN[@]}" "./$bin"
    else
      echo "+ ./$bin"
      "./$bin"
    fi
  ) >"$logfile" 2>&1
}

echo "[INFO] Building Dilithium ref..."
run_in_dir_log "$DILITHIUM_DIR/ref" "dilithium_ref_build" make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"

REF_TEST_DIR="$DILITHIUM_DIR/ref/test"
for b in test_dilithium2 test_dilithium3 test_dilithium5 test_speed2 test_speed3 test_speed5; do
  [[ -x "$REF_TEST_DIR/$b" ]] || { echo "ERROR: missing $REF_TEST_DIR/$b (build failed?)" >&2; exit 1; }
done

echo "[INFO] Running Dilithium ref tests..."
run_bin_log "$REF_TEST_DIR" "dilithium_ref_test_dilithium2" "test_dilithium2"
run_bin_log "$REF_TEST_DIR" "dilithium_ref_test_dilithium3" "test_dilithium3"
run_bin_log "$REF_TEST_DIR" "dilithium_ref_test_dilithium5" "test_dilithium5"
run_bin_log "$REF_TEST_DIR" "dilithium_ref_test_speed2" "test_speed2"
run_bin_log "$REF_TEST_DIR" "dilithium_ref_test_speed3" "test_speed3"
run_bin_log "$REF_TEST_DIR" "dilithium_ref_test_speed5" "test_speed5"

want_avx2="no"
case "$RUN_AVX2" in
  yes) want_avx2="yes" ;;
  no) want_avx2="no" ;;
  auto)
    if is_linux && is_x86_64; then want_avx2="yes"; else want_avx2="no"; fi
    ;;
  *)
    echo "ERROR: --avx2 must be auto|yes|no (got: $RUN_AVX2)" >&2
    exit 1
    ;;
esac

if [[ "$want_avx2" == "yes" ]]; then
  echo "[INFO] Building Dilithium avx2 (speed + all)..."
  run_in_dir_log "$DILITHIUM_DIR/avx2" "dilithium_avx2_make_speed" make speed -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  run_in_dir_log "$DILITHIUM_DIR/avx2" "dilithium_avx2_make_all" make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"

  AVX2_TEST_DIR="$DILITHIUM_DIR/avx2/test"
  for b in test_speed2 test_speed3 test_speed5 test_dilithium2 test_dilithium3 test_dilithium5; do
    [[ -x "$AVX2_TEST_DIR/$b" ]] || { echo "ERROR: missing $AVX2_TEST_DIR/$b (avx2 build failed?)" >&2; exit 1; }
  done

  echo "[INFO] Running Dilithium avx2 tests..."
  run_bin_log "$AVX2_TEST_DIR" "dilithium_avx2_test_speed2" "test_speed2"
  run_bin_log "$AVX2_TEST_DIR" "dilithium_avx2_test_speed3" "test_speed3"
  run_bin_log "$AVX2_TEST_DIR" "dilithium_avx2_test_speed5" "test_speed5"
  run_bin_log "$AVX2_TEST_DIR" "dilithium_avx2_test_dilithium2" "test_dilithium2"
  run_bin_log "$AVX2_TEST_DIR" "dilithium_avx2_test_dilithium3" "test_dilithium3"
  run_bin_log "$AVX2_TEST_DIR" "dilithium_avx2_test_dilithium5" "test_dilithium5"
else
  echo "[WARN] Skipping Dilithium avx2 (requires Linux x86_64). Use --avx2 yes to force."
fi

echo "[INFO] Dilithium done. Logs under: $OUT"


