// Streaming CoreEP2C5 CY7C68013A to ML bridge.
// PC sends A5A5 followed by 98 words, each containing two 4-bit pixels.
// Pixels are consumed directly by the ML core; no full-frame buffer is used.
module ml_fx2_stream_bridge (
  input wire clk, input wire rst, input wire FLAGA, input wire FLAGB,
  input wire FLAGC, output reg SLOE, output reg SLRD, output wire [1:0] FIFOADR,
  output reg SLWR, inout wire [15:0] FIFODATA, output reg [3:0] led,
  output wire buzz
);
  reg [5:0] step_acc;
  wire ml_step = (step_acc >= 6'd45);
  always @(posedge clk or negedge rst)
    if (!rst) step_acc <= 0;
    else if (ml_step) step_acc <= step_acc + 6'd5 - 6'd50;
    else step_acc <= step_acc + 6'd5;

  reg [1:0] rx_state;
  reg [6:0] rx_count;
  reg [15:0] rx_word;
  reg rx_pending, header_seen;
  localparam RX_IDLE=0, RX_LOW=1, RX_CAPTURE=2;
  reg frame_active, pixel_phase;
  reg [7:0] pixel_index;
  wire ml_valid = ml_step && frame_active && rx_pending;
  wire [3:0] ml_pixel = pixel_phase ? rx_word[11:8] : rx_word[3:0];
  wire ml_last = ml_valid && pixel_phase && (pixel_index == 8'd195);

  reg [15:0] fifo_out_data;
  reg [1:0] tx_state;
  reg [3:0] tx_index;
  reg result_pending, saved_accepted;
  reg [3:0] saved_digit;
  reg [7:0] saved_confidence;
  reg [15:0] saved_margin;
  reg [31:0] saved_cycles;
  localparam TX_IDLE=0, TX_SETUP=1, TX_WRITE=2, TX_NEXT=3;
  wire ml_busy, ml_result_valid, ml_result_accepted;
  wire [3:0] ml_result_digit;
  wire [7:0] ml_result_confidence;
  wire [15:0] ml_result_margin;
  wire [31:0] ml_result_cycles;
  wire [15:0] tx_word = (tx_index==0) ? 16'h5A5A :
                        (tx_index==1) ? {7'b0,saved_accepted,4'b0,saved_digit} :
                        (tx_index==2) ? {8'b0,saved_confidence} :
                        (tx_index==3) ? saved_margin :
                        (tx_index==4) ? saved_cycles[15:0] :
                        (tx_index==5) ? saved_cycles[31:16] : 16'd0;
  assign FIFODATA = !SLWR ? fifo_out_data : 16'hzzzz;
  assign FIFOADR = (tx_state != TX_IDLE) ? 2'b10 : 2'b00;
  assign buzz = 1'b1;

  ml_inference #(.CONFIDENCE_THRESHOLD(0), .MARGIN_THRESHOLD(0)) core_i (
    .clk(clk), .reset_n(rst), .clock_enable(ml_step),
    .input_frame_valid(ml_valid), .input_pixel_index(pixel_index),
    .input_pixel(ml_pixel), .input_frame_last(ml_last), .input_frame_error(1'b0),
    .busy(ml_busy), .result_valid(ml_result_valid),
    .result_accepted(ml_result_accepted), .result_digit(ml_result_digit),
    .result_confidence(ml_result_confidence), .result_margin(ml_result_margin),
    .result_cycles(ml_result_cycles));

  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      rx_state<=RX_IDLE; rx_count<=0; rx_word<=0; rx_pending<=0;
      header_seen<=0; SLOE<=1; SLRD<=1; frame_active<=0;
      pixel_phase<=0; pixel_index<=0;
    end else begin
      SLOE<=1; SLRD<=1;
      case (rx_state)
        RX_IDLE: if (FLAGA && !rx_pending && !frame_active) rx_state<=RX_LOW;
        RX_LOW: begin SLOE<=0; SLRD<=0; rx_state<=RX_CAPTURE; end
        RX_CAPTURE: begin
          if (!header_seen && FIFODATA==16'hA5A5) begin header_seen<=1; rx_count<=0; end
          else if (header_seen && rx_count<98) begin rx_word<=FIFODATA; rx_pending<=1; rx_count<=rx_count+1; end
          rx_state<=RX_IDLE;
        end
        default: rx_state<=RX_IDLE;
      endcase
      if (ml_step) begin
        if (!frame_active && rx_pending) begin frame_active<=1; pixel_phase<=0; pixel_index<=0; end
        else if (frame_active && rx_pending) begin
          if (!pixel_phase) begin pixel_phase<=1; pixel_index<=pixel_index+1; end
          else begin
            pixel_phase<=0; rx_pending<=0;
            if (pixel_index==195) begin frame_active<=0; header_seen<=0; end
          end
        end
      end
    end
  end

  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      result_pending<=0; saved_digit<=0; saved_accepted<=0; saved_confidence<=0;
      saved_margin<=0; saved_cycles<=0; tx_state<=TX_IDLE; tx_index<=0;
      SLWR<=1; fifo_out_data<=0; led<=4'b1111;
    end else begin
      SLWR<=1;
      if (ml_result_valid) begin
        result_pending<=1; saved_digit<=ml_result_digit; saved_accepted<=ml_result_accepted;
        saved_confidence<=ml_result_confidence; saved_margin<=ml_result_margin;
        saved_cycles<=ml_result_cycles; led<=~ml_result_digit;
      end
      case (tx_state)
        TX_IDLE: if (result_pending && !FLAGB) begin tx_index<=0; tx_state<=TX_SETUP; end
        TX_SETUP: begin fifo_out_data<=tx_word; tx_state<=TX_WRITE; end
        TX_WRITE: begin fifo_out_data<=tx_word; SLWR<=0; tx_state<=TX_NEXT; end
        TX_NEXT: if (tx_index==5) begin result_pending<=0; tx_state<=TX_IDLE; end
                 else begin tx_index<=tx_index+1; tx_state<=TX_SETUP; end
        default: tx_state<=TX_IDLE;
      endcase
    end
  end
endmodule
