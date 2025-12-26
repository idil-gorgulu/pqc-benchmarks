# Methodology (Supplementary)

This repository measures **TLS 1.3 handshake timing and bytes** per TCP stream using a loopback capture and post-processing with `tshark` + Python.

## What is measured

Per TCP stream (Wireshark `tcp.stream`):

- **CH→SH (ms)**: time from TLS ClientHello (`tls.handshake.type == 1`) to ServerHello (`tls.handshake.type == 2`)
- **CH→END (ms)**: time from ClientHello to the **client Finished** (`tls.handshake.type == 20` originating from the client) when we can identify it; otherwise ClientHello to the **last observed handshake record** in that stream
- **bytes_c2s / bytes_s2c**: sum of TCP payload bytes (`tcp.len`) within \([CH, END]\) in each direction; if `tcp.len` is unavailable, we fall back to `frame.len`

## How direction is inferred

`analysis/analyze_tls_v3.py` determines the client port per stream as:

- the first observed `dstport == <server_port>` (client → server); its `srcport` is treated as the client port for that stream

Then:

- client → server: `dstport == server_port && srcport == client_port`
- server → client: `srcport == server_port && dstport == client_port`

If the client port cannot be inferred, byte counts fall back to 0 for that stream.

## Inputs produced by the scripts

`scripts/tls_level/extract_windows.sh` uses `tshark` to produce two TAB-separated files per time window:

- `hs_<i>.csv`: handshake records with `tls.handshake.type` and timing
- `frames_<i>.csv`: all frames in the window for byte counting

These are consumed by:

- `analysis/analyze_tls_v3.py hs_<i>.csv frames_<i>.csv <server_port> analysis_<i>.csv`

## Limitations

- Loopback capture is OS-dependent; the provided runner is tested primarily on Linux/WSL.
- Some TLS handshakes may not expose all expected handshake messages (e.g., missing Finished) depending on capture visibility; the analyzer uses a fallback to “last handshake record”.


