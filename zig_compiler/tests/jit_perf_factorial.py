#!/usr/bin/env python3
"""
JIT Performance Test: Factorial — Python reference implementation

Computes 18! iteratively inside a tight outer loop.
This is the exact same algorithm as jit_perf_factorial.bas for direct
wall-clock comparison.

Usage:
  python3 jit_perf_factorial.py              # default 10M reps
  python3 jit_perf_factorial.py 500000000    # 500M reps (slow!)

Compare with:
  fbc --jit --metrics tests/jit_perf_factorial.bas
"""

import sys
import time


def main():
    reps = int(sys.argv[1]) if len(sys.argv) > 1 else 10_000_000
    total = 0

    t_start = time.perf_counter()

    outer = 0
    while outer < reps:
        # Compute 18! iteratively
        n = 18
        fact = 1
        i = 2
        while i <= n:
            fact = fact * i
            i = i + 1

        # Accumulate with prime modulus so the work cannot be optimised away
        total = total + (fact % 997)

        outer = outer + 1

    t_end = time.perf_counter()
    elapsed_ms = (t_end - t_start) * 1000.0

    print(f"Repetitions: {reps}")
    print(f"18! = {fact}")
    print(f"Checksum:    {total}")
    print(f"Elapsed:     {elapsed_ms:.3f} ms")


if __name__ == "__main__":
    main()
