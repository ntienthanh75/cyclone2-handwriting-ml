// CoreEP2C5 CY7C68013A slave-FIFO bridge for the handwriting ML core.
//
// USB/FIFO transaction uses 16-bit words:
//   PC -> FPGA: word 0 = 16'hA5A5, then 98 words; each word contains
//               two 4-bit pixels in [3:0] and [11:8].
//   FPGA -> PC: word 0 = 16'h5A5A, word 1 = accepted[8], digit[3:0],
//               word 2 = confidence[7:0], word 3 = margin,
//               words 4/5 = cycle count low/high 16 bits.
//
// Pins and endpoint selection follow the existing CoreEP2C5 USB_LED project:
// EP2 OUT is FIFOADR=00 and EP6 IN is FIFOADR=10.
module ml_fx2_bridge (
  input wire clk,
  input wire rst,
  input wire FLAGA,
  input wire FLAGB,
  input wire FLAGC,
  output reg SLOE,
  output reg SLRD,
  output wire [1:0] FIFOADR,
  output reg SLWR,
  inout wire [15:0] FIFODATA,
  output reg [3:0] led,
  output wire buzz
);
  // 50 MHz USB clock with an exact 5 MHz ML step enable.
  reg [5:0] step_acc;
  wire ml_step = (step_acc >= 45);
  always @(posedge clk or negedge rst) begin
    if (!rst) step_acc <= 0;
    else if (ml_step) step_acc <= step_acc + 5 - 50;
    else step_acc <= step_acc + 5;
  end

  reg [15:0] fifo_out_data;
  assign FIFODATA = (!SLWR) ? fifo_out_data : 16'hzzzz;
  assign FIFOADR = (tx_state != TX_IDLE) ? 2'b10 : 2'b00;
  assign buzz = 1'b1;

  reg [3:0] rx_state;
  localparam RX_IDLE=0, RX_LOW=1, RX_CAPTURE=2;
  reg [7:0] rx_words;
  // Pack the two 4-bit pixels from each USB word into one byte.  This keeps
  // the input buffer compact and avoids a wide register/decode network.
  reg [7:0] frame_mem [0:97];
  reg frame_toggle;

  // FX2 read timing: select EP2, assert output-enable and read strobe,
  // then capture the 16-bit bus on the following clock.
  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      rx_state <= RX_IDLE;
      rx_words <= 0;
      frame_toggle <= 0;
      SLOE <= 1'b1;
      SLRD <= 1'b1;
    end else begin
      SLOE <= 1'b1;
      SLRD <= 1'b1;
      case (rx_state)
        RX_IDLE: begin
          if (FLAGA) rx_state <= RX_LOW;
        end
        RX_LOW: begin
          SLOE <= 1'b0;
          SLRD <= 1'b0;
          rx_state <= RX_CAPTURE;
        end
        RX_CAPTURE: begin
          if (rx_words == 0) begin
            if (FIFODATA == 16'hA5A5) rx_words <= 1;
            else rx_words <= 0;
          end else if (rx_words <= 98) begin
            frame_mem[rx_words - 1] <= {FIFODATA[11:8], FIFODATA[3:0]};
            if (rx_words == 98) begin
              rx_words <= 0;
              frame_toggle <= ~frame_toggle;
            end else begin
              rx_words <= rx_words + 1'b1;
            end
          end
          rx_state <= RX_IDLE;
        end
        default: rx_state <= RX_IDLE;
      endcase
    end
  end

  // Synchronize the completed-frame event into the 8 MHz ML clock domain.
  reg frame_sync1, frame_sync2, frame_seen;
  reg [7:0] ml_index;
  reg ml_frame_valid, ml_frame_last;
  wire ml_busy;
  wire ml_result_valid;
  wire ml_result_accepted;
  wire [3:0] ml_result_digit;
  wire [7:0] ml_result_confidence;
  wire [15:0] ml_result_margin;
  wire [31:0] ml_result_cycles;

  ml_inference #(.CONFIDENCE_THRESHOLD(0), .MARGIN_THRESHOLD(0)) core_i (
    .clk(clk), .reset_n(rst), .clock_enable(ml_step),
    .input_frame_valid(ml_frame_valid),
    .input_pixel_index(ml_index),
    .input_pixel(ml_index[0] ? frame_mem[ml_index[7:1]][7:4]
                             : frame_mem[ml_index[7:1]][3:0]),
    .input_frame_last(ml_frame_last),
    .input_frame_error(1'b0),
    .busy(ml_busy),
    .result_valid(ml_result_valid),
    .result_accepted(ml_result_accepted),
    .result_digit(ml_result_digit),
    .result_confidence(ml_result_confidence),
    .result_margin(ml_result_margin),
    .result_cycles(ml_result_cycles)
  );

  reg result_toggle;
  reg [3:0] saved_digit;
  reg saved_accepted;
  reg [7:0] saved_confidence;
  reg [15:0] saved_margin;
  reg [31:0] saved_cycles;
  reg ml_streaming;

  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      frame_sync1 <= 0; frame_sync2 <= 0; frame_seen <= 0;
      ml_index <= 0; ml_frame_valid <= 0; ml_frame_last <= 0;
      ml_streaming <= 0; result_toggle <= 0;
      saved_digit <= 0; saved_accepted <= 0; saved_confidence <= 0;
      saved_margin <= 0; saved_cycles <= 0;
    end else begin
      frame_sync1 <= frame_toggle;
      frame_sync2 <= frame_sync1;
      ml_frame_valid <= 0;
      ml_frame_last <= 0;
      if (frame_sync2 != frame_seen && !ml_busy) begin
        frame_seen <= frame_sync2;
        ml_streaming <= 1;
        ml_index <= 0;
      end
      if (ml_streaming && !ml_busy) begin
        ml_frame_valid <= 1;
        if (ml_index == 195) begin
          ml_frame_last <= 1;
          ml_streaming <= 0;
        end else begin
          ml_index <= ml_index + 1'b1;
        end
      end
      if (ml_result_valid) begin
        saved_digit <= ml_result_digit;
        saved_accepted <= ml_result_accepted;
        saved_confidence <= ml_result_confidence;
        saved_margin <= ml_result_margin;
        saved_cycles <= ml_result_cycles;
        result_toggle <= ~result_toggle;
      end
    end
  end

  // Synchronize the result event back to the 50 MHz USB/FIFO clock.
  reg result_sync1, result_sync2, result_seen;
  reg result_pending;
  reg [3:0] tx_index;
  reg [15:0] tx_word;
  reg [3:0] tx_state;
  localparam TX_IDLE=0, TX_SETUP=1, TX_WRITE=2, TX_NEXT=3;

  always @* begin
    case (tx_index)
      0: tx_word = 16'h5A5A;
      1: tx_word = {7'b0, saved_accepted, 4'b0, saved_digit};
      2: tx_word = {8'b0, saved_confidence};
      3: tx_word = saved_margin;
      4: tx_word = saved_cycles[15:0];
      5: tx_word = saved_cycles[31:16];
      default: tx_word = 0;
    endcase
  end

  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      result_sync1 <= 0; result_sync2 <= 0; result_seen <= 0;
      result_pending <= 0; tx_index <= 0; tx_state <= TX_IDLE;
      SLWR <= 1'b1; fifo_out_data <= 0;
      led <= 4'b1111;
    end else begin
      result_sync1 <= result_toggle;
      result_sync2 <= result_sync1;
      SLWR <= 1'b1;
      if (result_sync2 != result_seen) begin
        result_seen <= result_sync2;
        result_pending <= 1;
        tx_index <= 0;
        led <= ~saved_digit;
      end
      case (tx_state)
        TX_IDLE: if (result_pending && !FLAGB) tx_state <= TX_SETUP;
        TX_SETUP: begin
          fifo_out_data <= tx_word;
          tx_state <= TX_WRITE;
        end
        TX_WRITE: begin
          fifo_out_data <= tx_word;
          SLWR <= 1'b0;
          tx_state <= TX_NEXT;
        end
        TX_NEXT: begin
          if (tx_index == 5) begin
            result_pending <= 0;
            tx_state <= TX_IDLE;
          end else begin
            tx_index <= tx_index + 1'b1;
            tx_state <= TX_SETUP;
          end
        end
        default: tx_state <= TX_IDLE;
      endcase
    end
  end
endmodule
