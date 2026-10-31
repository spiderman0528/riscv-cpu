// hazard_unit.sv - decides when the instruction in ID must wait.
//
// With forwarding enabled only the load-use hazard needs a stall: a load's
// data is not ready until the end of MEM, so a dependent instruction directly
// behind it waits one cycle and then picks the value up from MEM/WB.
//
// With FORWARDING = 0 (used for the performance comparison) ID waits until
// every in-flight producer of its sources has reached WB, where the register
// file's write-through bypass hands the value over.
module hazard_unit #(
  parameter int FORWARDING = 1
) (
  input  logic       id_valid,
  input  logic [4:0] id_rs1,
  input  logic [4:0] id_rs2,
  input  logic       id_uses_rs1,
  input  logic       id_uses_rs2,

  input  logic       ex_valid,
  input  logic       ex_reg_we,
  input  logic       ex_mem_read,
  input  logic [4:0] ex_rd,

  input  logic       mem_valid,
  input  logic       mem_reg_we,
  input  logic [4:0] mem_rd,

  output logic       stall
);

  logic ex_dep, mem_dep;

  // rd == x0 never has reg_we set (the decoder clears it), so no x0 check here
  assign ex_dep  = ex_valid  && ex_reg_we &&
                   ((id_uses_rs1 && id_rs1 == ex_rd) || (id_uses_rs2 && id_rs2 == ex_rd));
  assign mem_dep = mem_valid && mem_reg_we &&
                   ((id_uses_rs1 && id_rs1 == mem_rd) || (id_uses_rs2 && id_rs2 == mem_rd));

  generate
    if (FORWARDING != 0) begin : g_fwd
      assign stall = id_valid && ex_dep && ex_mem_read;     // load-use only
    end else begin : g_nofwd
      assign stall = id_valid && (ex_dep || mem_dep);
    end
  endgenerate

endmodule
