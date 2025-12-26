# Algorithm-level benchmarks (Supplementary)

This repository includes two layers of measurements:

- **TLS-level (system-level)**: end-to-end TLS 1.3 handshake timing/bytes using packet capture (`scripts/tls_level/run_burst.sh` + `scripts/tls_level/extract_windows.sh` + `analysis/analyze_tls_v3.py`).
- **Algorithm-level (microbenchmarks)**: standalone implementations’ test/speed programs (Kyber, Dilithium) and OpenSSL `speed` baselines.

This document describes the **algorithm-level** side and how to reproduce it from this repo.

## What is included

The original interactive terminal session is preserved in:

- `terminal_log_algorithm_level.txt`

For reproducibility, the equivalent steps are packaged as scripts:

- `scripts/algorithm_level/run_all.sh` (recommended entrypoint)
- `scripts/algorithm_level/run_kyber.sh`
- `scripts/algorithm_level/run_dilithium.sh`
- `scripts/algorithm_level/run_openssl_speed.sh`
- TLS-level scripts are organized under `scripts/tls_level/`.

## Prerequisites

These are intended to match the environment used in the terminal log (Linux/WSL2):

- **git**, **make**, and a compiler toolchain (`gcc`/`clang`)
- `taskset` (optional; CPU pinning is skipped if unavailable)
- **Linux x86_64** for AVX2 targets (auto-skipped on other platforms)
- `openssl` available for the OpenSSL baseline runner

## Running

Run everything (Kyber + Dilithium + OpenSSL speed) and store under `runs/algorithm_level/<tag>`:

```bash
./scripts/algorithm_level/run_all.sh --tag wsl_try1
```

Run only a subset:

```bash
./scripts/algorithm_level/run_all.sh --tag kyber_only --only kyber
```

Disable AVX2 explicitly:

```bash
./scripts/algorithm_level/run_all.sh --tag no_avx2 --no-avx2
```

## Outputs

By default, outputs go to `runs/algorithm_level/<tag>/...` and are **git-ignored**:

- Kyber: `runs/algorithm_level/<tag>/kyber/*.log`
- Dilithium: `runs/algorithm_level/<tag>/dilithium/*.log`
- OpenSSL: `runs/algorithm_level/<tag>/openssl_speed/*.txt`

The scripts also clone upstream sources under:

- `runs/algorithm_level/<tag>/work/`


