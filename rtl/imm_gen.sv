// imm_gen.sv - immediate decoder for the I/S/B/U/J formats
module imm_gen
  import riscv_pkg::*;
(
  input  logic [31:0] inst,
  output logic [31:0] imm
);

  logic [31:0] i_imm, s_imm, b_imm, u_imm, j_imm;

  assign i_imm = {{20{inst[31]}}, inst[31:20]};
  assign s_imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};
  assign b_imm = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
  assign u_imm = {inst[31:12], 12'b0};
  assign j_imm = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

  always_comb begin
    case (inst[6:0])
      OP_STORE:          imm = s_imm;
      OP_BRANCH:         imm = b_imm;
      OP_LUI, OP_AUIPC:  imm = u_imm;
      OP_JAL:            imm = j_imm;
      default:           imm = i_imm;  // OP-IMM, LOAD, JALR, SYSTEM
    endcase
  end

endmodule
