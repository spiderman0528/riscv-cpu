// soc.sv - core + 64 KiB dual-port RAM + memory-mapped peripherals
//
//   0x0000_0000 - 0x0000_FFFF  RAM (code + data + stack)
//   0x1000_0000                UART TX data   (write a byte to send it)
//   0x1000_0004                UART status    (bit 0 = transmitter busy)
//   0x1000_0008                LEDs           (read/write)
//   0x1000_000C                switches       (read)
//   0x1000_0010                sim exit       (write: end simulation, value = exit code)
module soc
  import riscv_pkg::*;
#(
  parameter int    FORWARDING = 1,
  parameter int    BP_ENABLE  = 1,
  parameter int    BP_ENTRIES = 64,
  parameter int    RAM_WORDS  = 16384,
  parameter        INIT_HEX   = "",
  parameter int    CLK_HZ     = 50_000_000,
  parameter int    BAUD       = 115_200,
  parameter int    SIM_UART   = 0         // 1: UART never reports busy (fast sim)
) (
  input  logic        clk,
  input  logic        rst,

  output logic [9:0]  leds,
  input  logic [9:0]  switches,
  output logic        uart_txd,

  // debug / verification port
  output logic        retire_valid,
  output logic [31:0] retire_pc,
  output logic [31:0] retire_inst,
  output logic        retire_reg_we,
  output logic [4:0]  retire_rd,
  output logic [31:0] retire_wdata,
  output logic        retire_mem_we,
  output logic [31:0] retire_mem_addr,
  output logic [31:0] retire_mem_wdata,
  output logic [1:0]  retire_mem_size,
  output logic        retire_illegal,
  output logic [63:0] perf_cycle,
  output logic [63:0] perf_instret,
  output logic [31:0] perf_mispredict,
  output logic [31:0] perf_stall
);

  logic [31:0] imem_addr, imem_rdata;
  logic        dmem_re, dmem_we;
  logic [3:0]  dmem_be;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;

  core #(
    .FORWARDING(FORWARDING), .BP_ENABLE(BP_ENABLE), .BP_ENTRIES(BP_ENTRIES)
  ) u_core (
    .clk, .rst,
    .imem_addr, .imem_rdata,
    .dmem_re, .dmem_we, .dmem_be, .dmem_addr, .dmem_wdata, .dmem_rdata,
    .retire_valid, .retire_pc, .retire_inst, .retire_reg_we, .retire_rd,
    .retire_wdata, .retire_mem_we, .retire_mem_addr, .retire_mem_wdata,
    .retire_mem_size, .retire_illegal,
    .perf_cycle, .perf_instret, .perf_mispredict, .perf_stall
  );

  // ---------------- address decode ----------------
  logic is_mmio;
  assign is_mmio = (dmem_addr[31:28] == MMIO_BASE[31:28]);

  logic [31:0] ram_rdata;

  ram_dp #(.WORDS(RAM_WORDS), .INIT_HEX(INIT_HEX)) u_ram (
    .clk,
    .a_addr  (imem_addr),
    .a_rdata (imem_rdata),
    .b_en    ((dmem_re || dmem_we) && !is_mmio),
    .b_we    (dmem_we ? dmem_be : 4'b0000),
    .b_addr  (dmem_addr),
    .b_wdata (dmem_wdata),
    .b_rdata (ram_rdata)
  );

  // ---------------- peripherals ----------------
  logic       uart_busy, uart_start;
  logic [7:0] uart_data;

  assign uart_start = dmem_we && is_mmio && (dmem_addr[7:0] == MMIO_UART_TX[7:0]);
  assign uart_data  = dmem_wdata[7:0];

  uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
    .clk, .rst,
    .start (uart_start),
    .data  (uart_data),
    .busy  (uart_busy),
    .tx    (uart_txd)
  );

  always_ff @(posedge clk) begin
    if (rst) leds <= '0;
    else if (dmem_we && is_mmio && dmem_addr[7:0] == MMIO_LEDS[7:0])
      leds <= dmem_wdata[9:0];
  end

  // MMIO reads are registered to match the RAM's one-cycle read latency
  logic        mmio_sel_q;
  logic [31:0] mmio_rdata_q;

  always_ff @(posedge clk) begin
    mmio_sel_q <= is_mmio;
    if (dmem_re && is_mmio) begin
      case (dmem_addr[7:0])
        MMIO_UART_ST[7:0]:  mmio_rdata_q <= {31'b0, (SIM_UART != 0) ? 1'b0 : uart_busy};
        MMIO_LEDS[7:0]:     mmio_rdata_q <= {22'b0, leds};
        MMIO_SWITCHES[7:0]: mmio_rdata_q <= {22'b0, switches};
        default:            mmio_rdata_q <= 32'b0;
      endcase
    end
  end

  assign dmem_rdata = mmio_sel_q ? mmio_rdata_q : ram_rdata;

endmodule
