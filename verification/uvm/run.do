transcript on
if {[file exists work]} { vdel -lib work -all }
vlib work
set UVM_ROOT "D:/Program/altera/13.0sp1/modelsim_ase/verilog_src/uvm-1.1c/src"
vlog -sv +define+UVM_NO_DPI +incdir+$UVM_ROOT "$UVM_ROOT/uvm_pkg.sv"
vlog -sv "D:/Program/altera/13.0sp1/modelsim_ase/altera/verilog/src/altera_mf.v"
vlog -sv +define+UVM_NO_DPI +incdir+$UVM_ROOT ../../rtl/ml_inference.sv ml_inference_if.sv ml_inference_pkg.sv tb_top.sv
vsim -t 1ps -L work tb_top
run -all
quit -f
