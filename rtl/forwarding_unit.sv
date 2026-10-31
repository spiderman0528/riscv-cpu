// forwarding_unit.sv - bypass network for the EX stage operands.
//
// Priority: the youngest producer wins.
//   1. EX/MEM  (instruction one ahead)  - ALU / PC+4 / CSR results only.
//      A load in EX/MEM cannot forward; the hazard unit has already stalled.
//   2. MEM/WB  (instruction two ahead)  - any result, including load data.
//   3. Value read from the register file in ID.
module forwarding_unit #(
  parameter int FORWARDING = 1
) (
  input  logic [4:0]  rs,
  input  logic [31:0] rf_value,

  input  logic        mem_valid,
  input  logic        mem_reg_we,
  input  logic        mem_is_load,
  input  logic [4:0]  mem_rd,
  input  logic [31:0] mem_value,

  input  logic        wb_valid,
  input  logic        wb_reg_we,
  input  logic [4:0]  wb_rd,
  input  logic [31:0] wb_value,

  output logic [31:0] value
);

  always_comb begin
    value = rf_value;
    if (FORWARDING != 0 && rs != 5'd0) begin
      if (mem_valid && mem_reg_we && !mem_is_load && mem_rd == rs)
        value = mem_value;
      else if (wb_valid && wb_reg_we && wb_rd == rs)
        value = wb_value;
    end
  end

endmodule
