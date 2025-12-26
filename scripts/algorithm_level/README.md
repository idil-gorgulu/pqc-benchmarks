# Algorithm-level scripts

This folder contains **microbenchmark runners** for algorithm-level measurements (as opposed to the TLS-level pipeline under `scripts/tls_level/run_burst.sh`).

These scripts were derived from the step-by-step commands captured in `terminal_log_algorithm_level.txt`, but packaged in a reproducible, repo-friendly way.

## What gets run

- **Kyber (pq-crystals/kyber)**:
  - `ref/test`: `test_kyber{512,768,1024}` and `test_speed{512,768,1024}`
  - `avx2/test`: same binaries (**Linux x86_64 only**, auto-skipped otherwise)
- **Dilithium (pq-crystals/dilithium)**:
  - `ref/test`: `test_dilithium{2,3,5}` and `test_speed{2,3,5}`
  - `avx2/test`: `make speed` + `make`, then run `test_speed{2,3,5}` and `test_dilithium{2,3,5}` (**Linux x86_64 only**, auto-skipped otherwise)
- **OpenSSL baseline**:
  - `openssl speed rsa2048`, `openssl speed ecdsa`, `openssl speed ecdh`

## Usage

Prefer the single driver:

```bash
./scripts/algorithm_level/run_all.sh --tag wsl_try1
```

Outputs default to:

- `runs/algorithm_level/<tag>/kyber/*.log`
- `runs/algorithm_level/<tag>/dilithium/*.log`
- `runs/algorithm_level/<tag>/openssl_speed/*.txt`

## Notes

- CPU pinning uses `taskset` if available; otherwise scripts run unpinned (with a warning).
- The scripts print `cpu MHz` lines from `/proc/cpuinfo` when available (Linux), to mirror your original terminal log.
- The TLS-level pipeline scripts are organized under `scripts/tls_level/`.


