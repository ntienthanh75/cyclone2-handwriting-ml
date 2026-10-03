// Streaming CoreEP2C5 CY7C68013A to ML bridge.
// PC sends A5A5 followed by 98 words, each containing two 4-bit pixels.
// The complete frame is buffered before inference starts so repeated USB
// transfers cannot overlap the ML input state machine.
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

  reg [2:0] rx_state;
  reg [5:0] rx_wait;
  reg [6:0] rx_count;
  reg [15:0] rx_word;
  reg [7:0] rx_sequence;
  reg header_seen, frame_ready;
  localparam RX_IDLE=0, RX_WAIT=1, RX_LOW=2, RX_CAPTURE=3,
             RX_STORE_LOW=4, RX_STORE_HIGH=5;
  reg [7:0] feed_index;
  wire ml_valid = ml_step && frame_ready;
  wire [3:0] frame_ram_q;
  wire [7:0] frame_ram_write_addr = (rx_state == RX_STORE_LOW) ?
                                     {rx_count,1'b0} : ({rx_count,1'b0} + 1'b1);
  wire [3:0] frame_ram_write_data = (rx_state == RX_STORE_LOW) ?
                                     rx_word[3:0] : rx_word[11:8];
  wire frame_ram_wren = (rx_state == RX_STORE_LOW) || (rx_state == RX_STORE_HIGH);
  wire [3:0] ml_pixel = frame_ram_q;
  wire [7:0] ml_pixel_index = feed_index;
  wire ml_last = ml_valid && (feed_index == 8'd195);

  reg [15:0] fifo_out_data;
  reg [15:0] tx_word_reg;
  reg [1:0] tx_state;
    reg [2:0] tx_index;
  reg [2:0] tx_wait;
  reg result_pending, saved_accepted;
    reg [3:0] saved_digit;
    reg [7:0] saved_confidence;
    reg [15:0] saved_margin;
    reg [31:0] saved_cycles;
    reg [7:0] saved_sequence;
    reg [1:0] tx_packet_count;
  localparam TX_IDLE=0, TX_SETUP=1, TX_WRITE=2, TX_NEXT=3;
  wire ml_busy, ml_result_valid, ml_result_accepted;
  wire [3:0] ml_result_digit;
  wire [7:0] ml_result_confidence;
  wire [15:0] ml_result_margin;
  wire [31:0] ml_result_cycles;
  assign FIFODATA = !SLWR ? fifo_out_data : 16'hzzzz;
  assign FIFOADR = (tx_state != TX_IDLE) ? 2'b10 : 2'b00;
  assign buzz = 1'b1;

  altsyncram #(
    .operation_mode("DUAL_PORT"), .width_a(4), .widthad_a(8), .numwords_a(256),
    .width_b(4), .widthad_b(8), .numwords_b(256),
    .outdata_reg_b("UNREGISTERED"), .lpm_type("altsyncram")
  ) frame_ram (
    .clock0(clk), .address_a(frame_ram_write_addr), .data_a(frame_ram_write_data),
    .wren_a(frame_ram_wren), .clock1(clk), .address_b(feed_index), .q_b(frame_ram_q)
  );

  ml_inference #(.CONFIDENCE_THRESHOLD(0), .MARGIN_THRESHOLD(0)) core_i (
    .clk(clk), .reset_n(rst), .clock_enable(ml_step),
    .input_frame_valid(ml_valid), .input_pixel_index(ml_pixel_index),
    .input_pixel(ml_pixel), .input_frame_last(ml_last), .input_frame_error(1'b0),
    .busy(ml_busy), .result_valid(ml_result_valid),
    .result_accepted(ml_result_accepted), .result_digit(ml_result_digit),
    .result_confidence(ml_result_confidence), .result_margin(ml_result_margin),
    .result_cycles(ml_result_cycles));

  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      rx_state<=RX_IDLE; rx_wait<=0; rx_count<=0;
      header_seen<=0; frame_ready<=0; feed_index<=0;
      rx_sequence<=0;
      SLOE<=1; SLRD<=1;
    end else begin
      SLOE<=1; SLRD<=1;
      case (rx_state)
        // PINFLAGSAB maps FLAGA to EP2 empty.  In the loaded FX2 firmware it
        // is high when OUT data is available.  Wait 32 CoreEP2C5 clock cycles
        // after the asynchronous flag transition before asserting SLRD/SLOE;
        // this avoids sampling the FX2 bus's idle pattern (0x5A5A).
        RX_IDLE: if (FLAGA && !frame_ready && !result_pending) begin
          rx_wait <= 0;
          rx_state <= RX_WAIT;
        end
        RX_WAIT: begin
          if (!FLAGA) rx_state <= RX_IDLE;
          else if (rx_wait == 6'd31) begin
            rx_wait <= 0;
            rx_state <= RX_LOW;
          end else rx_wait <= rx_wait + 1'b1;
        end
        RX_LOW: begin
          SLOE<=0; SLRD<=0;
          if (rx_wait == 6'd3) begin
            rx_wait <= 0;
            rx_state <= RX_CAPTURE;
          end else rx_wait <= rx_wait + 1'b1;
        end
        RX_CAPTURE: begin
          if (!header_seen && FIFODATA==16'hA5A5) begin header_seen<=1; rx_count<=0; rx_state<=RX_IDLE; end
          else if (header_seen && rx_count<98) begin
            rx_word <= FIFODATA;
            rx_state <= RX_STORE_LOW;
          end else rx_state<=RX_IDLE;
        end
        RX_STORE_LOW: begin
          if (rx_count == 0)
            rx_sequence <= {rx_word[15:12], rx_word[7:4]};
          rx_state <= RX_STORE_HIGH;
        end
        RX_STORE_HIGH: begin
            if (rx_count == 7'd97) begin
              frame_ready <= 1'b1;
              feed_index <= 0;
              header_seen <= 1'b0;
            end else rx_count <= rx_count + 1'b1;
          rx_state<=RX_IDLE;
        end
        default: rx_state<=RX_IDLE;
      endcase
      if (ml_step && frame_ready) begin
        if (feed_index == 8'd195) frame_ready <= 1'b0;
        else feed_index <= feed_index + 1'b1;
      end
    end
  end

  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      result_pending<=0; saved_digit<=0; saved_accepted<=0; saved_confidence<=0;
      saved_margin<=0; saved_cycles<=0; saved_sequence<=0;
      tx_state<=TX_IDLE; tx_index<=0;
      tx_packet_count<=0;
      tx_wait<=0;
      tx_word_reg<=0; SLWR<=1; fifo_out_data<=0; led<=4'b1111;
    end else begin
      SLWR<=1;
      if (ml_result_valid) begin
        result_pending<=1; saved_digit<=ml_result_digit; saved_accepted<=ml_result_accepted;
        saved_confidence<=ml_result_confidence; saved_margin<=ml_result_margin;
        saved_cycles<=ml_result_cycles; saved_sequence<=rx_sequence;
        led<=~ml_result_digit;
      end
      case (tx_state)
        // FLAGB is the original EP2 input-full flag in the board design.  It
        // is not the EP6 IN readiness flag, so it must not gate the result
        // packet transmission.
        TX_IDLE: if (result_pending) begin
          tx_index<=0; tx_packet_count<=0; tx_wait<=0; tx_word_reg<=16'hC33C;
          fifo_out_data<=16'hC33C; tx_state<=TX_SETUP;
        end
        TX_SETUP: begin
          fifo_out_data<=tx_word_reg;
          // FX2 asynchronous SLWR high time is 70 ns minimum.
          if (tx_wait==3) begin tx_wait<=0; tx_state<=TX_WRITE; end
          else tx_wait<=tx_wait+1'b1;
        end
        TX_WRITE: begin
          // CY7C68013A asynchronous SLWR low time is 50 ns minimum.
          // Three 50 MHz clocks provide one 60 ns write pulse.
          fifo_out_data<=tx_word_reg; SLWR<=0;
          if (tx_wait==2) begin tx_wait<=0; tx_state<=TX_NEXT; end
          else tx_wait<=tx_wait+1'b1;
        end
        TX_NEXT: if (tx_index==5) begin
                   if (tx_packet_count==1) begin
                     result_pending<=0; tx_state<=TX_IDLE;
                   end else begin
                     tx_packet_count<=tx_packet_count+1'b1;
                     tx_index<=0; tx_word_reg<=16'hC33C; tx_state<=TX_SETUP;
                   end
                 end
                 else begin
                   tx_index<=tx_index+1;
                   case (tx_index)
                     // Keep the six-word/24-byte response. The status word
                     // has unused bits, so carry the 8-bit transaction ID
                     // without changing the FX2 packet size.
                     0: tx_word_reg<={saved_sequence[7:4],3'b0,saved_accepted,
                                      saved_sequence[3:0],saved_digit};
                     1: tx_word_reg<={8'b0,saved_confidence};
                     2: tx_word_reg<=saved_margin;
                     3: tx_word_reg<=saved_cycles[15:0];
                     4: tx_word_reg<=saved_cycles[31:16];
                     default: tx_word_reg<=16'd0;
                   endcase
                   tx_state<=TX_SETUP;
                 end
        default: tx_state<=TX_IDLE;
      endcase
    end
  end
endmodule
