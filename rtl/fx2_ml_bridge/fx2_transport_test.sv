module fx2_transport_test (
  input wire clk, input wire rst, input wire FLAGA, input wire FLAGB,
  input wire FLAGC, output reg SLOE, output reg SLRD,
  output wire [1:0] FIFOADR, output reg SLWR,
  inout wire [15:0] FIFODATA, output reg [3:0] led, output wire buzz
);
  localparam RX_IDLE=0, RX_CAPTURE=1;
  localparam TX_IDLE=0, TX_SETUP=1, TX_WRITE=2, TX_NEXT=3;
  reg rx_state, got_header;
  reg [1:0] tx_state;
  reg [2:0] rx_wait, tx_wait;
  reg [2:0] tx_index;
  reg tx_pending;
  reg [15:0] tx_data;
  reg [15:0] out_word;

  // Transport isolation mode: select EP2 continuously and keep the FX2
  // read path enabled so any OUT packet is drained without ML or TX logic.
  assign FIFOADR = 2'b00;
  assign FIFODATA = 16'hzzzz;
  assign buzz = 1'b1;

  always @(posedge clk or negedge rst) begin
    if (!rst) begin
      rx_state<=RX_IDLE; rx_wait<=0; got_header<=0;
      SLOE<=1; SLRD<=1; tx_pending<=0; led<=4'b1111;
      tx_state<=TX_IDLE; tx_wait<=0; tx_index<=0; tx_data<=0; out_word<=0; SLWR<=1;
    end else begin
      SLOE<=1; SLRD<=1; SLWR<=1;
      case (rx_state)
        RX_IDLE: if (FLAGA) begin SLOE<=0; SLRD<=0; rx_wait<=0; rx_state<=RX_CAPTURE; end
        RX_CAPTURE: begin
          SLOE<=0; SLRD<=0;
          if (rx_wait==2) begin
            if (FIFODATA==16'hA5A5) begin tx_pending<=1; led<=4'b1010; end
            rx_wait<=0; rx_state<=RX_IDLE;
          end else rx_wait<=rx_wait+1'b1;
        end
        default: rx_state<=RX_IDLE;
      endcase
      case (tx_state)
        TX_IDLE: if (tx_pending) begin
          tx_pending<=0; tx_index<=0; tx_wait<=0; tx_data<=16'h5A5A;
          out_word<=16'h5A5A; tx_state<=TX_SETUP;
        end
        TX_SETUP: begin
          out_word<=tx_data;
          if (tx_wait==3) begin tx_wait<=0; tx_state<=TX_WRITE; end
          else tx_wait<=tx_wait+1'b1;
        end
        TX_WRITE: begin
          out_word<=tx_data; SLWR<=0;
          if (tx_wait==2) begin tx_wait<=0; tx_state<=TX_NEXT; end
          else tx_wait<=tx_wait+1'b1;
        end
        TX_NEXT: begin
          if (tx_index==5) tx_state<=TX_IDLE;
          else begin
            tx_index<=tx_index+1'b1; tx_wait<=0; tx_state<=TX_SETUP;
            case (tx_index)
              0: tx_data<=16'h1234;
              1: tx_data<=16'h5678;
              2: tx_data<=16'h9ABC;
              3: tx_data<=16'h1111;
              4: tx_data<=16'h2222;
              default: tx_data<=16'h0000;
            endcase
          end
        end
        default: tx_state<=TX_IDLE;
      endcase
    end
  end
endmodule
