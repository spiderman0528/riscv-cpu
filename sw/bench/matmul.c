// matmul.c - 12x12 integer matrix multiply (RV32I has no MUL: software multiply)
#include "bench.h"

#define N 12
static int32_t A[N][N], B[N][N], C[N][N];

int main(void) {
  for (int i = 0; i < N; i++)
    for (int j = 0; j < N; j++) {
      A[i][j] = (int32_t)(rng() % 201) - 100;
      B[i][j] = (int32_t)(rng() % 201) - 100;
    }

  perf_t t0 = perf_now();
  for (int i = 0; i < N; i++)
    for (int j = 0; j < N; j++) {
      int32_t s = 0;
      for (int k = 0; k < N; k++) s += A[i][k] * B[k][j];
      C[i][j] = s;
    }
  perf_t t1 = perf_now();

  // Check with a different method: (row sums of C) == A * (row sums of B)
  for (int i = 0; i < N; i++) {
    int32_t lhs = 0, rhs = 0;
    for (int j = 0; j < N; j++) lhs += C[i][j];
    for (int k = 0; k < N; k++) {
      int32_t bsum = 0;
      for (int j = 0; j < N; j++) bsum += B[k][j];
      rhs += A[i][k] * bsum;
    }
    if (lhs != rhs) { print("matmul: MISMATCH\n"); return 1; }
  }

  perf_report("matmul", t0, t1);
  print("matmul: OK\n");
  return 0;
}
