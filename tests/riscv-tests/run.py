#!/usr/bin/env python3
"""Build and run the official riscv-tests (rv32ui) on the CPU with co-simulation.

The upstream repository is cloned (at a pinned commit) into
tests/riscv-tests/build/ the first time this script runs.
"""
import argparse
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
BUILD = HERE / "build"
UPSTREAM = "https://github.com/riscv-software-src/riscv-tests.git"
PINNED = "3df703cd52d5f0d8224e3c50bf03c6cb70efff98"

# ma_data checks misaligned loads/stores, which need trap support (not
# implemented: the core targets aligned accesses, as allowed by the spec).
SKIP = {"ma_data": "misaligned access needs trap support"}

CFLAGS = ["--target=riscv32-unknown-elf", "-march=rv32i_zicsr_zifencei", "-mabi=ilp32",
          "-nostdlib", "-static", "-fuse-ld=lld", "-mno-relax", "-Wl,--no-relax"]


def sh(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)


def fetch() -> pathlib.Path:
    repo = BUILD / "riscv-tests"
    if not (repo / "isa").exists():
        BUILD.mkdir(parents=True, exist_ok=True)
        sh(["git", "clone", "-q", UPSTREAM, str(repo)])
        sh(["git", "-C", str(repo), "checkout", "-q", PINNED])
    return repo


def build(repo: pathlib.Path, name: str) -> pathlib.Path:
    out = BUILD / "bin"
    out.mkdir(parents=True, exist_ok=True)
    elf, binf, hexf = out / f"{name}.elf", out / f"{name}.bin", out / f"{name}.hex"
    src = repo / "isa" / "rv32ui" / f"{name}.S"
    sh(["clang", *CFLAGS, f"-I{HERE / 'env'}", f"-I{repo / 'isa' / 'macros' / 'scalar'}",
        f"-Wl,-T,{ROOT / 'sw' / 'common' / 'link.ld'}", "-o", str(elf), str(src)])
    sh(["llvm-objcopy", "-O", "binary", str(elf), str(binf)])
    sh([sys.executable, str(ROOT / "scripts" / "elf2hex.py"), str(binf), str(hexf)])
    return hexf


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sim", required=True, help="path to the Verilator simulator binary")
    ap.add_argument("tests", nargs="*", help="run only these tests (default: all)")
    args = ap.parse_args()

    repo = fetch()
    names = args.tests or sorted(p.stem for p in (repo / "isa" / "rv32ui").glob("*.S"))
    passed, failed, skipped = [], [], []
    for name in names:
        if name in SKIP:
            skipped.append(name)
            print(f"  SKIP  {name:10s} ({SKIP[name]})")
            continue
        hexf = build(repo, name)
        r = subprocess.run([args.sim, f"+hex={hexf}", "--max-cycles", "100000"],
                           capture_output=True, text=True)
        ok = r.returncode == 0
        (passed if ok else failed).append(name)
        detail = r.stderr.strip().splitlines()[-1] if r.stderr.strip() else ""
        print(f"  {'PASS' if ok else 'FAIL'}  {name:10s} {'' if ok else detail}")

    print(f"\nriscv-tests rv32ui: {len(passed)} passed, {len(failed)} failed, "
          f"{len(skipped)} skipped")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
