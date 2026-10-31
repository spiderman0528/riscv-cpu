// tb_main.cpp - Verilator testbench with lock-step co-simulation.
//
// Every instruction the RTL retires is replayed on the ISS (golden model) and
// the two are compared: PC, instruction, destination register + value, and
// store address/data/size. The first mismatch stops the run with a report.
//
// Usage: Vsoc +hex=<program.hex> [--no-cosim] [--trace out.vcd]
//             [--max-cycles N] [--stats out.json] [--quiet]
//
// Exit protocol: the program stores (code << 1) | 1 to 0x10000010.
// code 0 means pass (this is the riscv-tests "tohost" convention).
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>

#include "Vsoc.h"
#include "iss.h"
#include "verilated.h"
#if VM_TRACE
#include "verilated_vcd_c.h"
#endif

namespace {

const char* reg_name(int r) {
  static const char* n[32] = {"zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
                              "s0",   "s1", "a0", "a1", "a2", "a3", "a4", "a5",
                              "a6",   "a7", "s2", "s3", "s4", "s5", "s6", "s7",
                              "s8",   "s9", "s10", "s11", "t3", "t4", "t5", "t6"};
  return n[r & 31];
}

struct Options {
  std::string hex;
  std::string trace;
  std::string stats;
  bool cosim = true;
  bool quiet = false;
  uint64_t max_cycles = 50'000'000;
};

Options parse(int argc, char** argv) {
  Options o;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    if (a.rfind("+hex=", 0) == 0) o.hex = a.substr(5);
    else if (a == "--no-cosim") o.cosim = false;
    else if (a == "--quiet") o.quiet = true;
    else if (a == "--trace" && i + 1 < argc) o.trace = argv[++i];
    else if (a == "--stats" && i + 1 < argc) o.stats = argv[++i];
    else if (a == "--max-cycles" && i + 1 < argc) o.max_cycles = std::strtoull(argv[++i], nullptr, 0);
  }
  return o;
}

}  // namespace

int main(int argc, char** argv) {
  Options opt = parse(argc, argv);
  if (opt.hex.empty()) {
    std::fprintf(stderr, "usage: %s +hex=<program.hex> [--no-cosim] [--trace f.vcd] "
                         "[--max-cycles N] [--stats f.json] [--quiet]\n", argv[0]);
    return 2;
  }

  auto ctx = std::make_unique<VerilatedContext>();
  ctx->commandArgs(argc, argv);
  auto top = std::make_unique<Vsoc>(ctx.get());

#if VM_TRACE
  std::unique_ptr<VerilatedVcdC> vcd;
  if (!opt.trace.empty()) {
    ctx->traceEverOn(true);
    vcd = std::make_unique<VerilatedVcdC>();
    top->trace(vcd.get(), 99);
    vcd->open(opt.trace.c_str());
  }
#endif

  Iss iss;
  if (opt.cosim && !iss.load_hex(opt.hex)) {
    std::fprintf(stderr, "cannot read %s\n", opt.hex.c_str());
    return 2;
  }

  uint64_t time = 0;
  auto tick = [&]() {
    top->clk = 0; top->eval();
#if VM_TRACE
    if (vcd) vcd->dump(time);
#endif
    time++;
    top->clk = 1; top->eval();
#if VM_TRACE
    if (vcd) vcd->dump(time);
#endif
    time++;
  };

  top->switches = 0;
  top->rst = 1;
  for (int i = 0; i < 5; i++) tick();
  top->rst = 0;

  int exit_code = -1;
  std::string fail_reason;
  uint64_t cycles = 0, retired = 0;
  uint64_t snap_cycle = 0, snap_instret = 0;
  uint32_t snap_mispredict = 0, snap_stall = 0;

  while (exit_code < 0 && fail_reason.empty()) {
    tick();
    cycles++;
    if (cycles > opt.max_cycles) { fail_reason = "timeout (no exit after max cycles)"; break; }
    if (!top->retire_valid) continue;
    retired++;

    const uint32_t pc = top->retire_pc, inst = top->retire_inst;

    if (top->retire_illegal) {
      char b[128];
      std::snprintf(b, sizeof b, "illegal instruction 0x%08x at pc 0x%08x", inst, pc);
      fail_reason = b;
      break;
    }

    // ---------------- co-simulation check ----------------
    if (opt.cosim) {
      Commit c = iss.step();
      char b[512] = {0};
      if (c.misaligned) {
        std::snprintf(b, sizeof b, "misaligned access at pc 0x%08x (not supported)", c.pc);
      } else if (c.pc != pc || c.inst != inst) {
        std::snprintf(b, sizeof b, "PC/instruction mismatch: RTL pc=0x%08x inst=0x%08x, "
                      "ISS pc=0x%08x inst=0x%08x", pc, inst, c.pc, c.inst);
      } else if (c.is_csr) {
        // counter values depend on timing: take the RTL's value
        if (top->retire_reg_we) iss.set_reg(top->retire_rd, top->retire_wdata);
      } else if (c.reg_we != bool(top->retire_reg_we) ||
                 (c.reg_we && (c.rd != top->retire_rd || c.wdata != top->retire_wdata))) {
        std::snprintf(b, sizeof b, "register write mismatch at pc 0x%08x (inst 0x%08x): "
                      "RTL %s %s=0x%08x, ISS %s %s=0x%08x", pc, inst,
                      top->retire_reg_we ? "writes" : "no-write", reg_name(top->retire_rd),
                      top->retire_wdata, c.reg_we ? "writes" : "no-write", reg_name(c.rd), c.wdata);
      } else if (c.mem_we != bool(top->retire_mem_we)) {
        std::snprintf(b, sizeof b, "store mismatch at pc 0x%08x: RTL %s, ISS %s", pc,
                      top->retire_mem_we ? "stores" : "no store", c.mem_we ? "stores" : "no store");
      } else if (c.mem_we) {
        uint32_t sz = top->retire_mem_size;
        uint32_t mask = sz == 2 ? 0xFFFFFFFFu : ((1u << (8 << sz)) - 1);
        uint32_t rtl_data = top->retire_mem_wdata & mask;
        if (c.mem_addr != top->retire_mem_addr || c.mem_size != sz || c.mem_wdata != rtl_data)
          std::snprintf(b, sizeof b, "store mismatch at pc 0x%08x: RTL [0x%08x] size %u = 0x%08x, "
                        "ISS [0x%08x] size %u = 0x%08x", pc, top->retire_mem_addr, sz, rtl_data,
                        c.mem_addr, c.mem_size, c.mem_wdata);
      }
      if (b[0]) { fail_reason = b; break; }
    }

    // ---------------- MMIO side effects ----------------
    if (top->retire_mem_we) {
      uint32_t addr = top->retire_mem_addr;
      if (addr == Iss::kUartTx) {
        std::putchar(top->retire_mem_wdata & 0xFF);
        std::fflush(stdout);
      } else if (addr == Iss::kExit) {
        uint32_t v = top->retire_mem_wdata;
        exit_code = (v == 1) ? 0 : static_cast<int>(v >> 1);
        if (exit_code == 0 && v != 1) exit_code = 1;
        // snapshot counters at the moment the program finished
        snap_cycle = top->perf_cycle;  snap_instret = top->perf_instret;
        snap_mispredict = top->perf_mispredict;  snap_stall = top->perf_stall;
      }
    }
  }

  // Let the last instructions drain so the waveform is complete.
  for (int i = 0; i < 4; i++) tick();

#if VM_TRACE
  if (vcd) vcd->close();
#endif

  if (exit_code < 0) {
    snap_cycle = top->perf_cycle;  snap_instret = top->perf_instret;
    snap_mispredict = top->perf_mispredict;  snap_stall = top->perf_stall;
  }
  const uint64_t cyc  = snap_cycle;
  const uint64_t inst = snap_instret;
  const double cpi = inst ? double(cyc) / double(inst) : 0.0;

  if (!opt.stats.empty()) {
    if (FILE* f = std::fopen(opt.stats.c_str(), "w")) {
      std::fprintf(f, "{\"cycles\": %llu, \"instret\": %llu, \"cpi\": %.4f, "
                      "\"mispredicts\": %u, \"stall_cycles\": %u, \"exit_code\": %d}\n",
                   (unsigned long long)cyc, (unsigned long long)inst, cpi,
                   snap_mispredict, snap_stall, exit_code);
      std::fclose(f);
    }
  }

  if (!fail_reason.empty()) {
    std::fprintf(stderr, "\n[FAIL] %s (after %llu cycles, %llu instructions)\n", fail_reason.c_str(),
                 (unsigned long long)cycles, (unsigned long long)retired);
    return 1;
  }
  if (!opt.quiet) {
    std::fprintf(stderr, "\n[%s] exit code %d | cycles %llu | instret %llu | CPI %.3f | "
                         "mispredicts %u | stall cycles %u%s\n",
                 exit_code == 0 ? "PASS" : "FAIL", exit_code, (unsigned long long)cyc,
                 (unsigned long long)inst, cpi, snap_mispredict, snap_stall,
                 opt.cosim ? " | cosim OK" : "");
  }
  top->final();
  return exit_code == 0 ? 0 : 1;
}
