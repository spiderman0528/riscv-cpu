// crc32.c - bitwise CRC-32 (IEEE 802.3) over a 2 KiB buffer (shift/xor heavy)
#include "bench.h"

#define LEN 2048
#define CRC_EXPECTED 0x54e6be43u   /* zlib.crc32 of the same buffer */
static uint8_t buf[LEN];

static uint32_t crc32(const uint8_t *p, int n) {
  uint32_t crc = 0xFFFFFFFFu;
  for (int i = 0; i < n; i++) {
    crc ^= p[i];
    for (int b = 0; b < 8; b++) crc = (crc >> 1) ^ (0xEDB88320u & -(crc & 1u));
  }
  return ~crc;
}

int main(void) {
  for (int i = 0; i < LEN; i++) buf[i] = (uint8_t)(i * 7 + (i >> 3));

  perf_t t0 = perf_now();
  uint32_t crc = crc32(buf, LEN);
  perf_t t1 = perf_now();

  // Reference value computed on the host with Python's zlib.crc32
  if (crc != CRC_EXPECTED) { print("crc32: got "); print_hex(crc); print("\n"); return 1; }

  perf_report("crc32", t0, t1);
  print("crc32: OK "); print_hex(crc); print("\n");
  return 0;
}
