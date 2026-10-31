// riscv_test.h - minimal test environment for running the official
// riscv-tests (isa/rv32ui) on this bare-metal core.
//
// The upstream "p" environment sets up machine-mode traps and CSRs this core
// does not implement. The rv32ui tests only need the macros below:
//   pass -> store 1 to the exit register
//   fail -> store (TESTNUM << 1) | 1, so the failing sub-test is reported
#ifndef _ENV_RISCV_CPU_H
#define _ENV_RISCV_CPU_H

#define EXIT_ADDR 0x10000010

#define RVTEST_RV32U .macro init; .endm
#define RVTEST_RV64U .macro init; .endm

#define TESTNUM gp

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  6;                                                      \
        .globl _start;                                                  \
_start:                                                                 \
        init;

#define RVTEST_CODE_END                                                 \
        unimp

#define RVTEST_PASS                                                     \
        fence;                                                          \
        li      TESTNUM, 1;                                             \
        li      t0, EXIT_ADDR;                                          \
        sw      TESTNUM, 0(t0);                                         \
1:      j       1b;

#define RVTEST_FAIL                                                     \
        fence;                                                          \
1:      beqz    TESTNUM, 1b;                                            \
        sll     TESTNUM, TESTNUM, 1;                                    \
        or      TESTNUM, TESTNUM, 1;                                    \
        li      t0, EXIT_ADDR;                                          \
        sw      TESTNUM, 0(t0);                                         \
2:      j       2b;

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN                                               \
        EXTRA_DATA                                                      \
        .data;                                                          \
        .align 4;

#define RVTEST_DATA_END

#endif
