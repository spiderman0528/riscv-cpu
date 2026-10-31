// sieve.c - Sieve of Eratosthenes up to 8192 (byte loads/stores, loops)
#include "bench.h"

#define LIMIT 8192
static uint8_t composite[LIMIT];

int main(void) {
  perf_t t0 = perf_now();
  uint32_t count = 0;
  for (uint32_t i = 2; i < LIMIT; i++) {
    if (composite[i]) continue;
    count++;
    for (uint32_t j = i + i; j < LIMIT; j += i) composite[j] = 1;
  }
  perf_t t1 = perf_now();

  if (count != 1028) { print("sieve: wrong count "); print_udec(count); print("\n"); return 1; }
  perf_report("sieve", t0, t1);
  print("sieve: OK\n");
  return 0;
}
