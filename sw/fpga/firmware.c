// firmware.c - board demo: greets over the UART, mirrors the switches on the
// LEDs, and reports a CoreMark-style mini benchmark using the cycle counter.
#include "runtime.h"

static uint32_t work(uint32_t seed) {
  uint32_t x = seed;
  for (int i = 0; i < 1000; i++) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; }
  return x;
}

int main(void) {
  print("\r\nriscv-cpu: 5-stage RV32I pipeline on DE10-Lite\r\n");

  uint32_t c0 = rdcycle(), i0 = rdinstret();
  uint32_t r = work(1);
  uint32_t c1 = rdcycle(), i1 = rdinstret();
  print("xorshift x1000: "); print_hex(r);
  print("  cycles "); print_udec(c1 - c0);
  print("  instructions "); print_udec(i1 - i0); print("\r\n");

  uint32_t last = 0xFFFFFFFFu;
  for (;;) {
    uint32_t sw = SWITCHES;
    LEDS = sw;
    if (sw != last) { print("switches = "); print_hex(sw); print("\r\n"); last = sw; }
  }
}
