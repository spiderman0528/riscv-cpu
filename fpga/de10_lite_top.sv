// de10_lite_top.sv - board wrapper for the Terasic DE10-Lite (MAX 10 10M50)
//
//   KEY[0]      reset (active low)
//   SW[9:0]     readable at 0x1000000C
//   LEDR[9:0]   driven from 0x10000008
//   ARDUINO_IO[1]  UART TX, 115200 8N1 (connect to a 3.3 V USB-UART RX pin)
module de10_lite_top (
  input  logic       MAX10_CLK1_50,
  input  logic [1:0] KEY,
  input  logic [9:0] SW,
  output logic [9:0] LEDR,
  inout  wire  [15:0] ARDUINO_IO
);

  // ---- 25 MHz core clock ----
  // The open-source timing estimate (scripts/synth_ecp5.sh) puts the critical
  // path (EX branch resolution -> next-PC mux -> block-RAM address) at about
  // 25 ns, so the core runs at 50/2 MHz. A toggle flip-flop is used instead of
  // a PLL to keep the project free of generated IP; the SDC file declares it
  // as a generated clock and Quartus routes it on a global network.
  logic clk = 1'b0;
  always_ff @(posedge MAX10_CLK1_50) clk <= ~clk;

  // ---- reset synchroniser (KEY is active low and asynchronous) ----
  logic [2:0] rst_sync = 3'b111;
  always_ff @(posedge clk) rst_sync <= {rst_sync[1:0], ~KEY[0]};
  logic rst;
  assign rst = rst_sync[2];

  // ---- switch synchroniser ----
  logic [9:0] sw_meta, sw_sync;
  always_ff @(posedge clk) begin
    sw_meta <= SW;
    sw_sync <= sw_meta;
  end

  logic uart_txd;

  soc #(
    .INIT_HEX ("firmware.hex"),   // built by: make -C sw fpga
    .CLK_HZ   (25_000_000),
    .BAUD     (115_200)
  ) u_soc (
    .clk      (clk),
    .rst      (rst),
    .leds     (LEDR),
    .switches (sw_sync),
    .uart_txd (uart_txd),
    // verification port unused on hardware
    .retire_valid (), .retire_pc (), .retire_inst (), .retire_reg_we (), .retire_rd (),
    .retire_wdata (), .retire_mem_we (), .retire_mem_addr (), .retire_mem_wdata (),
    .retire_mem_size (), .retire_illegal (),
    .perf_cycle (), .perf_instret (), .perf_mispredict (), .perf_stall ()
  );

  assign ARDUINO_IO[1]    = uart_txd;
  assign ARDUINO_IO[0]    = 1'bz;
  assign ARDUINO_IO[15:2] = 'z;

endmodule
