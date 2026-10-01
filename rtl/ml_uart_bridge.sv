// UART runtime wrapper for the Cyclone II handwriting ML core.
//
// Runtime protocol, 8-N-1:
//   PC -> FPGA: 0xA5 followed by 196 pixel bytes (low nibble is used)
//   FPGA -> PC: 0x5A, digit, accepted, confidence,
//               margin low/high, cycles byte 0..3, XOR checksum
//
// This file intentionally does not assign board pins. The clock and UART pins
// must be supplied by the board-specific Quartus project after the connector
// wiring is confirmed.
module ml_uart_bridge #(
  parameter integer CLK_HZ = 8000000,
  parameter integer BAUD = 115200,
  parameter integer CONFIDENCE_THRESHOLD = 0,
  parameter integer MARGIN_THRESHOLD = 0
) (
  input  wire       clk,
  input  wire       reset_n,
  input  wire       uart_rx_i,
  output wire       uart_tx_o,
  output wire       busy,
  output wire       result_valid_o,
  output wire [3:0] result_digit_o
);
  wire       rx_valid;
  wire [7:0] rx_data;
  wire       tx_ready;
  reg        tx_start;
  reg [7:0]  tx_data;

  uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) rx_i (
    .clk(clk), .reset_n(reset_n), .rx(uart_rx_i),
    .data_valid(rx_valid), .data(rx_data)
  );

  uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) tx_i (
    .clk(clk), .reset_n(reset_n), .start(tx_start), .data(tx_data),
    .tx(uart_tx_o), .ready(tx_ready)
  );

  reg        core_frame_valid;
  reg [7:0]  core_pixel_index;
  reg [3:0]  core_pixel;
  reg        core_frame_last;
  reg        core_frame_error;
  wire       core_busy;
  wire       core_result_valid;
  wire       core_result_accepted;
  wire [3:0] core_result_digit;
  wire [7:0] core_result_confidence;
  wire [15:0] core_result_margin;
  wire [31:0] core_result_cycles;

  ml_inference #(
    .CONFIDENCE_THRESHOLD(CONFIDENCE_THRESHOLD),
    .MARGIN_THRESHOLD(MARGIN_THRESHOLD)
  ) core_i (
    .clk(clk), .reset_n(reset_n),
    .clock_enable(1'b1),
    .input_frame_valid(core_frame_valid),
    .input_pixel_index(core_pixel_index),
    .input_pixel(core_pixel),
    .input_frame_last(core_frame_last),
    .input_frame_error(core_frame_error),
    .busy(core_busy),
    .result_valid(core_result_valid),
    .result_accepted(core_result_accepted),
    .result_digit(core_result_digit),
    .result_confidence(core_result_confidence),
    .result_margin(core_result_margin),
    .result_cycles(core_result_cycles)
  );

  reg        frame_active;
  reg [7:0]  frame_index;
  reg [3:0]  saved_digit;
  reg        saved_accepted;
  reg [7:0]  saved_confidence;
  reg [15:0] saved_margin;
  reg [31:0] saved_cycles;
  reg        tx_active;
  reg [3:0]  tx_index;
  reg [7:0]  packet_byte;
  reg [7:0]  packet_xor;

  assign busy = core_busy | frame_active | tx_active;
  assign result_valid_o = core_result_valid;
  assign result_digit_o = core_result_digit;

  // Packet indexes 0..10: sync, digit, accepted, confidence, margin[1:0],
  // cycles[3:0], checksum.
  always @* begin
    case (tx_index)
      4'd0: packet_byte = 8'h5A;
      4'd1: packet_byte = {4'b0, saved_digit};
      4'd2: packet_byte = {7'b0, saved_accepted};
      4'd3: packet_byte = saved_confidence;
      4'd4: packet_byte = saved_margin[7:0];
      4'd5: packet_byte = saved_margin[15:8];
      4'd6: packet_byte = saved_cycles[7:0];
      4'd7: packet_byte = saved_cycles[15:8];
      4'd8: packet_byte = saved_cycles[23:16];
      4'd9: packet_byte = saved_cycles[31:24];
      4'd10: packet_byte = packet_xor;
      default: packet_byte = 0;
    endcase
  end

  always @(posedge clk) begin
    tx_start <= 1'b0;
    core_frame_valid <= 1'b0;
    core_frame_last <= 1'b0;
    core_frame_error <= 1'b0;

    if (!reset_n) begin
      frame_active <= 1'b0;
      frame_index <= 0;
      tx_active <= 1'b0;
      tx_index <= 0;
      tx_data <= 0;
      packet_xor <= 0;
      saved_digit <= 0;
      saved_accepted <= 0;
      saved_confidence <= 0;
      saved_margin <= 0;
      saved_cycles <= 0;
    end else begin
      // A new frame starts with 0xA5 while the bridge is idle.
      if (rx_valid && !frame_active && !core_busy && !tx_active && rx_data == 8'hA5) begin
        frame_active <= 1'b1;
        frame_index <= 0;
      end

      // Every byte after 0xA5 is one pixel. The last pixel starts inference.
      if (rx_valid && frame_active) begin
        core_frame_valid <= 1'b1;
        core_pixel_index <= frame_index;
        core_pixel <= rx_data[3:0];
        if (frame_index == 8'd195) begin
          core_frame_last <= 1'b1;
          frame_active <= 1'b0;
        end else begin
          frame_index <= frame_index + 1'b1;
        end
      end

      if (core_result_valid) begin
        saved_digit <= core_result_digit;
        saved_accepted <= core_result_accepted;
        saved_confidence <= core_result_confidence;
        saved_margin <= core_result_margin;
        saved_cycles <= core_result_cycles;
        packet_xor <= 8'h5A ^ {4'b0, core_result_digit} ^
                      {7'b0, core_result_accepted} ^ core_result_confidence ^
                      core_result_margin[7:0] ^ core_result_margin[15:8] ^
                      core_result_cycles[7:0] ^ core_result_cycles[15:8] ^
                      core_result_cycles[23:16] ^ core_result_cycles[31:24];
        tx_active <= 1'b1;
        tx_index <= 0;
      end

      if (tx_active && tx_ready) begin
        tx_data <= packet_byte;
        tx_start <= 1'b1;
        if (tx_index == 4'd10) begin
          tx_active <= 1'b0;
        end else begin
          tx_index <= tx_index + 1'b1;
        end
      end
    end
  end
endmodule

module uart_rx #(
  parameter integer CLK_HZ = 8000000,
  parameter integer BAUD = 115200
) (
  input wire clk, input wire reset_n, input wire rx,
  output reg data_valid, output reg [7:0] data
);
  localparam integer DIV = CLK_HZ / BAUD;
  reg [15:0] count;
  reg [3:0] bit_index;
  reg [7:0] shift;
  reg active;

  always @(posedge clk) begin
    data_valid <= 1'b0;
    if (!reset_n) begin
      count <= 0; bit_index <= 0; shift <= 0; active <= 1'b0; data <= 0;
    end else if (!active) begin
      if (!rx) begin
        active <= 1'b1;
        count <= DIV / 2;
        bit_index <= 0;
      end
    end else if (count != 0) begin
      count <= count - 1'b1;
    end else begin
      count <= DIV - 1;
      if (bit_index < 8) begin
        shift[bit_index] <= rx;
        bit_index <= bit_index + 1'b1;
      end else begin
        active <= 1'b0;
        data <= shift;
        data_valid <= 1'b1;
      end
    end
  end
endmodule

module uart_tx #(
  parameter integer CLK_HZ = 8000000,
  parameter integer BAUD = 115200
) (
  input wire clk, input wire reset_n, input wire start, input wire [7:0] data,
  output reg tx, output wire ready
);
  localparam integer DIV = CLK_HZ / BAUD;
  reg [15:0] count;
  reg [3:0] bit_index;
  reg [9:0] shift;
  reg active;

  assign ready = !active;

  always @(posedge clk) begin
    if (!reset_n) begin
      tx <= 1'b1; count <= 0; bit_index <= 0; shift <= 10'h3FF; active <= 1'b0;
    end else if (!active) begin
      tx <= 1'b1;
      if (start) begin
        shift <= {1'b1, data, 1'b0};
        bit_index <= 0;
        count <= DIV - 1;
        active <= 1'b1;
        tx <= 1'b0;
      end
    end else if (count != 0) begin
      count <= count - 1'b1;
    end else begin
      count <= DIV - 1;
      shift <= {1'b1, shift[9:1]};
      bit_index <= bit_index + 1'b1;
      tx <= shift[1];
      if (bit_index == 4'd9) begin
        active <= 1'b0;
        tx <= 1'b1;
      end
    end
  end
endmodule
