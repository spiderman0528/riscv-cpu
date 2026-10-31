#!/usr/bin/env bash
# Open-source synthesis + place & route for a resource and Fmax estimate.
#
#   sv2v (SystemVerilog -> Verilog) -> Yosys synth_ecp5 -> nextpnr-ecp5
#
# Target: Lattice ECP5 LFE5U-45F (the 64 KiB RAM needs more block RAM than a -25F has), speed grade 6. This is an *estimate* that
# needs no vendor tools; the DE10-Lite numbers come from Quartus (see fpga/).
# usage: scripts/synth_ecp5.sh [path/to/sv2v]
set -euo pipefail
cd "$(dirname "$0")/.."
SV2V=${1:-sv2v}
OUT=build/ecp5
mkdir -p "$OUT"

make -s -C sw fpga
cp fpga/firmware.hex "$OUT/firmware.hex"
"$SV2V" $(cat rtl/files.f) fpga/de10_lite_top.sv > "$OUT/cpu.v"

cd "$OUT"
yosys -q -l yosys.log -p "read_verilog cpu.v; synth_ecp5 -top de10_lite_top -json cpu.json"
nextpnr-ecp5 --45k --speed 6 --package CABGA256 --json cpu.json --textcfg cpu.config \
  --freq 25 --seed 1 --log nextpnr.log --report report.json > /dev/null 2>&1
grep -E "Max frequency|TRELLIS_COMB|TRELLIS_FF|TRELLIS_RAMW|DP16KD" nextpnr.log | tail -8
