# riscv-cpu top-level Makefile
#
#   make sim                 build the Verilator simulator (default config)
#   make run PROG=hello      build + run a C program from sw/ with co-simulation
#   make wave PROG=hello     same, and dump build/wave.vcd for GTKWave
#   make test                everything below
#   make test-unit           cocotb unit tests (Icarus Verilog)
#   make test-isa            official riscv-tests (rv32ui) with co-simulation
#   make test-random         random-instruction programs with co-simulation
#   make test-sw             C programs and benchmarks with co-simulation
#   make bench               performance comparison across CPU configurations
#   make lint                Verilator lint (-Wall)

VERILATOR ?= verilator
RTL       := $(shell cat rtl/files.f)
SIM_SRC   := $(abspath sim/tb_main.cpp sim/iss.cpp)
BUILD     := build
JOBS      ?= $(shell nproc)

# CPU configuration: FWD=0/1 (forwarding), BP=0/1 (dynamic branch prediction)
FWD ?= 1
BP  ?= 1
CFG := fwd$(FWD)_bp$(BP)
SIM := $(BUILD)/sim_$(CFG)/Vsoc

PROG ?= hello

.PHONY: all sim run wave test test-unit test-isa test-random test-sw bench lint clean sw

all: sim

$(BUILD)/sim_%/Vsoc: $(RTL) $(SIM_SRC) rtl/lint.vlt
	$(VERILATOR) --cc --exe --build -j $(JOBS) -O3 --trace \
	  -Wall -DSIMULATION --top-module soc rtl/lint.vlt $(RTL) $(SIM_SRC) \
	  -GFORWARDING=$(FWD) -GBP_ENABLE=$(BP) -GSIM_UART=1 \
	  -CFLAGS "-O2 -std=c++17 -I$(CURDIR)/sim" --Mdir $(BUILD)/sim_$* -o Vsoc > $(BUILD)/sim_$*.log 2>&1 \
	  || (cat $(BUILD)/sim_$*.log; exit 1)

sim: | $(BUILD)
	@$(MAKE) --no-print-directory $(SIM)

sw:
	@$(MAKE) --no-print-directory -C sw

run: sim
	@$(MAKE) --no-print-directory -C sw build/$(PROG).hex
	$(SIM) +hex=sw/build/$(PROG).hex

wave: sim
	@$(MAKE) --no-print-directory -C sw build/$(PROG).hex
	$(SIM) +hex=sw/build/$(PROG).hex --trace $(BUILD)/wave.vcd
	@echo "waveform: $(BUILD)/wave.vcd (open with gtkwave)"

test: lint test-unit test-isa test-random test-sw

test-unit:
	$(MAKE) -C tests/unit

test-isa: sim
	python3 tests/riscv-tests/run.py --sim $(SIM)

test-random: sim
	python3 tests/random/run.py --sim $(SIM) --count 200

test-sw: sim sw
	python3 scripts/run_programs.py --sim $(SIM)

bench:
	python3 scripts/bench.py

lint:
	$(VERILATOR) --lint-only -Wall -DSIMULATION --top-module soc rtl/lint.vlt $(RTL)
	@echo "lint: clean"

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD) sw/build tests/riscv-tests/build tests/random/build
	$(MAKE) -C tests/unit clean
