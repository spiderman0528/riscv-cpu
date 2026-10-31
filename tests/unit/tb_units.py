"""cocotb unit tests for the individual pipeline building blocks.

Each test drives one module with directed corner cases plus thousands of
random stimuli and checks it against a small Python reference model.
"""
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, ReadOnly

MASK = 0xFFFFFFFF
CORNERS = [0, 1, 2, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0xFFFFFFFE, 0x12345678, 31, 32]


def s32(x):
    x &= MASK
    return x - (1 << 32) if x & 0x80000000 else x


# ---------------------------------------------------------------------------
# ALU
# ---------------------------------------------------------------------------
ALU_OPS = {
    0: lambda a, b: a + b,
    1: lambda a, b: a - b,
    2: lambda a, b: a << (b & 31),
    3: lambda a, b: int(s32(a) < s32(b)),
    4: lambda a, b: int(a < b),
    5: lambda a, b: a ^ b,
    6: lambda a, b: a >> (b & 31),
    7: lambda a, b: s32(a) >> (b & 31),
    8: lambda a, b: a | b,
    9: lambda a, b: a & b,
    10: lambda a, b: b,
}


@cocotb.test()
async def alu_matches_model(dut):
    """Every ALU op on corner values and 2,000 random operand pairs."""
    rng = random.Random(1)
    pairs = [(a, b) for a in CORNERS for b in CORNERS]
    pairs += [(rng.getrandbits(32), rng.getrandbits(32)) for _ in range(2000)]
    for op, fn in ALU_OPS.items():
        for a, b in pairs:
            dut.op.value, dut.a.value, dut.b.value = op, a, b
            await Timer(1, unit="ns")
            want = fn(a, b) & MASK
            got = int(dut.y.value)
            assert got == want, f"op {op}: a=0x{a:08x} b=0x{b:08x} got 0x{got:08x} want 0x{want:08x}"


# ---------------------------------------------------------------------------
# Immediate generator
# ---------------------------------------------------------------------------
def sext(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def imm_model(inst):
    op = inst & 0x7F
    f = lambda hi, lo: (inst >> lo) & ((1 << (hi - lo + 1)) - 1)
    if op == 0x23:
        v = sext((f(31, 25) << 5) | f(11, 7), 12)
    elif op == 0x63:
        v = sext((f(31, 31) << 12) | (f(7, 7) << 11) | (f(30, 25) << 5) | (f(11, 8) << 1), 13)
    elif op in (0x37, 0x17):
        v = inst & 0xFFFFF000
    elif op == 0x6F:
        v = sext((f(31, 31) << 20) | (f(19, 12) << 12) | (f(20, 20) << 11) | (f(30, 21) << 1), 21)
    else:
        v = sext(f(31, 20), 12)
    return v & MASK


@cocotb.test()
async def imm_gen_matches_model(dut):
    """Immediates for every format, 5,000 random instructions."""
    rng = random.Random(2)
    opcodes = [0x13, 0x03, 0x67, 0x23, 0x63, 0x37, 0x17, 0x6F, 0x73]
    for _ in range(5000):
        inst = (rng.getrandbits(25) << 7) | rng.choice(opcodes)
        dut.inst.value = inst
        await Timer(1, unit="ns")
        assert int(dut.imm.value) == imm_model(inst), f"inst 0x{inst:08x}"


# ---------------------------------------------------------------------------
# Register file
# ---------------------------------------------------------------------------
@cocotb.test()
async def regfile_behaviour(dut):
    """x0 stays zero, write-through bypass, and random read/write traffic."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    model = [0] * 32
    rng = random.Random(3)

    # registers are not reset (like most register files): write them all first
    for i in range(1, 32):
        dut.we.value, dut.waddr.value, dut.wdata.value = 1, i, 0
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
    dut.we.value = 0
    await RisingEdge(dut.clk)

    # x0 can never be written
    dut.we.value, dut.waddr.value, dut.wdata.value = 1, 0, 0xDEADBEEF
    dut.raddr1.value = 0
    await ReadOnly()
    assert int(dut.rdata1.value) == 0, "x0 must read as zero even while being written"
    await RisingEdge(dut.clk)

    # bypass: same-cycle write and read returns the new value
    await Timer(1, unit="ns")
    dut.we.value, dut.waddr.value, dut.wdata.value = 1, 5, 0xCAFEF00D
    dut.raddr1.value, dut.raddr2.value = 5, 5
    await ReadOnly()
    assert int(dut.rdata1.value) == 0xCAFEF00D and int(dut.rdata2.value) == 0xCAFEF00D
    await RisingEdge(dut.clk)
    model[5] = 0xCAFEF00D

    for _ in range(3000):
        await Timer(1, unit="ns")
        we, wa, wd = rng.getrandbits(1), rng.randrange(32), rng.getrandbits(32)
        r1, r2 = rng.randrange(32), rng.randrange(32)
        dut.we.value, dut.waddr.value, dut.wdata.value = we, wa, wd
        dut.raddr1.value, dut.raddr2.value = r1, r2
        await ReadOnly()
        view = model[:]
        if we and wa:
            view[wa] = wd
        assert int(dut.rdata1.value) == view[r1], f"rdata1 x{r1}"
        assert int(dut.rdata2.value) == view[r2], f"rdata2 x{r2}"
        await RisingEdge(dut.clk)
        model = view


# ---------------------------------------------------------------------------
# Branch predictor
# ---------------------------------------------------------------------------
async def bp_update(dut, pc, is_cond, taken, target):
    await Timer(1, unit="ns")
    dut.upd_valid.value, dut.upd_pc.value = 1, pc
    dut.upd_is_cond.value, dut.upd_taken.value, dut.upd_target.value = is_cond, taken, target
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    dut.upd_valid.value = 0


async def bp_predict(dut, pc):
    dut.pc.value = pc
    await Timer(1, unit="ns")
    taken = int(dut.pred_taken.value)
    # the target is only meaningful (and only initialised) on a predicted-taken hit
    return taken, (int(dut.pred_target.value) if taken else None)


@cocotb.test()
async def branch_predictor_training(dut):
    """2-bit hysteresis, BTB targets, and unconditional jumps."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst.value, dut.upd_valid.value, dut.pc.value = 1, 0, 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0

    assert (await bp_predict(dut, 0x100))[0] == 0, "cold BTB must predict not-taken"

    # a loop branch: one taken update -> weakly taken -> predicted taken
    await bp_update(dut, 0x100, 1, 1, 0x80)
    assert await bp_predict(dut, 0x100) == (1, 0x80)

    # strongly taken after a second taken; one not-taken must not flip it (hysteresis)
    await bp_update(dut, 0x100, 1, 1, 0x80)
    await bp_update(dut, 0x100, 1, 0, 0x80)
    assert (await bp_predict(dut, 0x100))[0] == 1, "one not-taken should not flip a strong counter"
    await bp_update(dut, 0x100, 1, 0, 0x80)
    assert (await bp_predict(dut, 0x100))[0] == 0, "two not-taken should flip it"

    # unconditional jump: always predicted taken once seen
    await bp_update(dut, 0x200, 0, 1, 0x400)
    assert await bp_predict(dut, 0x200) == (1, 0x400)

    # aliasing PC (same index, different tag) must miss
    assert (await bp_predict(dut, 0x200 + 64 * 4))[0] == 0, "tag check failed"
