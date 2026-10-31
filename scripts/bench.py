#!/usr/bin/env python3
"""Benchmark the CPU in four configurations and write results/.

Configurations (Verilog parameters, so the same RTL is measured each time):
    baseline    no forwarding, static not-taken prediction
    +fwd        forwarding,    static not-taken prediction
    +bp         no forwarding, BTB + 2-bit BHT
    final       forwarding,    BTB + 2-bit BHT

Each benchmark measures only its kernel with the hardware counters (see
sw/common/bench.h) and prints a STATS line, which is parsed here.
Outputs: results/perf.md, results/perf.json, results/cpi.png
"""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESULTS = ROOT / "results"
BENCHES = ["sort", "matmul", "crc32", "fib", "sieve"]
CONFIGS = [  # (key, label, FWD, BP)
    ("baseline", "No forwarding, static prediction", 0, 0),
    ("fwd", "Forwarding, static prediction", 1, 0),
    ("bp", "No forwarding, BTB + 2-bit BHT", 0, 1),
    ("final", "Forwarding + BTB + 2-bit BHT", 1, 1),
]
# Reference categorical palette, slots 1-4 in fixed order (validated)
COLORS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"]
STATS = re.compile(r"STATS name=(\w+) cycles=(\d+) instret=(\d+) mispredicts=(\d+) stalls=(\d+)")


def main() -> int:
    subprocess.run(["make", "-s", "-C", str(ROOT / "sw")], check=True)
    data = {}
    for key, label, fwd, bp in CONFIGS:
        subprocess.run(["make", "-s", "-C", str(ROOT), "sim", f"FWD={fwd}", f"BP={bp}"],
                       check=True, stdout=subprocess.DEVNULL)
        sim = ROOT / "build" / f"sim_fwd{fwd}_bp{bp}" / "Vsoc"
        data[key] = {}
        for b in BENCHES:
            r = subprocess.run([str(sim), f"+hex={ROOT / 'sw' / 'build' / f'{b}.hex'}"],
                               capture_output=True, text=True)
            m = STATS.search(r.stdout)
            if r.returncode != 0 or not m:
                print(f"{b} failed on {key}:\n{r.stdout}\n{r.stderr}")
                return 1
            cyc, ins, mis, stl = map(int, m.groups()[1:])
            data[key][b] = {"cycles": cyc, "instret": ins, "mispredicts": mis,
                            "stall_cycles": stl, "cpi": cyc / ins}
            print(f"  {key:9s} {b:7s} CPI {cyc / ins:.3f}")

    RESULTS.mkdir(exist_ok=True)
    (RESULTS / "perf.json").write_text(json.dumps(data, indent=2) + "\n")

    # ---------------- markdown tables ----------------
    lines = ["### CPI by configuration (kernel only, lower is better)", "",
             "| Benchmark | " + " | ".join(c[1] for c in CONFIGS) + " | Speed-up |",
             "| --- | " + " | ".join("---:" for _ in CONFIGS) + " | ---: |"]
    for b in BENCHES:
        row = [f"{data[k][b]['cpi']:.3f}" for k, *_ in CONFIGS]
        speed = data["baseline"][b]["cycles"] / data["final"][b]["cycles"]
        lines.append(f"| {b} | " + " | ".join(row) + f" | {speed:.2f}x |")
    lines += ["", "### Final configuration detail", "",
              "| Benchmark | Instructions | Cycles | CPI | Mispredicts | MPKI | Load-use stall cycles |",
              "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for b in BENCHES:
        d = data["final"][b]
        mpki = 1000 * d["mispredicts"] / d["instret"]
        lines.append(f"| {b} | {d['instret']:,} | {d['cycles']:,} | {d['cpi']:.3f} | "
                     f"{d['mispredicts']:,} | {mpki:.1f} | {d['stall_cycles']:,} |")
    (RESULTS / "perf.md").write_text("\n".join(lines) + "\n")

    # ---------------- chart ----------------
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(figsize=(9, 5.0), dpi=150)
    fig.patch.set_facecolor("#fcfcfb")
    ax.set_facecolor("#fcfcfb")
    n = len(CONFIGS)
    width = 0.19
    for i, (key, label, *_rest) in enumerate(CONFIGS):
        xs = [j + (i - (n - 1) / 2) * (width + 0.01) for j in range(len(BENCHES))]
        ys = [data[key][b]["cpi"] for b in BENCHES]
        ax.bar(xs, ys, width, color=COLORS[i], label=label, edgecolor="#fcfcfb", linewidth=1)
        if key in ("baseline", "final"):        # selective direct labels
            for x, y in zip(xs, ys):
                ax.text(x, y + 0.02, f"{y:.2f}", ha="center", va="bottom", fontsize=7,
                        color="#52514e")
    ax.axhline(1.0, color="#52514e", linewidth=0.8, linestyle=(0, (3, 3)),
               label="Ideal pipeline (CPI = 1)")
    ax.set_xticks(range(len(BENCHES)), BENCHES, color="#0b0b0b")
    ax.set_ylabel("Cycles per instruction (CPI)", color="#52514e")
    ax.set_ylim(0, max(data["baseline"][b]["cpi"] for b in BENCHES) * 1.15)
    ax.set_title("Forwarding and branch prediction bring CPI close to 1",
                 loc="left", fontsize=12, color="#0b0b0b")
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    for s in ("left", "bottom"):
        ax.spines[s].set_color("#c3c2b7")
    ax.tick_params(colors="#52514e")
    ax.yaxis.grid(True, color="#e8e7e2", linewidth=0.6)
    ax.set_axisbelow(True)
    ax.legend(frameon=False, fontsize=8, ncol=3, loc="upper center", bbox_to_anchor=(0.5, -0.09))
    fig.tight_layout()
    fig.savefig(RESULTS / "cpi.png", facecolor=fig.get_facecolor())
    print(f"wrote {RESULTS / 'perf.md'} and {RESULTS / 'cpi.png'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
