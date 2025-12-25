#!/usr/bin/env bash
set -euo pipefail

# End-to-end TLS burst runner:
# - starts s_server pinned to core 0
# - runs repeated s_client connections pinned to core 1 for N seconds
# - captures loopback traffic to capture.pcap
# - writes bursts.csv as a single [t0,t1] window
# - slices window and runs tshark extraction + Python analysis
#
# Examples:
# PQC:
#   ./scripts/run_burst.sh --mode pq --group MLKEM512 --sigalg mldsa44 \
#     --cert artifacts/certs/server_pq.crt --key artifacts/certs/server_pq.key \
#     --seconds 10 --out runs/mlkem512_mldsa44_try1
#
# Classical:
#   ./scripts/run_burst.sh --mode classic --group P-256 \
#     --cert artifacts/certs/server_classic.crt --key artifacts/certs/server_classic.key \
#     --seconds 10 --out runs/p256_try1

MODE="pq"         # pq | classic
PORT="4433"
GROUP=""
SIGALG=""
CERT=""
KEY=""
SECONDS="10"
OUT=""
CLIENTS="1"
IFACE=""          # default: linux=lo, darwin=lo0 (auto)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --group) GROUP="$2"; shift 2 ;;
    --sigalg) SIGALG="$2"; shift 2 ;;
    --cert) CERT="$2"; shift 2 ;;
    --key) KEY="$2"; shift 2 ;;
    --seconds) SECONDS="$2"; shift 2 ;;
    --clients) CLIENTS="$2"; shift 2 ;;
    --iface) IFACE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
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
if [[ -z "$CERT" || -z "$KEY" ]]; then
  echo "ERROR: --cert and --key are required" >&2
  exit 1
fi
if [[ -z "$GROUP" ]]; then
  echo "ERROR: --group is required (e.g., MLKEM512 or P-256)" >&2
  exit 1
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing required command: $1" >&2; exit 1; }
}

need_cmd openssl
need_cmd python3
need_cmd awk
need_cmd tcpdump
need_cmd tshark

if [[ -z "$IFACE" ]]; then
  case "$(uname -s)" in
    Darwin) IFACE="lo0" ;;
    *) IFACE="lo" ;;
  esac
fi

PIN_SERVER=()
PIN_CLIENT=()
if command -v taskset >/dev/null 2>&1; then
  PIN_SERVER=(taskset -c 0)
  PIN_CLIENT=(taskset -c 1)
else
  echo "[WARN] taskset not found; running without CPU pinning."
fi

SUDO=()
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
  else
    echo "ERROR: tcpdump capture requires root privileges; install sudo or run as root." >&2
    exit 1
  fi
fi

mkdir -p "$OUT"
pushd "$OUT" >/dev/null

echo "[INFO] mode=$MODE port=$PORT group=$GROUP sigalg=${SIGALG:-<auto>} seconds=$SECONDS clients=$CLIENTS iface=$IFACE"
echo "[INFO] writing outputs under: $OUT"

# Start server pinned to core 0
SERVER_ARGS=(openssl s_server -accept "$PORT" -cert "$CERT" -key "$KEY" -tls1_3)
# Force provider order explicitly (matches what you did in terminal for success)
SERVER_ARGS+=(-provider oqsprovider -provider default)

if [[ -n "$SIGALG" ]]; then
  SERVER_ARGS+=(-sigalgs "$SIGALG")
fi
SERVER_ARGS+=(-groups "$GROUP")

"${PIN_SERVER[@]}" "${SERVER_ARGS[@]}" > server.log 2>&1 &
echo $! > server.pid
sleep 1

# Start capture
"${SUDO[@]}" tcpdump -i "$IFACE" -w capture.pcap "tcp port $PORT" >/dev/null 2>&1 &
TCPDUMP_PID=$!

cleanup() {
  set +e
  if [[ -f server.pid ]]; then kill "$(cat server.pid)" >/dev/null 2>&1; fi
  kill "$TCPDUMP_PID" >/dev/null 2>&1
  wait >/dev/null 2>&1
}
trap cleanup EXIT

# Run clients for SECONDS
T0="$(python3 -c 'import time; print(time.time())')"
END_AT="$(python3 -c "import time; print(time.time()+$SECONDS)")"

client_cmd_base=(openssl s_client -connect "127.0.0.1:$PORT" -tls1_3 -servername localhost -brief)
# Providers on client too
client_cmd_base+=(-provider oqsprovider -provider default)
# Match group and sigalg preferences (optional; OpenSSL can also auto-negotiate)
client_cmd_base+=(-groups "$GROUP")
if [[ -n "$SIGALG" ]]; then
  client_cmd_base+=(-sigalgs "$SIGALG")
fi

echo "[INFO] Running clients..."
# One or more parallel client loops
pids=()
for c in $(seq 1 "$CLIENTS"); do
  (
    while :; do
      now="$(python3 -c 'import time; print(time.time())')"
      awk "BEGIN{exit !($now < $END_AT)}" || break
      # suppress output; keep it lightweight
      "${PIN_CLIENT[@]}" "${client_cmd_base[@]}" </dev/null >/dev/null 2>&1 || true
    done
  ) &
  pids+=("$!")
done

for p in "${pids[@]}"; do wait "$p" || true; done

T1="$(python3 -c 'import time; print(time.time())')"

# Stop capture explicitly (trap will also handle)
kill "$TCPDUMP_PID" >/dev/null 2>&1 || true
sleep 1

# record one window (t0,t1)
echo "t0,t1" > bursts.csv
echo "$T0,$T1" >> bursts.csv

echo "[INFO] Extract+Analyze (single window)"
ANALYZER="../../analysis/analyze_tls_v3.py"
EXTRACT="../../scripts/extract_windows.sh"

# Use a single window index=1
bash "$EXTRACT" --pcap capture.pcap --bursts bursts.csv --port "$PORT" --analyzer "$ANALYZER"

echo "[INFO] Done. Key files:"
ls -1 capture.pcap bursts.csv analysis_1.csv summary_1.txt 2>/dev/null || true

popd >/dev/null
