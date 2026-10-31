### CPI by configuration (kernel only, lower is better)

| Benchmark | No forwarding, static prediction | Forwarding, static prediction | No forwarding, BTB + 2-bit BHT | Forwarding + BTB + 2-bit BHT | Speed-up |
| --- | ---: | ---: | ---: | ---: | ---: |
| sort | 1.839 | 1.490 | 1.517 | 1.168 | 1.57x |
| matmul | 2.229 | 1.280 | 1.979 | 1.029 | 2.17x |
| crc32 | 2.359 | 1.077 | 2.308 | 1.026 | 2.30x |
| fib | 1.465 | 1.244 | 1.310 | 1.088 | 1.35x |
| sieve | 2.154 | 1.439 | 1.795 | 1.080 | 2.00x |

### Final configuration detail

| Benchmark | Instructions | Cycles | CPI | Mispredicts | MPKI | Load-use stall cycles |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| sort | 132,817 | 155,114 | 1.168 | 307 | 2.3 | 21,683 |
| matmul | 247,603 | 254,775 | 1.029 | 3,532 | 14.3 | 108 |
| crc32 | 79,894 | 81,945 | 1.026 | 2 | 0.0 | 2,048 |
| fib | 94,568 | 102,935 | 1.088 | 4,184 | 44.2 | 0 |
| sieve | 138,618 | 149,673 | 1.080 | 1,433 | 10.3 | 8,190 |
