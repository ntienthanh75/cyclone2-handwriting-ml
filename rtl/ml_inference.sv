// Single-HDL SystemVerilog implementation of the reusable inference core.
// This keeps the VHDL interface and state-machine contract, while allowing
// ModelSim-Altera UVM verification without mixed-language simulation.
module ml_inference #(
  parameter integer CONFIDENCE_THRESHOLD = 0,
  parameter integer MARGIN_THRESHOLD = 0
) (
  input  wire        clk,
  input  wire        reset_n,
  input  wire        clock_enable,
  input  wire        input_frame_valid,
  input  wire [7:0]  input_pixel_index,
  input  wire [3:0]  input_pixel,
  input  wire        input_frame_last,
  input  wire        input_frame_error,
  output wire        busy,
  output reg         result_valid,
  output reg         result_accepted,
  output reg  [3:0]  result_digit,
  output reg  [7:0]  result_confidence,
  output reg  [15:0] result_margin,
  output reg  [31:0] result_cycles
);
  localparam IDLE=0, LOAD=1, H_SETUP=2, H_MAC=3, H_NEXT=4,
             O_SETUP=5, O_MAC=6, FINISH=7, REJECT_FRAME=8;
  reg [3:0] state;
  reg [7:0] input_mem [0:195];
  reg signed [63:0] hidden [0:31];
  reg signed [63:0] scores [0:9];
  integer pixel_idx, neuron, output_n, i;
  reg signed [63:0] acc, product, next_acc, margin_v, scan_best, scan_second;
  reg [3:0] scan_digit;
  reg [31:0] cycle_ctr;

  wire [12:0] l1_addr = neuron * 196 + pixel_idx;
  wire [8:0]  l2_addr = output_n * 32 + neuron;
  wire [5:0]  b1_addr = neuron;
  wire [3:0]  b2_addr = output_n;
  wire [7:0] l1_data, l2_data;
  wire [31:0] b1_data, b2_data;

  altsyncram #(.operation_mode("ROM"),.width_a(8),.widthad_a(13),.numwords_a(6272),.outdata_reg_a("UNREGISTERED"),.init_file("../../artifacts/weights_l1.mif"),.lpm_type("altsyncram")) l1_rom (.clock0(clk),.address_a(l1_addr),.q_a(l1_data));
  altsyncram #(.operation_mode("ROM"),.width_a(8),.widthad_a(9),.numwords_a(320),.outdata_reg_a("UNREGISTERED"),.init_file("../../artifacts/weights_l2.mif"),.lpm_type("altsyncram")) l2_rom (.clock0(clk),.address_a(l2_addr),.q_a(l2_data));
  altsyncram #(.operation_mode("ROM"),.width_a(32),.widthad_a(6),.numwords_a(32),.outdata_reg_a("UNREGISTERED"),.init_file("../../artifacts/bias_l1.mif"),.lpm_type("altsyncram")) b1_rom (.clock0(clk),.address_a(b1_addr),.q_a(b1_data));
  altsyncram #(.operation_mode("ROM"),.width_a(32),.widthad_a(4),.numwords_a(10),.outdata_reg_a("UNREGISTERED"),.init_file("../../artifacts/bias_l2.mif"),.lpm_type("altsyncram")) b2_rom (.clock0(clk),.address_a(b2_addr),.q_a(b2_data));

  assign busy = (state != IDLE && state != FINISH && state != REJECT_FRAME);

  always @(posedge clk) begin
    result_valid <= 1'b0;
    if (!reset_n) begin
      state <= IDLE; cycle_ctr <= 0; result_accepted <= 0;
      result_digit <= 0; result_confidence <= 0; result_margin <= 0; result_cycles <= 0;
      pixel_idx <= 0; neuron <= 0; output_n <= 0; acc <= 0;
    end else if (clock_enable) begin
      if (state != IDLE) cycle_ctr <= cycle_ctr + 1;
      case (state)
        IDLE: begin
          if (input_frame_error) state <= REJECT_FRAME;
          else if (input_frame_valid) begin
            input_mem[input_pixel_index] <= input_pixel;
            if (input_frame_last || input_pixel_index == 195) begin neuron<=0; pixel_idx<=0; state<=H_SETUP; end
            else state <= LOAD;
          end
        end
        LOAD: begin
          if (input_frame_valid) begin
            input_mem[input_pixel_index] <= input_pixel;
            if (input_frame_last || input_pixel_index == 195) begin neuron<=0; pixel_idx<=0; state<=H_SETUP; end
          end
        end
        H_SETUP: begin state <= H_MAC; end
        H_MAC: begin
          product = $signed({1'b0,input_mem[pixel_idx]}) * $signed(l1_data);
          if (pixel_idx == 0) next_acc = $signed(b1_data) + product; else next_acc = acc + product;
          if (pixel_idx == 195) begin
            if (next_acc < 0) hidden[neuron] <= 0; else hidden[neuron] <= next_acc;
            state <= H_NEXT;
          end else begin acc <= next_acc; pixel_idx <= pixel_idx + 1; state <= H_SETUP; end
        end
        H_NEXT: begin
          if (neuron == 31) begin output_n<=0; neuron<=0; state<=O_SETUP; end
          else begin neuron<=neuron+1; pixel_idx<=0; state<=H_SETUP; end
        end
        O_SETUP: begin state <= O_MAC; end
        O_MAC: begin
          product = hidden[neuron] * $signed(l2_data);
          if (neuron == 0) next_acc = $signed(b2_data) + product; else next_acc = acc + product;
          if (neuron == 31) begin
            scores[output_n] <= next_acc;
            if (output_n == 9) state <= FINISH;
            else begin output_n<=output_n+1; neuron<=0; state<=O_SETUP; end
          end else begin acc<=next_acc; neuron<=neuron+1; state<=O_SETUP; end
        end
        FINISH: begin
          scan_best = scores[0]; scan_second = scores[1]; scan_digit = 0;
          for (i=1; i<10; i=i+1) begin
            if (scores[i] > scan_best) begin scan_second=scan_best; scan_best=scores[i]; scan_digit=i[3:0]; end
            else if (scores[i] > scan_second) scan_second=scores[i];
          end
          margin_v = scan_best - scan_second;
          result_digit <= scan_digit;
          result_confidence <= (scan_best < 0) ? 0 : (scan_best > 255 ? 255 : scan_best[7:0]);
          result_margin <= (margin_v < 0) ? 0 : (margin_v > 65535 ? 65535 : margin_v[15:0]);
          result_accepted <= (scan_best >= CONFIDENCE_THRESHOLD && margin_v >= MARGIN_THRESHOLD);
          result_cycles <= cycle_ctr; result_valid <= 1; state <= IDLE;
        end
        REJECT_FRAME: begin result_accepted<=0; result_digit<=0; result_confidence<=0; result_margin<=0; result_cycles<=cycle_ctr; result_valid<=1; state<=IDLE; end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
