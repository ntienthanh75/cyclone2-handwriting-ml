// Two-stage Cyclone II clock conversion: 50 MHz board clock -> 40 MHz -> 8 MHz.
module ml_pll_two_stage (input wire inclk0, output wire c0);
  wire [5:0] pll40_clk;
  wire [5:0] pll8_clk;
  wire [1:0] inclk50 = {1'b0, inclk0};
  wire [1:0] inclk40 = {1'b0, pll40_clk[0]};
  assign c0 = pll8_clk[0];

  altpll pll40_i (
    .inclk(inclk50), .clk(pll40_clk), .activeclock(), .areset(1'b0), .clkbad(),
    .clkena(6'b111111), .clkloss(), .clkswitch(1'b0), .configupdate(1'b0),
    .enable0(), .enable1(), .extclk(), .extclkena(4'b1111), .fbin(1'b1),
    .fbmimicbidir(), .fbout(), .fref(), .icdrclk(), .locked(), .pfdena(1'b1),
    .phasecounterselect(4'b1111), .phasedone(), .phasestep(1'b1), .phaseupdown(1'b1),
    .pllena(1'b1), .scanaclr(1'b0), .scanclk(1'b0), .scanclkena(1'b1),
    .scandata(1'b0), .scandataout(), .scandone(), .scanread(1'b0), .scanwrite(1'b0),
    .sclkout0(), .sclkout1(), .vcooverrange(), .vcounderrange()
  );
  defparam
    pll40_i.clk0_divide_by = 5, pll40_i.clk0_duty_cycle = 50,
    pll40_i.clk0_multiply_by = 4, pll40_i.clk0_phase_shift = "0",
    pll40_i.compensate_clock = "CLK0", pll40_i.inclk0_input_frequency = 20000,
    pll40_i.intended_device_family = "Cyclone II",
    pll40_i.lpm_hint = "CBX_MODULE_PREFIX=ml_pll40", pll40_i.lpm_type = "altpll",
    pll40_i.operation_mode = "NORMAL", pll40_i.port_activeclock = "PORT_UNUSED",
    pll40_i.port_areset = "PORT_UNUSED", pll40_i.port_clkbad0 = "PORT_UNUSED",
    pll40_i.port_clkbad1 = "PORT_UNUSED", pll40_i.port_clkloss = "PORT_UNUSED",
    pll40_i.port_clkswitch = "PORT_UNUSED", pll40_i.port_configupdate = "PORT_UNUSED",
    pll40_i.port_fbin = "PORT_UNUSED", pll40_i.port_inclk0 = "PORT_USED",
    pll40_i.port_inclk1 = "PORT_UNUSED", pll40_i.port_locked = "PORT_UNUSED",
    pll40_i.port_pfdena = "PORT_UNUSED", pll40_i.port_phasecounterselect = "PORT_UNUSED",
    pll40_i.port_phasedone = "PORT_UNUSED", pll40_i.port_phasestep = "PORT_UNUSED",
    pll40_i.port_phaseupdown = "PORT_UNUSED", pll40_i.port_pllena = "PORT_UNUSED",
    pll40_i.port_scanaclr = "PORT_UNUSED", pll40_i.port_scanclk = "PORT_UNUSED",
    pll40_i.port_scanclkena = "PORT_UNUSED", pll40_i.port_scandata = "PORT_UNUSED",
    pll40_i.port_scandataout = "PORT_UNUSED", pll40_i.port_scandone = "PORT_UNUSED",
    pll40_i.port_scanread = "PORT_UNUSED", pll40_i.port_scanwrite = "PORT_UNUSED",
    pll40_i.port_clk0 = "PORT_USED", pll40_i.port_clk1 = "PORT_UNUSED",
    pll40_i.port_clk2 = "PORT_UNUSED", pll40_i.port_clk3 = "PORT_UNUSED",
    pll40_i.port_clk4 = "PORT_UNUSED", pll40_i.port_clk5 = "PORT_UNUSED",
    pll40_i.port_clkena0 = "PORT_UNUSED", pll40_i.port_clkena1 = "PORT_UNUSED",
    pll40_i.port_clkena2 = "PORT_UNUSED", pll40_i.port_clkena3 = "PORT_UNUSED",
    pll40_i.port_clkena4 = "PORT_UNUSED", pll40_i.port_clkena5 = "PORT_UNUSED",
    pll40_i.port_extclk0 = "PORT_UNUSED", pll40_i.port_extclk1 = "PORT_UNUSED",
    pll40_i.port_extclk2 = "PORT_UNUSED", pll40_i.port_extclk3 = "PORT_UNUSED";

  altpll pll8_i (
    .inclk(inclk40), .clk(pll8_clk), .activeclock(), .areset(1'b0), .clkbad(),
    .clkena(6'b111111), .clkloss(), .clkswitch(1'b0), .configupdate(1'b0),
    .enable0(), .enable1(), .extclk(), .extclkena(4'b1111), .fbin(1'b1),
    .fbmimicbidir(), .fbout(), .fref(), .icdrclk(), .locked(), .pfdena(1'b1),
    .phasecounterselect(4'b1111), .phasedone(), .phasestep(1'b1), .phaseupdown(1'b1),
    .pllena(1'b1), .scanaclr(1'b0), .scanclk(1'b0), .scanclkena(1'b1),
    .scandata(1'b0), .scandataout(), .scandone(), .scanread(1'b0), .scanwrite(1'b0),
    .sclkout0(), .sclkout1(), .vcooverrange(), .vcounderrange()
  );
  defparam
    pll8_i.clk0_divide_by = 5, pll8_i.clk0_duty_cycle = 50,
    pll8_i.clk0_multiply_by = 1, pll8_i.clk0_phase_shift = "0",
    pll8_i.compensate_clock = "CLK0", pll8_i.inclk0_input_frequency = 25000,
    pll8_i.intended_device_family = "Cyclone II",
    pll8_i.lpm_hint = "CBX_MODULE_PREFIX=ml_pll8", pll8_i.lpm_type = "altpll",
    pll8_i.operation_mode = "NORMAL", pll8_i.port_activeclock = "PORT_UNUSED",
    pll8_i.port_areset = "PORT_UNUSED", pll8_i.port_clkbad0 = "PORT_UNUSED",
    pll8_i.port_clkbad1 = "PORT_UNUSED", pll8_i.port_clkloss = "PORT_UNUSED",
    pll8_i.port_clkswitch = "PORT_UNUSED", pll8_i.port_configupdate = "PORT_UNUSED",
    pll8_i.port_fbin = "PORT_UNUSED", pll8_i.port_inclk0 = "PORT_USED",
    pll8_i.port_inclk1 = "PORT_UNUSED", pll8_i.port_locked = "PORT_UNUSED",
    pll8_i.port_pfdena = "PORT_UNUSED", pll8_i.port_phasecounterselect = "PORT_UNUSED",
    pll8_i.port_phasedone = "PORT_UNUSED", pll8_i.port_phasestep = "PORT_UNUSED",
    pll8_i.port_phaseupdown = "PORT_UNUSED", pll8_i.port_pllena = "PORT_UNUSED",
    pll8_i.port_scanaclr = "PORT_UNUSED", pll8_i.port_scanclk = "PORT_UNUSED",
    pll8_i.port_scanclkena = "PORT_UNUSED", pll8_i.port_scandata = "PORT_UNUSED",
    pll8_i.port_scandataout = "PORT_UNUSED", pll8_i.port_scandone = "PORT_UNUSED",
    pll8_i.port_scanread = "PORT_UNUSED", pll8_i.port_scanwrite = "PORT_UNUSED",
    pll8_i.port_clk0 = "PORT_USED", pll8_i.port_clk1 = "PORT_UNUSED",
    pll8_i.port_clk2 = "PORT_UNUSED", pll8_i.port_clk3 = "PORT_UNUSED",
    pll8_i.port_clk4 = "PORT_UNUSED", pll8_i.port_clk5 = "PORT_UNUSED",
    pll8_i.port_clkena0 = "PORT_UNUSED", pll8_i.port_clkena1 = "PORT_UNUSED",
    pll8_i.port_clkena2 = "PORT_UNUSED", pll8_i.port_clkena3 = "PORT_UNUSED",
    pll8_i.port_clkena4 = "PORT_UNUSED", pll8_i.port_clkena5 = "PORT_UNUSED",
    pll8_i.port_extclk0 = "PORT_UNUSED", pll8_i.port_extclk1 = "PORT_UNUSED",
    pll8_i.port_extclk2 = "PORT_UNUSED", pll8_i.port_extclk3 = "PORT_UNUSED";
endmodule
