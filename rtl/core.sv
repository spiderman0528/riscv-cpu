// core.sv - 5-stage in-order pipelined RV32I core
//
//   IF  -> ID  -> EX  -> MEM -> WB
//
//  * Branch prediction in IF (BTB + 2-bit BHT), resolved in EX.
//    A misprediction flushes IF/ID and ID/EX (2-cycle penalty).
//  * Full forwarding into EX from EX/MEM and MEM/WB; 1-cycle load-use stall.
//  * Instruction and data memories are SYNCHRONOUS (block-RAM friendly):
//      - the fetch address is the *next* PC, so the instruction for the
//        current PC is available at the start of IF;
//      - the data address leaves at the end of EX, so load data is available
//        during MEM and stores commit on the EX->MEM clock edge.
//  * Read-only performance counters: cycle, instret, mispredicts, stalls.
//  * A retirement port exposes every committed instruction so a testbench can
//    check it against a golden model (co-simulation).
module core
  import riscv_pkg::*;
#(
  parameter int FORWARDING = 1,   // 0: stall on every RAW hazard
  parameter int BP_ENABLE  = 1,   // 0: static not-taken prediction
  parameter int BP_ENTRIES = 64
) (
  input  logic        clk,
  input  logic        rst,

  // instruction port (synchronous read: data for imem_addr arrives next cycle)
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,

  // data port (address/write on the EX->MEM edge, read data during MEM)
  output logic        dmem_re,
  output logic        dmem_we,
  output logic [3:0]  dmem_be,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  input  logic [31:0] dmem_rdata,

  // retirement / debug port (one instruction per cycle at most)
  output logic        retire_valid,
  output logic [31:0] retire_pc,
  output logic [31:0] retire_inst,
  output logic        retire_reg_we,
  output logic [4:0]  retire_rd,
  output logic [31:0] retire_wdata,
  output logic        retire_mem_we,
  output logic [31:0] retire_mem_addr,
  output logic [31:0] retire_mem_wdata,   // rs2 before byte-lane shifting
  output logic [1:0]  retire_mem_size,    // 0: byte, 1: half, 2: word
  output logic        retire_illegal,

  // performance counters (also readable through CSRs)
  output logic [63:0] perf_cycle,
  output logic [63:0] perf_instret,
  output logic [31:0] perf_mispredict,
  output logic [31:0] perf_stall
);

  // ===========================================================================
  // Hazard / redirect control signals (driven further down)
  // ===========================================================================
  logic        stall_d;          // hold IF and ID, bubble into EX
  logic        redirect_e;       // flush IF/ID and ID/EX, restart at redirect_pc
  logic [31:0] redirect_pc_e;

  // ===========================================================================
  // IF - instruction fetch
  // ===========================================================================
  logic [31:0] pc_f, pc_next;
  logic        pred_taken_f;
  logic [31:0] pred_target_f;

  // EX-stage predictor training signals
  logic        bp_upd_valid, bp_upd_is_cond, bp_upd_taken;
  logic [31:0] bp_upd_pc, bp_upd_target;

  branch_predictor #(.ENABLE(BP_ENABLE), .ENTRIES(BP_ENTRIES)) u_bp (
    .clk, .rst,
    .pc          (pc_f),
    .pred_taken  (pred_taken_f),
    .pred_target (pred_target_f),
    .upd_valid   (bp_upd_valid),
    .upd_pc      (bp_upd_pc),
    .upd_is_cond (bp_upd_is_cond),
    .upd_taken   (bp_upd_taken),
    .upd_target  (bp_upd_target)
  );

  always_comb begin
    if (redirect_e)        pc_next = redirect_pc_e;
    else if (stall_d)      pc_next = pc_f;
    else if (pred_taken_f) pc_next = pred_target_f;
    else                   pc_next = pc_f + 32'd4;
  end

  // During reset keep fetching RESET_PC so its instruction is ready right after.
  assign imem_addr = rst ? RESET_PC : pc_next;

  always_ff @(posedge clk) begin
    if (rst) pc_f <= RESET_PC;
    else     pc_f <= pc_next;
  end

  // ---------------- IF/ID ----------------
  logic        d_valid;
  logic [31:0] d_pc, d_inst, d_pred_target;
  logic        d_pred_taken;

  always_ff @(posedge clk) begin
    if (rst || redirect_e) begin
      d_valid <= 1'b0;
    end else if (!stall_d) begin
      d_valid       <= 1'b1;
      d_pc          <= pc_f;
      d_inst        <= imem_rdata;
      d_pred_taken  <= pred_taken_f;
      d_pred_target <= pred_target_f;
    end
  end

  // ===========================================================================
  // ID - decode and register read
  // ===========================================================================
  logic        d_reg_we, d_uses_rs1, d_uses_rs2, d_b_imm;
  logic        d_mem_read, d_mem_write, d_is_branch, d_is_jal, d_is_jalr;
  logic        d_is_fence_i, d_illegal;
  logic [3:0]  d_alu_op;
  logic [1:0]  d_a_sel, d_wb_sel;
  logic [31:0] d_imm, d_rs1_val, d_rs2_val;
  logic [4:0]  d_rs1, d_rs2, d_rd;

  assign d_rs1 = d_inst[19:15];
  assign d_rs2 = d_inst[24:20];
  assign d_rd  = d_inst[11:7];

  decoder u_dec (
    .inst       (d_inst),
    .reg_we     (d_reg_we),
    .uses_rs1   (d_uses_rs1),
    .uses_rs2   (d_uses_rs2),
    .alu_op     (d_alu_op),
    .a_sel      (d_a_sel),
    .b_imm      (d_b_imm),
    .wb_sel     (d_wb_sel),
    .mem_read   (d_mem_read),
    .mem_write  (d_mem_write),
    .is_branch  (d_is_branch),
    .is_jal     (d_is_jal),
    .is_jalr    (d_is_jalr),
    .is_fence_i (d_is_fence_i),
    .illegal    (d_illegal)
  );

  imm_gen u_immgen (.inst(d_inst), .imm(d_imm));

  // write-back signals (driven in WB)
  logic        w_valid, w_reg_we;
  logic [4:0]  w_rd;
  logic [31:0] w_data;

  regfile u_rf (
    .clk,
    .we     (w_valid && w_reg_we),
    .waddr  (w_rd),
    .wdata  (w_data),
    .raddr1 (d_rs1),
    .raddr2 (d_rs2),
    .rdata1 (d_rs1_val),
    .rdata2 (d_rs2_val)
  );

  // ---------------- ID/EX ----------------
  logic        e_valid, e_reg_we, e_b_imm, e_mem_read, e_mem_write;
  logic        e_is_branch, e_is_jal, e_is_jalr, e_is_fence_i, e_illegal;
  logic        e_pred_taken;
  logic [3:0]  e_alu_op;
  logic [1:0]  e_a_sel, e_wb_sel;
  logic [31:0] e_pc, e_inst, e_imm, e_rs1_val, e_rs2_val, e_pred_target;
  logic [4:0]  e_rs1, e_rs2, e_rd;
  logic [2:0]  e_funct3;

  always_ff @(posedge clk) begin
    if (rst || redirect_e || stall_d) begin
      e_valid <= 1'b0;                      // bubble
    end else begin
      e_valid <= d_valid;
    end
    // datapath fields do not need reset; e_valid qualifies them
    if (!(rst || redirect_e || stall_d)) begin
      e_pc          <= d_pc;
      e_inst        <= d_inst;
      e_imm         <= d_imm;
      e_rs1_val     <= d_rs1_val;
      e_rs2_val     <= d_rs2_val;
      e_rs1         <= d_rs1;
      e_rs2         <= d_rs2;
      e_rd          <= d_rd;
      e_funct3      <= d_inst[14:12];
      e_reg_we      <= d_reg_we;
      e_alu_op      <= d_alu_op;
      e_a_sel       <= d_a_sel;
      e_b_imm       <= d_b_imm;
      e_wb_sel      <= d_wb_sel;
      e_mem_read    <= d_mem_read;
      e_mem_write   <= d_mem_write;
      e_is_branch   <= d_is_branch;
      e_is_jal      <= d_is_jal;
      e_is_jalr     <= d_is_jalr;
      e_is_fence_i  <= d_is_fence_i;
      e_illegal     <= d_illegal;
      e_pred_taken  <= d_pred_taken;
      e_pred_target <= d_pred_target;
    end
  end

  // ===========================================================================
  // EX - execute, branch resolution, memory address
  // ===========================================================================
  // EX/MEM fields used by forwarding (declared here, driven below)
  logic        m_valid, m_reg_we;
  logic [1:0]  m_wb_sel;
  logic [4:0]  m_rd;
  logic [31:0] m_result;

  logic [31:0] e_op1, e_op2;      // forwarded rs1 / rs2

  forwarding_unit #(.FORWARDING(FORWARDING)) u_fwd1 (
    .rs(e_rs1), .rf_value(e_rs1_val),
    .mem_valid(m_valid), .mem_reg_we(m_reg_we), .mem_is_load(m_wb_sel == WB_MEM),
    .mem_rd(m_rd), .mem_value(m_result),
    .wb_valid(w_valid), .wb_reg_we(w_reg_we), .wb_rd(w_rd), .wb_value(w_data),
    .value(e_op1)
  );

  forwarding_unit #(.FORWARDING(FORWARDING)) u_fwd2 (
    .rs(e_rs2), .rf_value(e_rs2_val),
    .mem_valid(m_valid), .mem_reg_we(m_reg_we), .mem_is_load(m_wb_sel == WB_MEM),
    .mem_rd(m_rd), .mem_value(m_result),
    .wb_valid(w_valid), .wb_reg_we(w_reg_we), .wb_rd(w_rd), .wb_value(w_data),
    .value(e_op2)
  );

  logic [31:0] alu_a, alu_b, alu_y;

  always_comb begin
    case (e_a_sel)
      A_PC:    alu_a = e_pc;
      A_ZERO:  alu_a = 32'b0;
      default: alu_a = e_op1;
    endcase
  end
  assign alu_b = e_b_imm ? e_imm : e_op2;

  alu u_alu (.op(e_alu_op), .a(alu_a), .b(alu_b), .y(alu_y));

  // ---------------- branch resolution ----------------
  logic        br_cond, e_taken, e_ctrl;
  logic [31:0] e_target, e_pc4, e_actual_next, e_pred_next;

  always_comb begin
    case (e_funct3)
      3'b000:  br_cond = (e_op1 == e_op2);                       // BEQ
      3'b001:  br_cond = (e_op1 != e_op2);                       // BNE
      3'b100:  br_cond = ($signed(e_op1) <  $signed(e_op2));     // BLT
      3'b101:  br_cond = ($signed(e_op1) >= $signed(e_op2));     // BGE
      3'b110:  br_cond = (e_op1 <  e_op2);                       // BLTU
      3'b111:  br_cond = (e_op1 >= e_op2);                       // BGEU
      default: br_cond = 1'b0;
    endcase
  end

  assign e_pc4         = e_pc + 32'd4;
  assign e_ctrl        = e_is_branch || e_is_jal || e_is_jalr;
  assign e_taken       = e_is_jal || e_is_jalr || (e_is_branch && br_cond);
  assign e_target      = e_is_jalr ? {alu_y[31:1], 1'b0} : (e_pc + e_imm);
  assign e_actual_next = e_taken ? e_target : e_pc4;
  assign e_pred_next   = e_pred_taken ? e_pred_target : e_pc4;

  logic mispredict_e;
  assign mispredict_e  = e_valid && (e_actual_next != e_pred_next);
  assign redirect_e    = mispredict_e || (e_valid && e_is_fence_i);
  assign redirect_pc_e = e_actual_next;   // pc+4 for FENCE.I

  assign bp_upd_valid   = e_valid && e_ctrl;
  assign bp_upd_pc      = e_pc;
  assign bp_upd_is_cond = e_is_branch;
  assign bp_upd_taken   = e_taken;
  assign bp_upd_target  = e_target;

  // ---------------- CSR (read-only counters) ----------------
  logic [31:0] csr_val;
  always_comb begin
    case (e_inst[31:20])
      CSR_CYCLE:    csr_val = perf_cycle[31:0];
      CSR_CYCLEH:   csr_val = perf_cycle[63:32];
      CSR_INSTRET:  csr_val = perf_instret[31:0];
      CSR_INSTRETH: csr_val = perf_instret[63:32];
      CSR_HPM3:     csr_val = perf_mispredict;
      CSR_HPM4:     csr_val = perf_stall;
      default:      csr_val = 32'b0;
    endcase
  end

  logic [31:0] e_result;
  always_comb begin
    case (e_wb_sel)
      WB_PC4:  e_result = e_pc4;
      WB_CSR:  e_result = csr_val;
      default: e_result = alu_y;       // WB_MEM gets replaced in MEM
    endcase
  end

  // ---------------- data memory request ----------------
  logic [1:0] e_byte_off;
  assign e_byte_off = alu_y[1:0];

  assign dmem_addr = alu_y;
  assign dmem_re   = e_valid && e_mem_read;
  assign dmem_we   = e_valid && e_mem_write;

  always_comb begin
    case (e_funct3[1:0])
      2'b00: begin  // byte
        dmem_be    = 4'b0001 << e_byte_off;
        dmem_wdata = {4{e_op2[7:0]}};
      end
      2'b01: begin  // half
        dmem_be    = e_byte_off[1] ? 4'b1100 : 4'b0011;
        dmem_wdata = {2{e_op2[15:0]}};
      end
      default: begin
        dmem_be    = 4'b1111;
        dmem_wdata = e_op2;
      end
    endcase
  end

  // ---------------- EX/MEM ----------------
  logic        m_mem_write, m_illegal;
  logic [31:0] m_pc, m_inst, m_addr, m_store_data;
  logic [2:0]  m_funct3;

  always_ff @(posedge clk) begin
    if (rst) m_valid <= 1'b0;
    else     m_valid <= e_valid;
    m_pc         <= e_pc;
    m_inst       <= e_inst;
    m_rd         <= e_rd;
    m_reg_we     <= e_reg_we;
    m_wb_sel     <= e_wb_sel;
    m_result     <= e_result;
    m_mem_write  <= e_mem_write;
    m_addr       <= alu_y;
    m_store_data <= e_op2;
    m_funct3     <= e_funct3;
    m_illegal    <= e_illegal;
  end

  // ===========================================================================
  // MEM - load data alignment
  // ===========================================================================
  logic [31:0] load_shifted, load_data, m_final;

  assign load_shifted = dmem_rdata >> {m_addr[1:0], 3'b000};

  always_comb begin
    case (m_funct3)
      3'b000:  load_data = {{24{load_shifted[7]}},  load_shifted[7:0]};   // LB
      3'b001:  load_data = {{16{load_shifted[15]}}, load_shifted[15:0]};  // LH
      3'b100:  load_data = {24'b0, load_shifted[7:0]};                    // LBU
      3'b101:  load_data = {16'b0, load_shifted[15:0]};                   // LHU
      default: load_data = dmem_rdata;                                    // LW
    endcase
  end

  assign m_final = (m_wb_sel == WB_MEM) ? load_data : m_result;

  // ---------------- MEM/WB ----------------
  logic        w_mem_write, w_illegal;
  logic [31:0] w_pc, w_inst, w_addr, w_store_data;
  logic [2:0]  w_funct3;

  always_ff @(posedge clk) begin
    if (rst) w_valid <= 1'b0;
    else     w_valid <= m_valid;
    w_pc         <= m_pc;
    w_inst       <= m_inst;
    w_rd         <= m_rd;
    w_reg_we     <= m_reg_we;
    w_data       <= m_final;
    w_mem_write  <= m_mem_write;
    w_addr       <= m_addr;
    w_store_data <= m_store_data;
    w_funct3     <= m_funct3;
    w_illegal    <= m_illegal;
  end

  // ===========================================================================
  // WB - register write happens inside the register file (see u_rf)
  // ===========================================================================
  assign retire_valid     = w_valid;
  assign retire_pc        = w_pc;
  assign retire_inst      = w_inst;
  assign retire_reg_we    = w_reg_we;
  assign retire_rd        = w_rd;
  assign retire_wdata     = w_data;
  assign retire_mem_we    = w_mem_write;
  assign retire_mem_addr  = w_addr;
  assign retire_mem_wdata = w_store_data;
  assign retire_mem_size  = w_funct3[1:0];
  assign retire_illegal   = w_illegal;

  // ===========================================================================
  // Hazard detection
  // ===========================================================================
  hazard_unit #(.FORWARDING(FORWARDING)) u_hz (
    .id_valid    (d_valid),
    .id_rs1      (d_rs1),
    .id_rs2      (d_rs2),
    .id_uses_rs1 (d_uses_rs1),
    .id_uses_rs2 (d_uses_rs2),
    .ex_valid    (e_valid),
    .ex_reg_we   (e_reg_we),
    .ex_mem_read (e_mem_read),
    .ex_rd       (e_rd),
    .mem_valid   (m_valid),
    .mem_reg_we  (m_reg_we),
    .mem_rd      (m_rd),
    .stall       (stall_d)
  );

  // ===========================================================================
  // Performance counters
  // ===========================================================================
  always_ff @(posedge clk) begin
    if (rst) begin
      perf_cycle      <= 64'd0;
      perf_instret    <= 64'd0;
      perf_mispredict <= 32'd0;
      perf_stall      <= 32'd0;
    end else begin
      perf_cycle <= perf_cycle + 64'd1;
      if (w_valid)                     perf_instret    <= perf_instret + 64'd1;
      if (mispredict_e)                perf_mispredict <= perf_mispredict + 32'd1;
      if (stall_d && !redirect_e)      perf_stall      <= perf_stall + 32'd1;
    end
  end

endmodule
