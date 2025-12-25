#!/usr/bin/env python3
"""
Analyze TLS handshake timing and bytes per TCP stream.

Inputs are TAB-separated outputs produced by tshark (-T fields).
We expect:

hs.csv columns (by scripts/extract_windows.sh):
  0 tcp.stream
  1 tls.handshake.type
  2 frame.time_epoch
  3 ip.src
  4 tcp.srcport
  5 ip.dst
  6 tcp.dstport
  7 frame.len
  8 tcp.len

frames.csv columns:
  0 tcp.stream
  1 frame.time_epoch
  2 ip.src
  3 tcp.srcport
  4 ip.dst
  5 tcp.dstport
  6 frame.len
  7 tcp.len

We compute per stream:
- CH_to_SH_ms: ClientHello(type=1) -> ServerHello(type=2)
- CH_to_END_ms: ClientHello -> client Finished(type=20) when observable;
                otherwise ClientHello -> last handshake record in stream (fallback)
- bytes_c2s / bytes_s2c: sum of tcp.len in [CH, END] for each direction (fallback frame.len)

Usage:
  python3 analyze_tls_v3.py <hs.csv> <frames.csv> <server_port> <out.csv>
"""

import sys
import csv
import statistics as st
from collections import defaultdict
from typing import Dict, List, Tuple, Optional

def parse_float(x: str) -> Optional[float]:
    try:
        return float(x)
    except Exception:
        return None

def parse_int(x: str) -> Optional[int]:
    try:
        return int(x)
    except Exception:
        return None

def pct(values: List[float], p: float) -> Optional[float]:
    if not values:
        return None
    v = sorted(values)
    k = (len(v) - 1) * p
    f = int(k)
    c = min(f + 1, len(v) - 1)
    if f == c:
        return float(v[f])
    return float(v[f] + (v[c] - v[f]) * (k - f))

def median(values: List[float]) -> Optional[float]:
    return st.median(values) if values else None

def main() -> int:
    if len(sys.argv) != 5:
        print("Usage: analyze_tls_v3.py <hs.csv> <frames.csv> <server_port> <out.csv>")
        return 1

    hs_path, frames_path, server_port_s, out_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    server_port = int(server_port_s)

    # handshake times per stream
    CH: Dict[str, float] = {}
    SH: Dict[str, float] = {}
    FIN_CLIENT: Dict[str, float] = {}
    LAST_HS: Dict[str, float] = {}

    # Determine client port per stream (first seen dstport==server_port implies client->server)
    client_port_guess: Dict[str, int] = {}

    # Parse hs records
    with open(hs_path, newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        for row in reader:
            if len(row) < 3:
                continue
            stream = row[0]
            hs_type = parse_int(row[1])
            ts = parse_float(row[2])
            if ts is None or hs_type is None:
                continue

            # Try to parse ports to identify direction (optional)
            srcp = parse_int(row[4]) if len(row) > 4 else None
            dstp = parse_int(row[6]) if len(row) > 6 else None
            if srcp is not None and dstp is not None:
                if dstp == server_port:
                    client_port_guess.setdefault(stream, srcp)

            if hs_type == 1:  # ClientHello
                # earliest CH
                if stream not in CH or ts < CH[stream]:
                    CH[stream] = ts
            elif hs_type == 2:  # ServerHello
                if stream not in SH or ts < SH[stream]:
                    SH[stream] = ts
            elif hs_type == 20:  # Finished (could be server or client)
                # If we have client port guess and src port matches, treat as client finished
                if srcp is not None and stream in client_port_guess and srcp == client_port_guess[stream]:
                    # earliest client Finished after CH
                    if stream not in FIN_CLIENT or ts < FIN_CLIENT[stream]:
                        FIN_CLIENT[stream] = ts

            # track last handshake timestamp
            if stream not in LAST_HS or ts > LAST_HS[stream]:
                LAST_HS[stream] = ts

    # Parse frames for bytes
    frames: Dict[str, List[Tuple[float, int, int, int, int]]] = defaultdict(list)
    # tuple: (ts, srcp, dstp, frame_len, tcp_len)
    with open(frames_path, newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        for row in reader:
            if len(row) < 7:
                continue
            stream = row[0]
            ts = parse_float(row[1])
            srcp = parse_int(row[3])
            dstp = parse_int(row[5])
            frame_len = parse_int(row[6])  # total length
            tcp_len = parse_int(row[7]) if len(row) > 7 else None  # payload bytes
            if ts is None or srcp is None or dstp is None or frame_len is None:
                continue
            frames[stream].append((ts, srcp, dstp, frame_len, tcp_len if tcp_len is not None else -1))

    for s in frames:
        frames[s].sort(key=lambda x: x[0])

    rows_out = []
    ch2sh_ms_list: List[float] = []
    ch2end_ms_list: List[float] = []
    c2s_bytes_list: List[int] = []
    s2c_bytes_list: List[int] = []

    used_streams = 0

    for s, ch_ts in CH.items():
        if s not in SH:
            continue
        sh_ts = SH[s]
        ch2sh_ms = (sh_ts - ch_ts) * 1000.0

        # define END timestamp
        end_ts = FIN_CLIENT.get(s, None)
        if end_ts is None:
            end_ts = LAST_HS.get(s, None)
        if end_ts is None:
            continue
        ch2end_ms = (end_ts - ch_ts) * 1000.0

        # bytes counting within [CH, END]
        b_c2s = 0
        b_s2c = 0

        # need client port guess; if missing, infer as first frame where dstport==server_port
        if s not in client_port_guess and s in frames:
            for (ts, srcp, dstp, flen, tlen) in frames[s]:
                if dstp == server_port:
                    client_port_guess[s] = srcp
                    break

        cport = client_port_guess.get(s, None)

        if s in frames and cport is not None:
            for (ts, srcp, dstp, flen, tlen) in frames[s]:
                if ts < ch_ts or ts > end_ts:
                    continue
                # prefer tcp.len if available; tshark outputs empty sometimes -> we store -1
                payload_len = tlen if tlen is not None and tlen >= 0 else flen
                if dstp == server_port and srcp == cport:
                    b_c2s += payload_len
                elif srcp == server_port and dstp == cport:
                    b_s2c += payload_len
        else:
            # fallback: can't determine direction
            b_c2s = 0
            b_s2c = 0

        rows_out.append({
            "tcp_stream": s,
            "CH_to_SH_ms": ch2sh_ms,
            "CH_to_END_ms": ch2end_ms,
            "bytes_c2s": b_c2s,
            "bytes_s2c": b_s2c,
        })

        used_streams += 1
        ch2sh_ms_list.append(ch2sh_ms)
        ch2end_ms_list.append(ch2end_ms)
        c2s_bytes_list.append(b_c2s)
        s2c_bytes_list.append(b_s2c)

    # Write per-stream CSV
    with open(out_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["tcp_stream", "CH_to_SH_ms", "CH_to_END_ms", "bytes_c2s", "bytes_s2c"])
        for r in rows_out:
            w.writerow([r["tcp_stream"], f'{r["CH_to_SH_ms"]:.6f}', f'{r["CH_to_END_ms"]:.6f}', r["bytes_c2s"], r["bytes_s2c"]])

    # Human-readable summary
    print("SUMMARY")
    print(f"  Streams: {used_streams}")
    if used_streams == 0:
        return 0

    def fmt(x: Optional[float], unit: str = "") -> str:
        return "NA" if x is None else f"{x:.3f}{unit}"

    print("  CH→SH (ms):"
          f" median={fmt(median(ch2sh_ms_list))},"
          f" p25={fmt(pct(ch2sh_ms_list, 0.25))},"
          f" p75={fmt(pct(ch2sh_ms_list, 0.75))},"
          f" p95={fmt(pct(ch2sh_ms_list, 0.95))}")

    print("  CH→END (ms):"
          f" median={fmt(median(ch2end_ms_list))},"
          f" p25={fmt(pct(ch2end_ms_list, 0.25))},"
          f" p75={fmt(pct(ch2end_ms_list, 0.75))},"
          f" p95={fmt(pct(ch2end_ms_list, 0.95))}")

    # bytes stats (ints)
    def med_int(v: List[int]) -> Optional[float]:
        return float(st.median(v)) if v else None

    print("  Bytes/HS C→S:"
          f" median={fmt(med_int(c2s_bytes_list))},"
          f" p95={fmt(pct([float(x) for x in c2s_bytes_list], 0.95))}")

    print("  Bytes/HS S→C:"
          f" median={fmt(med_int(s2c_bytes_list))},"
          f" p95={fmt(pct([float(x) for x in s2c_bytes_list], 0.95))}")

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
