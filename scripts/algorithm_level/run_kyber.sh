#!/usr/bin/env bash
set -euo pipefail

# Algorithm-level Kyber microbench runner (pq-crystals/kyber).
#
# What it does (mirrors terminal_log_algorithm_level.txt):
# - clones pq-crystals/kyber (or reuses an existing checkout)
# - builds + runs:
#   - ref/test: test_kyber{512,768,1024} and test_speed{512,768,1024}
#   - avx2/test: test_kyber{512,768,1024} and test_speed{512,768,1024} (x86_64 Linux only)
# - prints cpu MHz lines between runs if /proc/cpuinfo exists (Linux)
# - writes stdout logs to files under --out
#
# Notes:
# - AVX2 build requires Linux x86_64 and a toolchain that supports -mavx2 (typically gcc/clang).
# - CPU pinning uses taskset when available; otherwise runs unpinned.
#
# Usage:
#   ./scripts/algorithm_level/run_kyber.sh --out results/algorithm_level/myrun

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

OUT=""
WORKDIR=""
REPO_URL="https://github.com/pq-crystals/kyber.git"
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
      sed -n '1,160p' "$0"
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
  # default workdir next to output
  WORKDIR="$OUT/work"
fi
mkdir -p "$WORKDIR"

KYBER_DIR="$WORKDIR/kyber"
ensure_git_clone "$REPO_URL" "$KYBER_DIR"

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
    # We echo the command to make logs self-contained.
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

echo "[INFO] Building Kyber ref..."
run_in_dir_log "$KYBER_DIR/ref" "kyber_ref_build" make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"

REF_TEST_DIR="$KYBER_DIR/ref/test"
for b in test_kyber512 test_kyber768 test_kyber1024; do
  [[ -x "$REF_TEST_DIR/$b" ]] || { echo "ERROR: missing $REF_TEST_DIR/$b (build failed?)" >&2; exit 1; }
done
for b in test_speed512 test_speed768 test_speed1024; do
  [[ -x "$REF_TEST_DIR/$b" ]] || { echo "ERROR: missing $REF_TEST_DIR/$b (build failed?)" >&2; exit 1; }
done

echo "[INFO] Running Kyber ref tests..."
run_bin_log "$REF_TEST_DIR" "kyber_ref_test_kyber512" "test_kyber512"
run_bin_log "$REF_TEST_DIR" "kyber_ref_test_kyber768" "test_kyber768"
run_bin_log "$REF_TEST_DIR" "kyber_ref_test_kyber1024" "test_kyber1024"
run_bin_log "$REF_TEST_DIR" "kyber_ref_test_speed512" "test_speed512"
run_bin_log "$REF_TEST_DIR" "kyber_ref_test_speed768" "test_speed768"
run_bin_log "$REF_TEST_DIR" "kyber_ref_test_speed1024" "test_speed1024"

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
  echo "[INFO] Building Kyber avx2..."
  run_in_dir_log "$KYBER_DIR/avx2" "kyber_avx2_build" make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"

  AVX2_TEST_DIR="$KYBER_DIR/avx2/test"
  for b in test_kyber512 test_kyber768 test_kyber1024 test_speed512 test_speed768 test_speed1024; do
    [[ -x "$AVX2_TEST_DIR/$b" ]] || { echo "ERROR: missing $AVX2_TEST_DIR/$b (avx2 build failed?)" >&2; exit 1; }
  done

  echo "[INFO] Running Kyber avx2 tests..."
  run_bin_log "$AVX2_TEST_DIR" "kyber_avx2_test_kyber512" "test_kyber512"
  run_bin_log "$AVX2_TEST_DIR" "kyber_avx2_test_kyber768" "test_kyber768"
  run_bin_log "$AVX2_TEST_DIR" "kyber_avx2_test_kyber1024" "test_kyber1024"
  run_bin_log "$AVX2_TEST_DIR" "kyber_avx2_test_speed512" "test_speed512"
  run_bin_log "$AVX2_TEST_DIR" "kyber_avx2_test_speed768" "test_speed768"
  run_bin_log "$AVX2_TEST_DIR" "kyber_avx2_test_speed1024" "test_speed1024"
else
  echo "[WARN] Skipping Kyber avx2 (requires Linux x86_64). Use --avx2 yes to force."
fi

echo "[INFO] Kyber done. Logs under: $OUT"


