# crt0.S - C runtime start-up: set the stack, clear .bss, call main, exit.
    .section .text.init
    .globl _start
_start:
    la    sp, __stack_top
    la    t0, __bss_start
    la    t1, __bss_end
1:  bgeu  t0, t1, 2f
    sw    zero, 0(t0)
    addi  t0, t0, 4
    j     1b
2:  call  main
    call  exit          # exit(main's return value) - never returns
3:  j     3b
