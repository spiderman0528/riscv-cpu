#!/usr/bin/env python3
"""Run every C program in sw/ on the simulator with co-simulation enabled."""
import argparse
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sim", required=True)
    a = ap.parse_args()
    progs = sorted((ROOT / "sw" / "build").glob("*.hex"))
    failed = 0
    for hexf in progs:
        r = subprocess.run([a.sim, f"+hex={hexf}"], capture_output=True, text=True)
        last = r.stderr.strip().splitlines()[-1] if r.stderr.strip() else ""
        print(f"  {'PASS' if r.returncode == 0 else 'FAIL'}  {hexf.stem:8s} {last}")
        failed += r.returncode != 0
    print(f"programs: {len(progs) - failed}/{len(progs)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
