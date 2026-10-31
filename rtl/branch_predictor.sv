// branch_predictor.sv - dynamic branch predictor used in the fetch stage.
//
//   * BTB : direct-mapped branch target buffer (valid, tag, target, kind)
//   * BHT : one 2-bit saturating counter per BTB entry
//
// Prediction (IF, combinational): taken when the BTB hits and the entry is an
// unconditional jump (JAL/JALR) or the counter is in a "taken" state.
// Update (EX): every resolved control-flow instruction trains its entry.
//
// With ENABLE = 0 the predictor always says "not taken" (static prediction),
// which is used as the baseline in the performance comparison.
module branch_predictor #(
  parameter int ENABLE  = 1,
  parameter int ENTRIES = 64           // must be a power of two
) (
  input  logic        clk,
  input  logic        rst,

  // lookup (fetch)
  input  logic [31:0] pc,
  output logic        pred_taken,
  output logic [31:0] pred_target,

  // update (execute)
  input  logic        upd_valid,
  input  logic [31:0] upd_pc,
  input  logic        upd_is_cond,     // conditional branch (vs JAL/JALR)
  input  logic        upd_taken,
  input  logic [31:0] upd_target
);

  localparam int IDX_W = $clog2(ENTRIES);
  localparam int TAG_W = 30 - IDX_W;

  logic             valid  [ENTRIES];
  logic             is_jmp [ENTRIES];
  logic [1:0]       ctr    [ENTRIES];
  logic [TAG_W-1:0] tag    [ENTRIES];
  logic [31:0]      target [ENTRIES];

  logic [IDX_W-1:0] l_idx, u_idx;
  logic [TAG_W-1:0] l_tag, u_tag;

  assign l_idx = pc[IDX_W+1:2];
  assign l_tag = pc[31:IDX_W+2];
  assign u_idx = upd_pc[IDX_W+1:2];
  assign u_tag = upd_pc[31:IDX_W+2];

  // ---------------- lookup ----------------
  logic hit;
  assign hit         = (ENABLE != 0) && valid[l_idx] && (tag[l_idx] == l_tag);
  assign pred_taken  = hit && (is_jmp[l_idx] || ctr[l_idx][1]);
  assign pred_target = target[l_idx];

  // ---------------- update ----------------
  logic same_entry;
  assign same_entry = valid[u_idx] && (tag[u_idx] == u_tag);

  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < ENTRIES; i++) valid[i] <= 1'b0;
    end else if (upd_valid && ENABLE != 0) begin
      // Not-taken branches that are not already tracked are not allocated:
      // a BTB miss already predicts not-taken.
      if (upd_taken || same_entry) begin
        valid[u_idx]  <= 1'b1;
        tag[u_idx]    <= u_tag;
        is_jmp[u_idx] <= !upd_is_cond;
        if (upd_taken) target[u_idx] <= upd_target;

        if (!same_entry)
          ctr[u_idx] <= upd_taken ? 2'b10 : 2'b01;        // weakly taken / not
        else if (upd_taken && ctr[u_idx] != 2'b11)
          ctr[u_idx] <= ctr[u_idx] + 2'b01;
        else if (!upd_taken && ctr[u_idx] != 2'b00)
          ctr[u_idx] <= ctr[u_idx] - 2'b01;
      end
    end
  end

endmodule
