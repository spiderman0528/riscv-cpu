// iss.cpp - RV32I golden reference model (see iss.h)
#include "iss.h"

#include <cstdio>
#include <fstream>
#include <sstream>

namespace {
inline int32_t sext(uint32_t v, int bits) {
  uint32_t m = 1u << (bits - 1);
  v &= (bits == 32) ? 0xFFFFFFFFu : ((1u << bits) - 1);
  return static_cast<int32_t>((v ^ m) - m);
}
inline uint32_t bits(uint32_t v, int hi, int lo) {
  return (v >> lo) & ((hi - lo == 31) ? 0xFFFFFFFFu : ((1u << (hi - lo + 1)) - 1));
}
inline bool is_mmio(uint32_t a) { return (a >> 28) == 0x1; }
}  // namespace

Iss::Iss() : mem_(kRamBytes, 0) {
  for (auto& r : x_) r = 0;
}

bool Iss::load_hex(const std::string& path) {
  std::ifstream f(path);
  if (!f) return false;
  std::string tok;
  uint32_t word_idx = 0;
  while (f >> tok) {
    if (tok.empty()) continue;
    if (tok[0] == '@') { word_idx = std::stoul(tok.substr(1), nullptr, 16); continue; }
    if (tok.rfind("//", 0) == 0) { std::getline(f, tok); continue; }
    uint32_t w = std::stoul(tok, nullptr, 16);
    uint32_t a = (word_idx * 4) % kRamBytes;
    for (int b = 0; b < 4; b++) mem_[a + b] = (w >> (8 * b)) & 0xFF;
    word_idx++;
  }
  return true;
}

// Loads/stores mirror the RTL memory system: RAM is 64 KiB and aliases
// (only address bits [15:2] select a word); MMIO decodes address bits [7:0].
uint32_t Iss::load(uint32_t addr, int size, bool is_signed) {
  uint32_t word = 0;
  if (is_mmio(addr)) {
    switch (addr & 0xFC) {
      case kUartSt & 0xFF:   word = 0; break;        // fast-sim UART: never busy
      case kLeds & 0xFF:     word = leds_; break;
      case kSwitches & 0xFF: word = 0; break;
      default:               word = 0; break;
    }
  } else {
    uint32_t a = addr & (kRamBytes - 1) & ~3u;
    word = mem_[a] | (mem_[a + 1] << 8) | (mem_[a + 2] << 16) | (uint32_t(mem_[a + 3]) << 24);
  }
  if (size == 2) return word;
  uint32_t sh = word >> (8 * (addr & 3));
  int nbits = (size == 0) ? 8 : 16;
  return is_signed ? static_cast<uint32_t>(sext(sh, nbits)) : (sh & ((1u << nbits) - 1));
}

void Iss::store(uint32_t addr, int size, uint32_t value) {
  if (is_mmio(addr)) {
    if ((addr & 0xFF) == (kLeds & 0xFF)) {
      uint32_t lane = (size == 0) ? (value & 0xFF) * 0x01010101u
                    : (size == 1) ? (value & 0xFFFF) * 0x00010001u : value;
      leds_ = lane & 0x3FF;
    }
    return;  // UART / exit are observed by the testbench
  }
  uint32_t a = addr & (kRamBytes - 1);
  int n = 1 << size;
  for (int i = 0; i < n; i++) mem_[(a + i) & (kRamBytes - 1)] = (value >> (8 * i)) & 0xFF;
}

Commit Iss::step() {
  Commit c;
  uint32_t ia = pc_ & (kRamBytes - 1);
  uint32_t inst = mem_[ia] | (mem_[ia + 1] << 8) | (mem_[ia + 2] << 16) | (uint32_t(mem_[ia + 3]) << 24);
  c.pc = pc_;
  c.inst = inst;

  uint32_t opcode = bits(inst, 6, 0);
  uint32_t rd     = bits(inst, 11, 7);
  uint32_t funct3 = bits(inst, 14, 12);
  uint32_t rs1    = bits(inst, 19, 15);
  uint32_t rs2    = bits(inst, 24, 20);
  uint32_t funct7 = bits(inst, 31, 25);

  int32_t imm_i = sext(inst >> 20, 12);
  int32_t imm_s = sext((bits(inst, 31, 25) << 5) | bits(inst, 11, 7), 12);
  int32_t imm_b = sext((bits(inst, 31, 31) << 12) | (bits(inst, 7, 7) << 11) |
                       (bits(inst, 30, 25) << 5) | (bits(inst, 11, 8) << 1), 13);
  uint32_t imm_u = inst & 0xFFFFF000u;
  int32_t imm_j = sext((bits(inst, 31, 31) << 20) | (bits(inst, 19, 12) << 12) |
                       (bits(inst, 20, 20) << 11) | (bits(inst, 30, 21) << 1), 21);

  uint32_t a = x_[rs1], b = x_[rs2];
  uint32_t next = pc_ + 4;
  uint32_t result = 0;
  bool wr = false;

  auto alu = [&](uint32_t f3, uint32_t lhs, uint32_t rhs, bool alt) -> uint32_t {
    switch (f3) {
      case 0: return alt ? lhs - rhs : lhs + rhs;
      case 1: return lhs << (rhs & 31);
      case 2: return static_cast<int32_t>(lhs) < static_cast<int32_t>(rhs);
      case 3: return lhs < rhs;
      case 4: return lhs ^ rhs;
      case 5: return alt ? static_cast<uint32_t>(static_cast<int32_t>(lhs) >> (rhs & 31))
                         : lhs >> (rhs & 31);
      case 6: return lhs | rhs;
      default: return lhs & rhs;
    }
  };

  switch (opcode) {
    case 0x37: result = imm_u; wr = true; break;                              // LUI
    case 0x17: result = pc_ + imm_u; wr = true; break;                        // AUIPC
    case 0x6F: result = pc_ + 4; wr = true; next = pc_ + imm_j; break;        // JAL
    case 0x67:                                                                // JALR
      if (funct3 != 0) { c.illegal = true; break; }
      result = pc_ + 4; wr = true; next = (a + imm_i) & ~1u; break;
    case 0x63: {                                                              // BRANCH
      bool t;
      switch (funct3) {
        case 0: t = a == b; break;
        case 1: t = a != b; break;
        case 4: t = static_cast<int32_t>(a) < static_cast<int32_t>(b); break;
        case 5: t = static_cast<int32_t>(a) >= static_cast<int32_t>(b); break;
        case 6: t = a < b; break;
        case 7: t = a >= b; break;
        default: c.illegal = true; t = false;
      }
      if (t) next = pc_ + imm_b;
      break;
    }
    case 0x03: {                                                              // LOAD
      uint32_t addr = a + imm_i;
      int size = funct3 & 3;
      if (funct3 == 3 || funct3 >= 6) { c.illegal = true; break; }
      if ((size == 1 && (addr & 1)) || (size == 2 && (addr & 3))) c.misaligned = true;
      result = load(addr, size, !(funct3 & 4));
      wr = true;
      break;
    }
    case 0x23: {                                                              // STORE
      uint32_t addr = a + imm_s;
      int size = funct3;
      if (funct3 > 2) { c.illegal = true; break; }
      if ((size == 1 && (addr & 1)) || (size == 2 && (addr & 3))) c.misaligned = true;
      uint32_t mask = (size == 2) ? 0xFFFFFFFFu : ((1u << (8 << size)) - 1);
      store(addr, size, b);
      c.mem_we = true; c.mem_addr = addr; c.mem_wdata = b & mask; c.mem_size = size;
      break;
    }
    case 0x13: {                                                              // OP-IMM
      bool alt = (funct3 == 5) && (funct7 & 0x20);
      if (funct3 == 1 && funct7 != 0) c.illegal = true;
      if (funct3 == 5 && funct7 != 0 && funct7 != 0x20) c.illegal = true;
      uint32_t rhs = (funct3 == 1 || funct3 == 5) ? rs2 : static_cast<uint32_t>(imm_i);
      result = alu(funct3, a, rhs, alt); wr = true; break;
    }
    case 0x33: {                                                              // OP
      if (!(funct7 == 0 || (funct7 == 0x20 && (funct3 == 0 || funct3 == 5)))) c.illegal = true;
      result = alu(funct3, a, b, funct7 & 0x20); wr = true; break;
    }
    case 0x0F:                                                                // FENCE(.I)
      if (funct3 > 1) c.illegal = true;
      break;
    case 0x73:                                                                // SYSTEM
      if (funct3 == 0 || funct3 == 4) { c.illegal = true; break; }
      c.is_csr = true; wr = true; result = 0;   // value supplied by the RTL
      break;
    default:
      c.illegal = true;
  }

  if (c.illegal) wr = false;
  if (wr && rd != 0) {
    x_[rd] = result;
    c.reg_we = true; c.rd = rd; c.wdata = result;
  }
  pc_ = next;
  return c;
}
