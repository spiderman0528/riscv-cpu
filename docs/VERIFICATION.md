# Verification

The goal is not "the demo program printed hello" but evidence that every
instruction the pipeline commits is architecturally correct, under the hazard
and branch patterns that break pipelines.

## Layers

| Layer | Tool | What it proves | Command |
| --- | --- | --- | --- |
| Lint | Verilator `-Wall` | No width mismatches, latches, undriven or multi-driven signals | `make lint` |
| Unit tests | cocotb + Icarus | ALU (23,100 checks), immediate decoder (5,000 random instructions), register file (x0, bypass, 3,000 random cycles), predictor training | `make test-unit` |
| Compliance | official riscv-tests `rv32ui` | Every RV32I instruction against the reference suite (41 pass, `ma_data` skipped: no misaligned support) | `make test-isa` |
| Random co-simulation | Python generator + C++ ISS | 200 random programs (~200k instructions), each retired instruction compared with the golden model | `make test-random` |
| Programs | C benchmarks | Real compiled code, self-checking results, co-simulated | `make test-sw` |
| Mutation testing | `scripts/mutation_test.py` | The suites above detect realistic pipeline bugs | `python3 scripts/mutation_test.py` |

## Lock-step co-simulation

`sim/iss.cpp` is a plain instruction-set simulator: one `switch` over the
opcode, written from the ISA manual with no pipeline knowledge. The Verilator
testbench (`sim/tb_main.cpp`) watches the core's retirement port. For every
retired instruction it steps the ISS once and compares:

* PC and instruction word (catches wrong-path instructions that escaped a flush,
  and skipped or duplicated instructions)
* destination register and value (catches forwarding and hazard bugs)
* store address, size and data (catches byte-lane and ordering bugs)

The first difference stops the run with a message such as:

```
[FAIL] register write mismatch at pc 0x00000024 (inst 0x40c5d733):
       RTL writes a4=0x40000000, ISS writes a4=0xc0000000
```

CSR reads of the counters are timing-dependent, so for those the ISS takes the
RTL's value instead of comparing.

## Random program generator

`tests/random/gen.py` aims at the corner cases rather than uniform randomness:

* 80% of register choices come from x1-x8, so back-to-back dependencies, load-use
  pairs and both forwarding paths are exercised constantly;
* loads and stores of every width to a shared buffer;
* forward branches of every condition, `JAL`, `JALR` with odd offsets (bit 0
  must be cleared), counted loops (backward branches the predictor learns),
  and shared subroutines called from many places (one return instruction, many
  different targets);
* writes to `x0`.

## Mutation testing

Each mutant injects one realistic bug into a copy of the RTL; the suites must
catch it. The current score is in [`results/mutation.md`](../results/mutation.md).

The first version of the random generator caught 12 of the 14 bugs. Two
survived: a misprediction check that ignored the predicted *target*, and a
`JALR` that did not clear bit 0 of its target. Neither the official tests nor
the generator ever produced the situation that exposes them: a `JALR` whose
target changes between executions, or an odd jump address. Adding shared
subroutines and odd `JALR` offsets to the generator caught both. This is the
point of mutation testing: it measures the test suite, not the design.

One candidate mutant was removed because it is *equivalent*: letting EX/MEM
forward load results changes nothing, since the load-use stall guarantees no
dependent instruction is ever in EX at that moment.
