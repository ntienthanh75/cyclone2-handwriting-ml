interface ml_inference_if(input logic clk);
  logic reset_n;
  logic input_frame_valid;
  logic [7:0] input_pixel_index;
  logic [3:0] input_pixel;
  logic input_frame_last;
  logic input_frame_error;
  logic busy;
  logic result_valid;
  logic result_accepted;
  logic [3:0] result_digit;
  logic [7:0] result_confidence;
  logic [15:0] result_margin;
  logic [31:0] result_cycles;
endinterface
