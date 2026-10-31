// bench.h - measure a benchmark kernel with the CPU's hardware counters.
#pragma once
#include "runtime.h"

typedef struct { uint32_t cyc, ins, mis, stl; } perf_t;

static inline perf_t perf_now(void) {
  perf_t p;
  p.cyc = rdcycle(); p.ins = rdinstret(); p.mis = rdmispredict(); p.stl = rdstalls();
  return p;
}

// Prints one machine-readable line that scripts/bench.py parses.
static inline void perf_report(const char *name, perf_t a, perf_t b) {
  print("STATS name="); print(name);
  print(" cycles=");      print_udec(b.cyc - a.cyc);
  print(" instret=");     print_udec(b.ins - a.ins);
  print(" mispredicts="); print_udec(b.mis - a.mis);
  print(" stalls=");      print_udec(b.stl - a.stl);
  print("\n");
}

// Tiny deterministic PRNG (xorshift32) so every run uses the same inputs.
static uint32_t rng_state = 0x12345678u;
static inline uint32_t rng(void) {
  uint32_t x = rng_state;
  x ^= x << 13; x ^= x >> 17; x ^= x << 5;
  return rng_state = x;
}
