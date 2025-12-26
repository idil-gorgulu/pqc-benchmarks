#!/usr/bin/env bash
set -euo pipefail

# Shared helpers for algorithm-level scripts.

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing required command: $1" >&2; exit 1; }
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

is_linux() {
  [[ "$(uname -s)" == "Linux" ]]
}

is_x86_64() {
  case "$(uname -m)" in
    x86_64|amd64) return 0 ;;
    *) return 1 ;;
  esac
}

# Print CPU MHz lines like in your terminal log (Linux /proc only).
print_cpu_mhz_like_log() {
  if [[ -r /proc/cpuinfo ]]; then
    grep -E "cpu MHz" /proc/cpuinfo || true
  else
    echo "[WARN] /proc/cpuinfo not available; skipping cpu MHz print."
  fi
}

# Build a prefix command for CPU pinning if taskset exists.
# Usage:
#   PIN=( $(pin_cmd 0) ); "${PIN[@]}" mycmd ...
pin_cmd() {
  local core="${1:-0}"
  if have_cmd taskset; then
    echo "taskset" "-c" "$core"
  else
    echo ""
  fi
}

# Safer variant for arrays:
#   PIN=( ); read -r -a PIN <<<"$(pin_cmd 0)";  # may be empty
read_pin_array() {
  local core="${1:-0}"
  local s=""
  s="$(pin_cmd "$core")"
  if [[ -n "$s" ]]; then
    # shellcheck disable=SC2206
    echo "$s"
  else
    echo ""
  fi
}

# Clone repo if missing; otherwise keep existing checkout.
ensure_git_clone() {
  local url="$1"
  local dir="$2"
  if [[ -d "$dir/.git" ]]; then
    echo "[INFO] Using existing repo: $dir"
    return 0
  fi
  need_cmd git
  echo "[INFO] Cloning $url -> $dir"
  git clone "$url" "$dir"
}


