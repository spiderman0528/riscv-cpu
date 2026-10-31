// ram_dp.sv - true dual-port synchronous RAM with byte enables.
//   Port A: instruction fetch (read only)
//   Port B: data load/store
// Written in the template that Intel Quartus, Xilinx Vivado and Yosys infer as
// block RAM. In simulation it can be preloaded with $readmemh.
module ram_dp #(
  parameter int    WORDS    = 16384,           // 64 KiB
  parameter        INIT_HEX = ""
) (
  input  logic        clk,

  input  logic [31:0] a_addr,
  output logic [31:0] a_rdata,

  input  logic        b_en,
  input  logic [3:0]  b_we,
  input  logic [31:0] b_addr,
  input  logic [31:0] b_wdata,
  output logic [31:0] b_rdata
);

  localparam int AW = $clog2(WORDS);

  logic [31:0] mem [WORDS];

`ifdef SIMULATION
  // Simulation: zero the RAM, then load the program named by +hex=<file>
  initial begin
    string hexfile;
    for (int i = 0; i < WORDS; i++) mem[i] = 32'b0;
    if ($value$plusargs("hex=%s", hexfile)) $readmemh(hexfile, mem);
    else if (INIT_HEX != "")                 $readmemh(INIT_HEX, mem);
  end
`else
  // Synthesis: initialise block RAM contents from a hex file
  initial begin
    if (INIT_HEX != "") $readmemh(INIT_HEX, mem);
  end
`endif

  logic [AW-1:0] a_idx, b_idx;
  assign a_idx = a_addr[AW+1:2];
  assign b_idx = b_addr[AW+1:2];

  always_ff @(posedge clk) begin
    a_rdata <= mem[a_idx];
  end

  always_ff @(posedge clk) begin
    if (b_en) begin
      if (b_we[0]) mem[b_idx][7:0]   <= b_wdata[7:0];
      if (b_we[1]) mem[b_idx][15:8]  <= b_wdata[15:8];
      if (b_we[2]) mem[b_idx][23:16] <= b_wdata[23:16];
      if (b_we[3]) mem[b_idx][31:24] <= b_wdata[31:24];
      b_rdata <= mem[b_idx];
    end
  end

endmodule
