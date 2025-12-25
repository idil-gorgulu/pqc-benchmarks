#!/usr/bin/env bash
set -euo pipefail

# Slice capture.pcap into windows from bursts.csv and run:
# - tshark extraction: hs_i.csv (handshake records), frames_i.csv (all frames)
# - python analysis: analysis_i.csv + summary_i.txt
#
# Usage:
#   ./scripts/extract_windows.sh --pcap capture.pcap --bursts bursts.csv --port 4433 --analyzer analysis/analyze_tls_v3.py
#
# bursts.csv format:
#   t0,t1
#   1760304693.7705,1760304698.0068
#   ...

PCAP=""
BURSTS=""
PORT="4433"
ANALYZER=""

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing required command: $1" >&2; exit 1; }
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pcap) PCAP="$2"; shift 2 ;;
    --bursts) BURSTS="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --analyzer) ANALYZER="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,140p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$PCAP" ]] || { echo "ERROR: PCAP not found: $PCAP" >&2; exit 1; }
[[ -f "$BURSTS" ]] || { echo "ERROR: bursts.csv not found: $BURSTS" >&2; exit 1; }
[[ -f "$ANALYZER" ]] || { echo "ERROR: analyzer not found: $ANALYZER" >&2; exit 1; }

need_cmd tshark
need_cmd python3

i=1
# Skip header line
tail -n +2 "$BURSTS" | while IFS=, read -r T0 T1; do
  echo "=== WINDOW $i : $T0 → $T1 ==="

  # Slice PCAP by time window
  tshark -d "tcp.port==$PORT,tls" -r "$PCAP" \
    -Y "frame.time_epoch >= $T0 && frame.time_epoch <= $T1" \
    -w "cap_${i}.pcap" >/dev/null 2>&1

  if [[ ! -f "cap_${i}.pcap" ]]; then
    echo "No cap_${i}.pcap produced; skipping."
    i=$((i+1))
    continue
  fi

  # Extract handshake records (all types) with tcp.stream correlation
  # Fields are TAB-separated by default with -T fields.
  tshark -d "tcp.port==$PORT,tls" -r "cap_${i}.pcap" -Y "tls.handshake" \
    -T fields \
    -e tcp.stream -e tls.handshake.type -e frame.time_epoch \
    -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport \
    -e frame.len -e tcp.len \
    > "hs_${i}.csv"

  # Extract all frames for byte counting
  tshark -d "tcp.port==$PORT,tls" -r "cap_${i}.pcap" \
    -T fields \
    -e tcp.stream -e frame.time_epoch \
    -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport \
    -e frame.len -e tcp.len \
    > "frames_${i}.csv"

  # Analyze
  python3 "$ANALYZER" "hs_${i}.csv" "frames_${i}.csv" "$PORT" "analysis_${i}.csv" > "summary_${i}.txt"
  sed -n '1,120p' "summary_${i}.txt" || true

  i=$((i+1))
done
