# sw/Makefile - build C programs into hex images for the CPU.
#   make            build every program in examples/ and bench/
#   make build/X.hex
RVCC    ?= clang
OBJCOPY ?= llvm-objcopy
OBJDUMP ?= llvm-objdump

ARCH    := --target=riscv32-unknown-elf -march=rv32i_zicsr -mabi=ilp32
CFLAGS  := $(ARCH) -O2 -g -ffreestanding -fno-builtin -nostdlib -Wall -Wextra \
           -mno-relax -Icommon
LDFLAGS := $(ARCH) -nostdlib -fuse-ld=lld -Wl,-T,common/link.ld -Wl,--no-relax -static

COMMON  := common/crt0.S common/runtime.c
PROGS   := $(basename $(notdir $(wildcard examples/*.c bench/*.c)))

all: $(PROGS:%=build/%.hex)

build/%.elf: examples/%.c $(COMMON) common/runtime.h common/link.ld | build
	$(RVCC) $(CFLAGS) $(LDFLAGS) -o $@ $(COMMON) $<

build/%.elf: bench/%.c $(COMMON) common/runtime.h common/link.ld | build
	$(RVCC) $(CFLAGS) $(LDFLAGS) -o $@ $(COMMON) $<

build/%.hex: build/%.elf
	$(OBJCOPY) -O binary $< build/$*.bin
	python3 ../scripts/elf2hex.py build/$*.bin $@
	$(OBJDUMP) -d --no-show-raw-insn $< > build/$*.dis

build:
	mkdir -p build

clean:
	rm -rf build

.PHONY: all clean
.SECONDARY:
