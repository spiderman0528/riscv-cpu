// fib.c - naive recursive Fibonacci (call/return heavy: JAL + JALR)
#include "bench.h"

__attribute__((noinline)) static uint32_t fib(uint32_t n) {
  return n < 2 ? n : fib(n - 1) + fib(n - 2);
}

int main(void) {
  perf_t t0 = perf_now();
  uint32_t f = fib(18);
  perf_t t1 = perf_now();

  if (f != 2584) { print("fib: wrong result "); print_udec(f); print("\n"); return 1; }
  perf_report("fib", t0, t1);
  print("fib: OK\n");
  return 0;
}
