| Injected bug | riscv-tests failing | random programs failing | Caught |
| --- | ---: | ---: | :---: |
| No load-use stall | 6 / 41 | 40 / 40 | yes |
| Forwarding priority reversed (MEM/WB before EX/MEM) | 41 / 41 | 40 / 40 | yes |
| Load-use check ignores rs2 | 1 / 41 | 23 / 40 | yes |
| No EX/MEM forwarding path | 41 / 41 | 40 / 40 | yes |
| Register file write-through bypass removed | 33 / 41 | 40 / 40 | yes |
| IF/ID not flushed on a misprediction | 40 / 41 | 40 / 40 | yes |
| ID/EX not flushed on a misprediction | 40 / 41 | 40 / 40 | yes |
| PC advances during a stall | 6 / 41 | 40 / 40 | yes |
| Misprediction check ignores the predicted target | 0 / 41 | 40 / 40 | yes |
| BLT uses an unsigned comparison | 1 / 41 | 23 / 40 | yes |
| JALR does not clear bit 0 of the target | 0 / 41 | 40 / 40 | yes |
| Halfword store writes the wrong byte lanes | 4 / 41 | 39 / 40 | yes |
| LH zero-extends instead of sign-extending | 6 / 41 | 40 / 40 | yes |
| SRA behaves like SRL | 3 / 41 | 39 / 40 | yes |

**Mutation score: 14/14**
