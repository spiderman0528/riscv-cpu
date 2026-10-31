// uart_tx.sv - 8N1 UART transmitter
module uart_tx #(
  parameter int CLK_HZ = 50_000_000,
  parameter int BAUD   = 115_200
) (
  input  logic       clk,
  input  logic       rst,
  input  logic       start,
  input  logic [7:0] data,
  output logic       busy,
  output logic       tx
);

  localparam int DIV = CLK_HZ / BAUD;

  logic [$clog2(DIV+1)-1:0] baud_cnt;
  logic [3:0]               bit_idx;
  logic [9:0]               shreg;     // {stop, data[7:0], start}

  assign tx = busy ? shreg[0] : 1'b1;

  always_ff @(posedge clk) begin
    if (rst) begin
      busy     <= 1'b0;
      baud_cnt <= '0;
      bit_idx  <= '0;
      shreg    <= '1;
    end else if (!busy) begin
      if (start) begin
        busy     <= 1'b1;
        shreg    <= {1'b1, data, 1'b0};
        baud_cnt <= '0;
        bit_idx  <= '0;
      end
    end else if (32'(baud_cnt) == DIV - 1) begin
      baud_cnt <= '0;
      shreg    <= {1'b1, shreg[9:1]};
      if (bit_idx == 4'd9) busy <= 1'b0;
      else                 bit_idx <= bit_idx + 4'd1;
    end else begin
      baud_cnt <= baud_cnt + 1'b1;
    end
  end

endmodule
