#!/usr/bin/env python3
"""Generate random programs and run each one with lock-step co-simulation.

usage: run.py --sim <Vsoc> [--count N] [--start-seed S] [--length L]
"""
import argparse
import concurrent.futures as cf
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
BUILD = HERE / "build"

CFLAGS = ["--target=riscv32-unknown-elf", "-march=rv32i_zicsr", "-mabi=ilp32",
          "-nostdlib", "-static", "-fuse-ld=lld", "-mno-relax", "-Wl,--no-relax"]


def run_one(sim: str, seed: int, length: int):
    asm = BUILD / f"rand_{seed}.S"
    elf, binf, hexf = asm.with_suffix(".elf"), asm.with_suffix(".bin"), asm.with_suffix(".hex")
    subprocess.run([sys.executable, str(HERE / "gen.py"), str(seed), str(asm),
                    "--length", str(length)], check=True)
    subprocess.run(["clang", *CFLAGS, f"-Wl,-T,{ROOT / 'sw' / 'common' / 'link.ld'}",
                    "-o", str(elf), str(asm)], check=True)
    subprocess.run(["llvm-objcopy", "-O", "binary", str(elf), str(binf)], check=True)
    subprocess.run([sys.executable, str(ROOT / "scripts" / "elf2hex.py"), str(binf), str(hexf)],
                   check=True)
    r = subprocess.run([sim, f"+hex={hexf}", "--max-cycles", "200000"],
                       capture_output=True, text=True)
    last = r.stderr.strip().splitlines()[-1] if r.stderr.strip() else ""
    if r.returncode == 0:
        for p in (asm, elf, binf, hexf):     # keep only failing cases
            p.unlink(missing_ok=True)
    return seed, r.returncode == 0, last


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sim", required=True)
    ap.add_argument("--count", type=int, default=200)
    ap.add_argument("--start-seed", type=int, default=1)
    ap.add_argument("--length", type=int, default=600)
    a = ap.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    sim = str(pathlib.Path(a.sim).resolve())

    seeds = range(a.start_seed, a.start_seed + a.count)
    failures, instr = [], 0
    with cf.ThreadPoolExecutor(max_workers=os.cpu_count() or 2) as ex:
        for seed, ok, last in ex.map(lambda s: run_one(sim, s, a.length), seeds):
            if ok:
                for part in last.split("|"):
                    if "instret" in part:
                        instr += int(part.split()[-1])
            else:
                failures.append((seed, last))
                print(f"  FAIL seed {seed}: {last}")

    print(f"random tests: {a.count - len(failures)}/{a.count} passed, "
          f"{instr} instructions checked against the ISS")
    if failures:
        print(f"failing programs kept in {BUILD}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
