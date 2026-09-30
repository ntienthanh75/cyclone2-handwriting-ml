`timescale 1ns/1ps
module tb_top;
  import uvm_pkg::*; import ml_inference_pkg::*;
  logic clk=0; always #10 clk=~clk; ml_inference_if vif(clk);
  ml_inference dut(.clk(clk),.reset_n(vif.reset_n),.input_frame_valid(vif.input_frame_valid),.input_pixel_index(vif.input_pixel_index),.input_pixel(vif.input_pixel),.input_frame_last(vif.input_frame_last),.input_frame_error(vif.input_frame_error),.busy(vif.busy),.result_valid(vif.result_valid),.result_accepted(vif.result_accepted),.result_digit(vif.result_digit),.result_confidence(vif.result_confidence),.result_margin(vif.result_margin),.result_cycles(vif.result_cycles));
  initial begin vif.reset_n=0; uvm_config_db#(virtual ml_inference_if)::set(null,"*","vif",vif); run_test("ml_smoke_test"); end
  initial begin repeat(4) @(posedge clk); vif.reset_n=1; end
endmodule
