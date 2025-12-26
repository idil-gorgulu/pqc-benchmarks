PQC TLS 1.3 Benchmark Artifacts (Supplementary Repo)

This repository contains the supplementary artifacts for our paper on algorithm- and system-level performance of post-quantum cryptography in TLS 1.3.

What this repo provides
- Reproducible TLS 1.3 benchmark pipeline using OpenSSL 3.5.1 + OQS provider (ML-KEM + ML-DSA).
- Scripts to:
  1) generate PQC server certificates (ML-DSA-44/65/87),
  2) run repeated TLS 1.3 handshakes (server pinned to core 0, client pinned to core 1),
  3) capture loopback traffic into a single PCAP,
  4) extract per-connection handshake traces (TShark),
  5) compute CH→SH and CH→END and handshake bytes C→S / S→C (Python analyzer).
- A compact “sample” folder layout to share small representative outputs without shipping large PCAP files.

Repository structure
- configs/                  OpenSSL provider configuration
- scripts/                  Experiment scripts (see scripts/tls_level/ and scripts/algorithm_level/)
- analysis/                 Python analyzer + plotting helpers
- docs/                     Supplementary notes, methodology, limitations
- data/sample/              Sample generation instructions (PCAP not committed)
- results/sample_outputs/   Example CSV layouts (tiny, representative)
- terminal_log_algorithm_level.txt  Historical terminal session (algorithm-level microbenchmarks)

Prerequisites

System tools
- Linux / WSL2 (tested on Ubuntu 24.04.x)
- tcpdump, tshark (Wireshark CLI), bash, python3

Install on Ubuntu:
sudo apt-get update
sudo apt-get install -y tcpdump tshark python3 python3-venv

Crypto stack
You need:
- OpenSSL 3.5.1 built and installed (or otherwise available),
- liboqs,
- oqsprovider (OpenSSL provider).

This repo does not vendor those sources. Instead, it provides configuration + runtime scripts.

Environment variables (important)
The scripts assume the same environment pattern as in our paper runs:

export OPENSSL_ROOT="$HOME/opt/openssl-3.5.1"
export PATH="$OPENSSL_ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$OPENSSL_ROOT/lib64:$OPENSSL_ROOT/lib:$HOME/opt/liboqs/lib:$LD_LIBRARY_PATH"
export OPENSSL_CONF="$(pwd)/configs/openssl-pqc.cnf"
export OSSL_PROVIDER_PATH="$OPENSSL_ROOT/lib64/ossl-modules"

Quick sanity checks:
openssl version -v
openssl list -providers
openssl list -signature-algorithms | grep -E 'MLDSA|Dilithium' || true
openssl list -kem-algorithms | grep -E 'MLKEM|Kyber' || true

Quickstart (PQC run in ~2 minutes)

Create Python venv:
python3 -m venv .venv
source .venv/bin/activate
pip install -r analysis/requirements.txt

Generate PQC cert/key (ML-DSA-44):
mkdir -p artifacts/certs
./scripts/tls_level/mk_pqc_cert.sh MLDSA44 artifacts/certs/server_pq

Run a short burst (10 seconds capture, PQ group MLKEM512):
./scripts/tls_level/run_burst.sh \
  --mode pq \
  --port 4433 \
  --group MLKEM512 \
  --sigalg mldsa44 \
  --cert artifacts/certs/server_pq.crt \
  --key  artifacts/certs/server_pq.key \
  --seconds 10 \
  --out runs/mlkem512_mldsa44_try1

This creates:
- runs/.../capture.pcap
- runs/.../bursts.csv (time windows)
- window-sliced cap_*.pcap
- analysis_*.csv (per-stream metrics)
- summary_*.txt (human-readable stats)

Notes on metrics
We compute per TCP stream:
- CH→SH: time from ClientHello (type=1) to ServerHello (type=2)
- CH→END: time from ClientHello to client Finished (type=20) when observable; fallback to last handshake record in that stream
- bytes_c2s / bytes_s2c: sum of TCP payload bytes (tcp.len) within [CH, END] (fallback to frame.len if needed)

These definitions are documented in docs/METHODOLOGY.md.

Algorithm-level microbenchmarks (Kyber/Dilithium/OpenSSL speed)

In addition to the TLS-level pipeline, this repo also includes **algorithm-level** runners derived from `terminal_log_algorithm_level.txt`.

Run all algorithm-level benchmarks (default output: runs/algorithm_level/<tag>):
./scripts/algorithm_level/run_all.sh --tag wsl_try1

Documentation:
- docs/ALGORITHM_LEVEL.md

Reproducing figures/tables
Use analysis/plot_figures.py to generate plots from analysis_*.csv files (example usage in the script header).
