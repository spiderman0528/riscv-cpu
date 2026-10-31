#!/usr/bin/env python3
"""Mutation testing: does the verification flow actually catch real bugs?

Each mutant injects one realistic pipeline bug into a copy of the RTL, builds
it, and runs the riscv-tests + random co-simulation suites against it. A
mutant is "killed" when at least one test fails. A good test suite kills all
of them.

usage: mutation_test.py [--random N]
"""
import argparse
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

# (description, file, original text, mutated text)
MUTANTS = [
    ("No load-use stall",
     "rtl/hazard_unit.sv", "assign stall = id_valid && ex_dep && ex_mem_read;",
     "assign stall = 1'b0;"),
    ("Forwarding priority reversed (MEM/WB before EX/MEM)",
     "rtl/forwarding_unit.sv",
     "if (mem_valid && mem_reg_we && !mem_is_load && mem_rd == rs)\n        value = mem_value;\n      else if (wb_valid && wb_reg_we && wb_rd == rs)\n        value = wb_value;",
     "if (wb_valid && wb_reg_we && wb_rd == rs)\n        value = wb_value;\n      else if (mem_valid && mem_reg_we && !mem_is_load && mem_rd == rs)\n        value = mem_value;"),
    ("Load-use check ignores rs2",
     "rtl/hazard_unit.sv",
     "((id_uses_rs1 && id_rs1 == ex_rd) || (id_uses_rs2 && id_rs2 == ex_rd))",
     "(id_uses_rs1 && id_rs1 == ex_rd)"),
    ("No EX/MEM forwarding path",
     "rtl/forwarding_unit.sv", "if (mem_valid && mem_reg_we && !mem_is_load && mem_rd == rs)",
     "if (1'b0)"),
    ("Register file write-through bypass removed",
     "rtl/regfile.sv", "else if (we && waddr == raddr1)    rdata1 = wdata;",
     "else if (1'b0)                    rdata1 = wdata;"),
    ("IF/ID not flushed on a misprediction",
     "rtl/core.sv", "if (rst || redirect_e) begin\n      d_valid <= 1'b0;",
     "if (rst) begin\n      d_valid <= 1'b0;"),
    ("ID/EX not flushed on a misprediction",
     "rtl/core.sv", "if (rst || redirect_e || stall_d) begin\n      e_valid <= 1'b0;",
     "if (rst || stall_d) begin\n      e_valid <= 1'b0;"),
    ("PC advances during a stall",
     "rtl/core.sv", "else if (stall_d)      pc_next = pc_f;",
     "else if (stall_d)      pc_next = pc_f + 32'd4;"),
    ("Misprediction check ignores the predicted target",
     "rtl/core.sv", "assign mispredict_e  = e_valid && (e_taken ? !(e_pred_taken && e_tgt_ok) : e_pred_taken);",
     "assign mispredict_e  = e_valid && (e_taken != e_pred_taken);"),
    ("BLT uses an unsigned comparison",
     "rtl/core.sv", "br_cond = ($signed(e_op1) <  $signed(e_op2));",
     "br_cond = (e_op1 <  e_op2);"),
    ("JALR does not clear bit 0 of the target",
     "rtl/core.sv", "assign e_target      = e_is_jalr ? {alu_y[31:1], 1'b0}",
     "assign e_target      = e_is_jalr ? alu_y"),
    ("Halfword store writes the wrong byte lanes",
     "rtl/core.sv", "dmem_be    = e_byte_off[1] ? 4'b1100 : 4'b0011;",
     "dmem_be    = e_byte_off[1] ? 4'b0011 : 4'b1100;"),
    ("LH zero-extends instead of sign-extending",
     "rtl/core.sv", "load_data = {{16{load_shifted[15]}}, load_shifted[15:0]};  // LH",
     "load_data = {16'b0, load_shifted[15:0]};  // LH"),
    ("SRA behaves like SRL",
     "rtl/alu.sv", "ALU_SRA:    y = $unsigned($signed(a) >>> shamt);",
     "ALU_SRA:    y = a >> shamt;"),
]


def build(rtl_dir: pathlib.Path, out: pathlib.Path) -> pathlib.Path:
    files = [str(rtl_dir / pathlib.Path(f).name)
             for f in (ROOT / "rtl" / "files.f").read_text().split()]
    subprocess.run(
        ["verilator", "--cc", "--exe", "--build", "-j", "0", "-Wall", "-DSIMULATION",
         "--top-module", "soc", str(rtl_dir / "lint.vlt"), *files,
         str(ROOT / "sim" / "tb_main.cpp"), str(ROOT / "sim" / "iss.cpp"), "-GSIM_UART=1",
         "-CFLAGS", f"-O1 -std=c++17 -I{ROOT / 'sim'}", "--Mdir", str(out), "-o", "Vsoc"],
        check=True, capture_output=True)
    return out / "Vsoc"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--random", type=int, default=40, help="random programs per mutant")
    a = ap.parse_args()

    killed = 0
    rows = []
    with tempfile.TemporaryDirectory() as tmp:
        for i, (desc, path, old, new) in enumerate(MUTANTS):
            work = pathlib.Path(tmp) / f"m{i}"
            shutil.copytree(ROOT / "rtl", work / "rtl")
            src = work / path
            text = src.read_text()
            if old not in text:
                print(f"  ERROR mutant '{desc}': pattern not found in {path}")
                return 2
            src.write_text(text.replace(old, new, 1))
            sim = build(work / "rtl", work / "obj")

            isa = subprocess.run([sys.executable, str(ROOT / "tests/riscv-tests/run.py"),
                                  "--sim", str(sim)], capture_output=True, text=True)
            rnd = subprocess.run([sys.executable, str(ROOT / "tests/random/run.py"),
                                  "--sim", str(sim), "--count", str(a.random),
                                  "--start-seed", "1000"], capture_output=True, text=True)
            isa_fail = isa.stdout.count("  FAIL ")
            rnd_fail = rnd.stdout.count("  FAIL seed")
            caught = isa_fail > 0 or rnd_fail > 0
            killed += caught
            rows.append((desc, isa_fail, rnd_fail, caught))
            print(f"  {'KILLED  ' if caught else 'SURVIVED'} {desc:52s} "
                  f"riscv-tests failing: {isa_fail:2d}   random failing: {rnd_fail:3d}/{a.random}")

    print(f"\nmutation score: {killed}/{len(MUTANTS)} injected bugs caught")
    out = ROOT / "results" / "mutation.md"
    out.parent.mkdir(exist_ok=True)
    with open(out, "w") as f:
        f.write("| Injected bug | riscv-tests failing | random programs failing | Caught |\n")
        f.write("| --- | ---: | ---: | :---: |\n")
        for desc, isa_fail, rnd_fail, caught in rows:
            f.write(f"| {desc} | {isa_fail} / 41 | {rnd_fail} / {a.random} | "
                    f"{'yes' if caught else '**no**'} |\n")
        f.write(f"\n**Mutation score: {killed}/{len(MUTANTS)}**\n")
    return 0 if killed == len(MUTANTS) else 1


if __name__ == "__main__":
    sys.exit(main())
