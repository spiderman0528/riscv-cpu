// runtime.h - tiny bare-metal runtime for the riscv-cpu SoC
#pragma once
#include <stdint.h>
#include <stddef.h>

#define MMIO32(addr) (*(volatile uint32_t *)(addr))
#define UART_TX   MMIO32(0x10000000u)
#define UART_ST   MMIO32(0x10000004u)
#define LEDS      MMIO32(0x10000008u)
#define SWITCHES  MMIO32(0x1000000Cu)
#define SIM_EXIT  MMIO32(0x10000010u)

void putchar_(char c);
void print(const char *s);
void print_dec(int32_t v);
void print_udec(uint32_t v);
void print_hex(uint32_t v);
void exit(int code) __attribute__((noreturn));

void *memset(void *dst, int c, size_t n);
void *memcpy(void *dst, const void *src, size_t n);

// Performance counters (Zicntr CSRs + two implementation-specific HPMs)
static inline uint32_t rdcycle(void)    { uint32_t v; __asm__ volatile("csrr %0, cycle"   : "=r"(v)); return v; }
static inline uint32_t rdinstret(void)  { uint32_t v; __asm__ volatile("csrr %0, instret" : "=r"(v)); return v; }
static inline uint32_t rdmispredict(void){ uint32_t v; __asm__ volatile("csrr %0, hpmcounter3" : "=r"(v)); return v; }
static inline uint32_t rdstalls(void)   { uint32_t v; __asm__ volatile("csrr %0, hpmcounter4" : "=r"(v)); return v; }
