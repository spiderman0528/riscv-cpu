// sort.c - insertion sort of 300 random integers (data-dependent branches)
#include "bench.h"

#define N 300
static int32_t a[N];

int main(void) {
  uint32_t sum_before = 0, sum_after = 0;
  for (int i = 0; i < N; i++) { a[i] = (int32_t)rng(); sum_before += (uint32_t)a[i]; }

  perf_t t0 = perf_now();
  for (int i = 1; i < N; i++) {
    int32_t key = a[i];
    int j = i - 1;
    while (j >= 0 && a[j] > key) { a[j + 1] = a[j]; j--; }
    a[j + 1] = key;
  }
  perf_t t1 = perf_now();

  for (int i = 0; i < N; i++) sum_after += (uint32_t)a[i];
  for (int i = 1; i < N; i++) if (a[i - 1] > a[i]) { print("sort: NOT SORTED\n"); return 1; }
  if (sum_before != sum_after) { print("sort: checksum changed\n"); return 2; }

  perf_report("sort", t0, t1);
  print("sort: OK\n");
  return 0;
}
