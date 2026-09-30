# UVM verification

This directory verifies the SystemVerilog `rtl/ml_inference.sv` with
SystemVerilog UVM. It uses the ModelSim-Altera UVM 1.1c package installed with Quartus II
13.0.1. The environment contains a sequence, driver, monitor, scoreboard,
environment, and smoke test. The first test streams an all-zero 14×14 frame
and checks that the DUT produces a nonzero-cycle result within a bounded time.

The UVM sources compile with the installed tools, but ModelSim-Altera 10.1d
cannot elaborate a mixed VHDL/SystemVerilog top level. The testbench therefore
uses the all-SystemVerilog DUT. The original mixed-language attempt stopped
with:

```text
ALTERA version supports only a single HDL
```

The smoke test therefore requires Questa or ModelSim SE/PE. Run from this
directory with a mixed-language-capable `vsim`:

```powershell
vsim -c -do run.do
```

The current run is single-language SystemVerilog: the simulator compiles the
DUT and UVM testbench with `vlog`. Golden digit checks will be added after the
RTL fixed-point arithmetic is made numerically equivalent to
`python/quantized_reference.py`.

With the current `run.do`, ModelSim-Altera runs the all-SystemVerilog DUT and
UVM smoke test successfully: 0 UVM errors, 0 UVM fatals, and one result at
13,408 DUT cycles. The result is a protocol/liveness check only; digit-level
golden checking is the next verification extension.

The UVM flow now uses the all-SystemVerilog implementation
`rtl/ml_inference.sv`, because ModelSim-Altera cannot mix VHDL and
SystemVerilog. The original VHDL reference remains available for comparison.
