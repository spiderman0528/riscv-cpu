// iss.h - RV32I instruction-set simulator used as the golden reference model.
//
// It executes one instruction at a time with no notion of pipelines or timing,
// so it is easy to check by reading the ISA spec. The co-simulation testbench
// steps it once for every instruction the RTL retires and compares results.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

struct Commit {
  uint32_t pc = 0;
  uint32_t inst = 0;
  bool     reg_we = false;
  uint32_t rd = 0;
  uint32_t wdata = 0;
  bool     mem_we = false;
  uint32_t mem_addr = 0;
  uint32_t mem_wdata = 0;   // store data, masked to the access size
  uint32_t mem_size = 0;    // 0 byte, 1 half, 2 word
  bool     is_csr = false;  // CSR reads are timing dependent; not compared
  bool     illegal = false;
  bool     misaligned = false;
};

class Iss {
 public:
  static constexpr uint32_t kRamBytes  = 64 * 1024;
  static constexpr uint32_t kMmioBase  = 0x10000000;
  static constexpr uint32_t kUartTx    = 0x10000000;
  static constexpr uint32_t kUartSt    = 0x10000004;
  static constexpr uint32_t kLeds      = 0x10000008;
  static constexpr uint32_t kSwitches  = 0x1000000C;
  static constexpr uint32_t kExit      = 0x10000010;

  Iss();
  bool load_hex(const std::string& path);   // $readmemh-style, one word per line
  Commit step();

  uint32_t reg(int i) const { return x_[i]; }
  void set_reg(int i, uint32_t v) { if (i) x_[i] = v; }
  uint32_t pc() const { return pc_; }

 private:
  uint32_t load(uint32_t addr, int size, bool is_signed);
  void store(uint32_t addr, int size, uint32_t value);

  uint32_t x_[32];
  uint32_t pc_ = 0;
  uint32_t leds_ = 0;
  std::vector<uint8_t> mem_;
};
