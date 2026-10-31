// runtime.c - console output, exit, and the integer helpers that the
// compiler calls on RV32I (there is no hardware multiply/divide).
#include "runtime.h"

void putchar_(char c) {
  while (UART_ST & 1) { }   // wait while the transmitter is busy
  UART_TX = (uint8_t)c;
}

void print(const char *s) { while (*s) putchar_(*s++); }

void print_udec(uint32_t v) {
  char buf[11];
  int i = 0;
  do { buf[i++] = (char)('0' + v % 10u); v /= 10u; } while (v);
  while (i) putchar_(buf[--i]);
}

void print_dec(int32_t v) {
  if (v < 0) { putchar_('-'); print_udec((uint32_t)(-(v + 1)) + 1u); }
  else print_udec((uint32_t)v);
}

void print_hex(uint32_t v) {
  print("0x");
  for (int i = 28; i >= 0; i -= 4) putchar_("0123456789abcdef"[(v >> i) & 0xF]);
}

void exit(int code) {
  SIM_EXIT = ((uint32_t)code << 1) | 1u;
  for (;;) { }
}

void *memset(void *dst, int c, size_t n) {
  uint8_t *d = dst;
  while (n--) *d++ = (uint8_t)c;
  return dst;
}

void *memcpy(void *dst, const void *src, size_t n) {
  uint8_t *d = dst;
  const uint8_t *s = src;
  while (n--) *d++ = *s++;
  return dst;
}

// ---- libgcc/compiler-rt integer helpers (shift-and-add / restoring division)
uint32_t __mulsi3(uint32_t a, uint32_t b) {
  uint32_t r = 0;
  while (b) { if (b & 1u) r += a; a <<= 1; b >>= 1; }
  return r;
}

static uint32_t udivmod(uint32_t n, uint32_t d, uint32_t *rem) {
  if (d == 0) { *rem = n; return 0xFFFFFFFFu; }   // RISC-V M semantics
  uint32_t q = 0, r = 0;
  for (int i = 31; i >= 0; i--) {
    r = (r << 1) | ((n >> i) & 1u);
    if (r >= d) { r -= d; q |= 1u << i; }
  }
  *rem = r;
  return q;
}

uint32_t __udivsi3(uint32_t n, uint32_t d) { uint32_t r; return udivmod(n, d, &r); }
uint32_t __umodsi3(uint32_t n, uint32_t d) { uint32_t r; udivmod(n, d, &r); return r; }

int32_t __divsi3(int32_t n, int32_t d) {
  int neg = (n < 0) ^ (d < 0);
  uint32_t q = __udivsi3(n < 0 ? -(uint32_t)n : (uint32_t)n, d < 0 ? -(uint32_t)d : (uint32_t)d);
  return neg ? -(int32_t)q : (int32_t)q;
}

int32_t __modsi3(int32_t n, int32_t d) {
  uint32_t r = __umodsi3(n < 0 ? -(uint32_t)n : (uint32_t)n, d < 0 ? -(uint32_t)d : (uint32_t)d);
  return n < 0 ? -(int32_t)r : (int32_t)r;
}
