"""pytest entry point: builds each module with Icarus Verilog and runs its
cocotb tests from tb_units.py.   Run with:  make -C tests/unit"""
import pathlib

import pytest
from cocotb_tools.runner import get_runner

HERE = pathlib.Path(__file__).resolve().parent
RTL = HERE.parent.parent / "rtl"

UNITS = {
    "alu": (["riscv_pkg.sv", "alu.sv"], ["alu_matches_model"]),
    "imm_gen": (["riscv_pkg.sv", "imm_gen.sv"], ["imm_gen_matches_model"]),
    "regfile": (["regfile.sv"], ["regfile_behaviour"]),
    "branch_predictor": (["branch_predictor.sv"], ["branch_predictor_training"]),
}


@pytest.mark.parametrize("top", UNITS.keys())
def test_unit(top):
    sources, tests = UNITS[top]
    runner = get_runner("icarus")
    build_dir = HERE / "sim_build" / top
    runner.build(sources=[RTL / s for s in sources], hdl_toplevel=top,
                 build_args=["-g2012"], build_dir=build_dir, always=True,
                 timescale=("1ns", "1ps"))
    runner.test(hdl_toplevel=top, test_module="tb_units", testcase=tests,
                build_dir=build_dir, test_dir=HERE)
