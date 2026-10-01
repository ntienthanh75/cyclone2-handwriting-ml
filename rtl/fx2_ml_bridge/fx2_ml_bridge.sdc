create_clock -name clk -period 20.000 [get_ports {clk}]
set_multicycle_path -setup 10 -from [get_clocks {clk}] -to [get_clocks {clk}]
set_multicycle_path -hold 9 -from [get_clocks {clk}] -to [get_clocks {clk}]
