// riscv_pkg.sv - shared constants for the RV32I pipelined core
package riscv_pkg;

  // ---------------------------------------------------------------------------
  // Major opcodes (inst[6:0])
  // ---------------------------------------------------------------------------
  localparam logic [6:0] OP_LUI    = 7'b0110111;
  localparam logic [6:0] OP_AUIPC  = 7'b0010111;
  localparam logic [6:0] OP_JAL    = 7'b1101111;
  localparam logic [6:0] OP_JALR   = 7'b1100111;
  localparam logic [6:0] OP_BRANCH = 7'b1100011;
  localparam logic [6:0] OP_LOAD   = 7'b0000011;
  localparam logic [6:0] OP_STORE  = 7'b0100011;
  localparam logic [6:0] OP_IMM    = 7'b0010011;
  localparam logic [6:0] OP_REG    = 7'b0110011;
  localparam logic [6:0] OP_FENCE  = 7'b0001111;
  localparam logic [6:0] OP_SYSTEM = 7'b1110011;

  // ---------------------------------------------------------------------------
  // ALU operations
  // ---------------------------------------------------------------------------
  localparam logic [3:0] ALU_ADD  = 4'd0;
  localparam logic [3:0] ALU_SUB  = 4'd1;
  localparam logic [3:0] ALU_SLL  = 4'd2;
  localparam logic [3:0] ALU_SLT  = 4'd3;
  localparam logic [3:0] ALU_SLTU = 4'd4;
  localparam logic [3:0] ALU_XOR  = 4'd5;
  localparam logic [3:0] ALU_SRL  = 4'd6;
  localparam logic [3:0] ALU_SRA  = 4'd7;
  localparam logic [3:0] ALU_OR   = 4'd8;
  localparam logic [3:0] ALU_AND  = 4'd9;
  localparam logic [3:0] ALU_PASS_B = 4'd10;  // used by LUI

  // ALU operand A select
  localparam logic [1:0] A_RS1  = 2'd0;
  localparam logic [1:0] A_PC   = 2'd1;
  localparam logic [1:0] A_ZERO = 2'd2;

  // Write-back source select
  localparam logic [1:0] WB_ALU = 2'd0;
  localparam logic [1:0] WB_MEM = 2'd1;
  localparam logic [1:0] WB_PC4 = 2'd2;
  localparam logic [1:0] WB_CSR = 2'd3;

  // ---------------------------------------------------------------------------
  // Performance-counter CSR addresses (read-only, Zicntr + two custom HPM)
  // ---------------------------------------------------------------------------
  localparam logic [11:0] CSR_CYCLE    = 12'hC00;
  localparam logic [11:0] CSR_INSTRET  = 12'hC02;
  localparam logic [11:0] CSR_HPM3     = 12'hC03;  // branch/jump mispredicts
  localparam logic [11:0] CSR_HPM4     = 12'hC04;  // data-hazard stall cycles
  localparam logic [11:0] CSR_CYCLEH   = 12'hC80;
  localparam logic [11:0] CSR_INSTRETH = 12'hC82;

  // ---------------------------------------------------------------------------
  // Memory map
  // ---------------------------------------------------------------------------
  localparam logic [31:0] RESET_PC      = 32'h0000_0000;
  localparam logic [31:0] MMIO_BASE     = 32'h1000_0000;
  localparam logic [31:0] MMIO_UART_TX  = 32'h1000_0000;  // W: send byte
  localparam logic [31:0] MMIO_UART_ST  = 32'h1000_0004;  // R: bit0 = tx busy
  localparam logic [31:0] MMIO_LEDS     = 32'h1000_0008;  // R/W: LEDs
  localparam logic [31:0] MMIO_SWITCHES = 32'h1000_000C;  // R: switches
  localparam logic [31:0] MMIO_EXIT     = 32'h1000_0010;  // W: end simulation

endpackage
