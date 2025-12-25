#!/usr/bin/env python3
"""
Simple plotting helper for generated analysis CSV files.

Example:
  python3 analysis/plot_figures.py runs/mlkem512_mldsa44_try1/analysis_1.csv out_mlkem512.png

This script is intentionally minimal (supplementary-quality).
"""

import sys
import pandas as pd
import matplotlib.pyplot as plt

def main():
    if len(sys.argv) != 3:
        print("Usage: plot_figures.py <analysis.csv> <out.png>")
        return 1

    in_csv, out_png = sys.argv[1], sys.argv[2]
    df = pd.read_csv(in_csv)

    # Plot CH→END distribution as a simple histogram
    plt.figure()
    plt.hist(df["CH_to_END_ms"], bins=40)
    plt.xlabel("CH→END (ms)")
    plt.ylabel("Count")
    plt.title("TLS 1.3 Handshake Completion Time Distribution")
    plt.tight_layout()
    plt.savefig(out_png, dpi=200)
    print(f"Saved: {out_png}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
