#!/usr/bin/env python3
"""Random RV32I program generator for co-simulation stress testing.

Programs are built to hit the hard cases of a pipeline as often as possible:
  * a small register pool (x1-x8 most of the time) so back-to-back RAW
    dependencies, load-use hazards and forwarding paths are constantly used;
  * loads and stores of every size to a shared buffer (store->load ordering);
  * forward branches of every condition, JAL, JALR through a computed address,
    and short counted loops (backward branches the predictor must learn);
  * writes to x0, which must be ignored.

Correctness is checked by the testbench: every retired instruction is compared
against the ISS, so the program itself just runs and exits.

usage: gen.py <seed> <out.S> [--length N]
"""
import argparse
import random

ALU_R = ["add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"]
ALU_I = ["addi", "slti", "sltiu", "xori", "ori", "andi"]
SHIFT_I = ["slli", "srli", "srai"]
BRANCH = ["beq", "bne", "blt", "bge", "bltu", "bgeu"]
LOADS = [("lb", 1), ("lbu", 1), ("lh", 2), ("lhu", 2), ("lw", 4)]
STORES = [("sb", 1), ("sh", 2), ("sw", 4)]

BUF = "x31"      # base address of the data buffer (never written by random code)
LOOP = "x30"     # loop counter (only written by loop scaffolding)
LINK = "x28"     # link register for subroutine calls (never written by random code)
TMP = "x29"      # scratch for computed jump addresses
NSUB = 3         # shared subroutines, called from many sites
BUF_BYTES = 256


class Gen:
    def __init__(self, seed: int):
        self.r = random.Random(seed)
        self.out = []
        self.label = 0

    def reg(self, allow_zero=False):
        r = self.r
        if allow_zero and r.random() < 0.05:
            return "x0"
        if r.random() < 0.8:
            return f"x{r.randint(1, 8)}"          # hot pool -> many hazards
        return f"x{r.randint(1, 27)}"

    def new_label(self):
        self.label += 1
        return f"L{self.label}"

    def emit(self, s):
        self.out.append("    " + s)

    def alu(self):
        r = self.r
        k = r.random()
        rd = self.reg(allow_zero=True)
        if k < 0.4:
            self.emit(f"{r.choice(ALU_R)} {rd}, {self.reg(True)}, {self.reg(True)}")
        elif k < 0.7:
            self.emit(f"{r.choice(ALU_I)} {rd}, {self.reg(True)}, {r.randint(-2048, 2047)}")
        elif k < 0.85:
            self.emit(f"{r.choice(SHIFT_I)} {rd}, {self.reg(True)}, {r.randint(0, 31)}")
        elif k < 0.93:
            self.emit(f"lui {rd}, {r.randint(0, 0xFFFFF)}")
        else:
            self.emit(f"auipc {rd}, {r.randint(0, 0xFF)}")

    def mem(self):
        r = self.r
        if r.random() < 0.5:
            op, size = r.choice(LOADS)
            off = r.randrange(0, BUF_BYTES, size)
            self.emit(f"{op} {self.reg(True)}, {off}({BUF})")
        else:
            op, size = r.choice(STORES)
            off = r.randrange(0, BUF_BYTES, size)
            self.emit(f"{op} {self.reg(True)}, {off}({BUF})")

    def load_use(self):
        """A load immediately followed by an instruction that uses its result."""
        r = self.r
        rd = f"x{r.randint(1, 8)}"
        op, size = r.choice(LOADS)
        self.emit(f"{op} {rd}, {r.randrange(0, BUF_BYTES, size)}({BUF})")
        self.emit(f"{r.choice(ALU_R)} {self.reg()}, {rd}, {self.reg(True)}")

    def fwd_branch(self):
        r = self.r
        target = self.new_label()
        self.emit(f"{r.choice(BRANCH)} {self.reg(True)}, {self.reg(True)}, {target}")
        for _ in range(r.randint(0, 3)):
            self.alu()
        self.out.append(f"{target}:")

    def jal(self):
        target = self.new_label()
        self.emit(f"jal {self.reg(True)}, {target}")
        for _ in range(self.r.randint(0, 2)):
            self.alu()
        self.out.append(f"{target}:")

    def jalr(self):
        """Computed jump; an odd offset checks that bit 0 of the target is cleared."""
        target = self.new_label()
        self.emit(f"la {TMP}, {target}")
        self.emit(f"jalr {self.reg(True)}, {self.r.choice([0, 1])}({TMP})")
        for _ in range(self.r.randint(0, 2)):
            self.alu()
        self.out.append(f"{target}:")

    def call(self):
        """Call a shared subroutine: the same return instruction goes back to many
        different addresses, which the BTB must not predict blindly."""
        self.emit(f"jal {LINK}, sub{self.r.randrange(NSUB)}")

    def loop(self):
        top = self.new_label()
        self.emit(f"li {LOOP}, {self.r.randint(2, 12)}")
        self.out.append(f"{top}:")
        for _ in range(self.r.randint(1, 6)):
            self.simple()
        if self.r.random() < 0.4:
            self.call()
        self.emit(f"addi {LOOP}, {LOOP}, -1")
        self.emit(f"bnez {LOOP}, {top}")

    def simple(self):
        k = self.r.random()
        if k < 0.6:
            self.alu()
        elif k < 0.85:
            self.mem()
        elif k < 0.95:
            self.load_use()
        else:
            self.fwd_branch()

    def program(self, length: int) -> str:
        r = self.r
        self.out = [
            "    .section .text.init",
            "    .globl _start",
            "_start:",
            f"    la {BUF}, buffer",
        ]
        for i in range(1, 28):
            self.emit(f"li x{i}, {r.randint(-2**31, 2**31 - 1)}")
        while len(self.out) < length:
            k = r.random()
            if k < 0.45:
                self.alu()
            elif k < 0.65:
                self.mem()
            elif k < 0.75:
                self.load_use()
            elif k < 0.85:
                self.fwd_branch()
            elif k < 0.90:
                self.jal()
            elif k < 0.94:
                self.jalr()
            elif k < 0.97:
                self.loop()
            elif k < 0.99:
                self.call()
            else:
                self.emit("fence")
        self.out += [
            "    li t0, 0x10000010",
            "    li t1, 1",
            "    sw t1, 0(t0)",
            "1:  j 1b",
            "",
        ]
        for i in range(NSUB):
            self.out.append(f"sub{i}:")
            for _ in range(r.randint(1, 4)):
                self.alu()
            self.emit(f"jalr x0, 0({LINK})")
        self.out += [
            "",
            "    .data",
            "    .align 4",
            "buffer:",
        ]
        for _ in range(BUF_BYTES // 4):
            self.out.append(f"    .word 0x{r.getrandbits(32):08x}")
        return "\n".join(self.out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("seed", type=int)
    ap.add_argument("out")
    ap.add_argument("--length", type=int, default=600)
    a = ap.parse_args()
    with open(a.out, "w") as f:
        f.write(Gen(a.seed).program(a.length))


if __name__ == "__main__":
    main()
