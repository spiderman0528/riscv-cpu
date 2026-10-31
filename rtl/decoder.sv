// decoder.sv - main control decoder for RV32I (+ Zicntr reads, FENCE.I)
module decoder
  import riscv_pkg::*;
(
  input  logic [31:0] inst,

  output logic        reg_we,      // writes rd
  output logic        uses_rs1,    // reads rs1 (for hazard detection)
  output logic        uses_rs2,    // reads rs2 (for hazard detection)
  output logic [3:0]  alu_op,
  output logic [1:0]  a_sel,       // A_RS1 / A_PC / A_ZERO
  output logic        b_imm,       // 1: operand B is the immediate
  output logic [1:0]  wb_sel,      // WB_ALU / WB_MEM / WB_PC4 / WB_CSR
  output logic        mem_read,
  output logic        mem_write,
  output logic        is_branch,
  output logic        is_jal,
  output logic        is_jalr,
  output logic        is_fence_i,
  output logic        illegal
);

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic [4:0] rd;

  assign opcode = inst[6:0];
  assign funct3 = inst[14:12];
  assign funct7 = inst[31:25];
  assign rd     = inst[11:7];

  // funct3 -> ALU op for OP and OP-IMM
  function automatic logic [3:0] arith_op(input logic [2:0] f3, input logic alt);
    case (f3)
      3'b000:  arith_op = alt ? ALU_SUB : ALU_ADD;
      3'b001:  arith_op = ALU_SLL;
      3'b010:  arith_op = ALU_SLT;
      3'b011:  arith_op = ALU_SLTU;
      3'b100:  arith_op = ALU_XOR;
      3'b101:  arith_op = alt ? ALU_SRA : ALU_SRL;
      3'b110:  arith_op = ALU_OR;
      default: arith_op = ALU_AND;
    endcase
  endfunction

  always_comb begin
    // Safe defaults: a NOP
    reg_we     = 1'b0;
    uses_rs1   = 1'b0;
    uses_rs2   = 1'b0;
    alu_op     = ALU_ADD;
    a_sel      = A_RS1;
    b_imm      = 1'b0;
    wb_sel     = WB_ALU;
    mem_read   = 1'b0;
    mem_write  = 1'b0;
    is_branch  = 1'b0;
    is_jal     = 1'b0;
    is_jalr    = 1'b0;
    is_fence_i = 1'b0;
    illegal    = 1'b0;

    case (opcode)
      OP_LUI: begin
        reg_we = 1'b1; alu_op = ALU_PASS_B; b_imm = 1'b1;
      end

      OP_AUIPC: begin
        reg_we = 1'b1; a_sel = A_PC; b_imm = 1'b1;
      end

      OP_JAL: begin
        reg_we = 1'b1; wb_sel = WB_PC4; is_jal = 1'b1;
      end

      OP_JALR: begin
        reg_we = 1'b1; wb_sel = WB_PC4; is_jalr = 1'b1;
        uses_rs1 = 1'b1; b_imm = 1'b1;               // ALU computes rs1 + imm
        illegal = (funct3 != 3'b000);
      end

      OP_BRANCH: begin
        is_branch = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1;
        illegal = (funct3 == 3'b010) || (funct3 == 3'b011);
      end

      OP_LOAD: begin
        reg_we = 1'b1; wb_sel = WB_MEM; mem_read = 1'b1;
        uses_rs1 = 1'b1; b_imm = 1'b1;
        illegal = (funct3 == 3'b011) || (funct3 == 3'b110) || (funct3 == 3'b111);
      end

      OP_STORE: begin
        mem_write = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1; b_imm = 1'b1;
        illegal = (funct3 > 3'b010);
      end

      OP_IMM: begin
        reg_we = 1'b1; uses_rs1 = 1'b1; b_imm = 1'b1;
        // only SRAI uses funct7 to select the alternate op
        alu_op = arith_op(funct3, (funct3 == 3'b101) && funct7[5]);
        if (funct3 == 3'b001) illegal = (funct7 != 7'b0);
        if (funct3 == 3'b101) illegal = (funct7 != 7'b0) && (funct7 != 7'b0100000);
      end

      OP_REG: begin
        reg_we = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1;
        alu_op = arith_op(funct3, funct7[5]);
        illegal = !((funct7 == 7'b0) ||
                    (funct7 == 7'b0100000 && (funct3 == 3'b000 || funct3 == 3'b101)));
      end

      OP_FENCE: begin
        // FENCE is a NOP on this in-order core; FENCE.I flushes the pipeline
        is_fence_i = (funct3 == 3'b001);
        illegal    = (funct3 > 3'b001);
      end

      OP_SYSTEM: begin
        if (funct3 != 3'b000 && funct3 != 3'b100) begin
          // CSRRW/CSRRS/CSRRC(+I): only the read-only counters are implemented,
          // writes are ignored.
          reg_we = 1'b1; wb_sel = WB_CSR;
        end else begin
          illegal = 1'b1;  // ECALL / EBREAK / MRET: no trap support
        end
      end

      default: illegal = 1'b1;
    endcase

    // rd == x0 never writes; dropping reg_we here keeps hazard logic simple
    if (rd == 5'd0) reg_we = 1'b0;
  end

endmodule
