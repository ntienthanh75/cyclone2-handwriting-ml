# Verification issues and lessons learned

This document records the problems encountered while moving the handwriting
inference reference from VHDL synthesis toward an all-SystemVerilog UVM flow.
It is intended as a troubleshooting and learning record, not as a list of
successful results only.

## Scope and baseline

The design targets the Waveshare/CoreEP2C5 board with FPGA device
`EP2C5T144C8`. The classifier interface accepts a streamed 14×14 frame (196
unsigned 4-bit pixels) and returns a digit, confidence, margin, acceptance
flag, and cycle count. The trained model is a `196 → 32 → 10` network with
signed quantized weights stored in Quartus MIF files.

## Issue log

| ID | Symptom | Root cause | Resolution | Status |
|---|---|---|---|---|
| I-001 | Quartus reported `Top-level design entity ... is undefined`. | The project/revision name did not match the HDL top-level entity or the source was not assigned. | Set the top-level entity explicitly and assign the correct HDL source in the QSF. | Resolved |
| I-002 | Quartus could not find `weights_l1.mif` and the other ROM files. | Relative MIF paths were interpreted from the Quartus project directory, not from the source-file location. | Corrected the initialization paths and verified that Quartus elaborated all four ROMs. | Resolved |
| I-003 | The first RTL implementation repeatedly used hidden neuron 0 in the output layer. | `O_SETUP` reset the neuron index every time, so the output MAC never visited hidden neurons 1–31. | Preserve the neuron index in `O_SETUP`; reset it only when starting a new output neuron. | Resolved in reference RTL |
| I-004 | Bias values could be from the previous ROM address. | The bias address and accumulator were updated in the same clock edge. | Present the ROM address in setup, then consume the settled ROM data in the following MAC cycle. | Resolved in reference RTL |
| I-005 | Quartus initially rejected VHDL syntax and arithmetic expressions. | Reserved state name, invalid `std_logic` conditions, unconstrained aggregates, and signed-width mismatches. | Renamed `REJECT`, used explicit `'1'` comparisons, fixed widths, and used explicit signed resizing. | Resolved |
| I-006 | Quartus compilation succeeded but timing failed. | The reference MAC has a wide combinational multiply/add path. | Recorded the timing result and kept this as a reference implementation. A frequency sweep showed 5 MHz passes, 8 MHz barely passes, and 10/20/50 MHz fail in the slow timing model. The next hardware optimization is pipelining or lowering the clock. | Open; use 5 MHz temporarily |
| I-007 | Many fitter warnings reported unassigned pins. | The reusable core has abstract input/output ports and no board-level pin map. | Added a separate smoke-build QSF and documented that it is not a board-ready image. | Expected for smoke build |
| I-008 | A mixed-language UVM simulation stopped with `ALTERA version supports only a single HDL`. | ModelSim-Altera 10.1d does not support a VHDL DUT with a SystemVerilog UVM testbench. | Added `rtl/ml_inference.sv` and changed the local UVM flow to all SystemVerilog. | Resolved for local simulator |
| I-009 | UVM simulation failed with a null DPI function pointer. | The legacy ModelSim-Altera UVM package calls optional DPI functions, but its DPI library was not loaded. | Compiled UVM with `UVM_NO_DPI`; this test does not need DPI. | Resolved for current smoke test |
| I-010 | ModelSim ignored the nested `-do` command and returned to a prompt. | `run.do` invoked `vsim` with another nested `-do` option. | Changed the script to load the design, then execute `run -all` and `quit -f` in the active simulation. | Resolved |
| I-011 | UVM reported `The run phase must start at time 0`. | The testbench held reset for several clock cycles before calling `run_test()`. | Call `run_test()` at time zero and release reset from a separate initial process. | Resolved |
| I-012 | ModelSim could not load MIF files during UVM simulation. | The simulation working directory is `verification/uvm`, while the original path was relative to `rtl`. | Used the correct path from the UVM working directory: `../../artifacts/*.mif`. | Resolved |
| I-013 | UVM produced a result for the all-zero smoke frame but confidence was zero. | The test intentionally sends an all-zero frame; it is a protocol/liveness test, not a classification-quality test. | Keep this test as a smoke test and add image vectors plus golden expected results next. | Expected; extension required |
| I-014 | Quartus reported truncation warnings for arithmetic-derived addresses and saturated outputs in SystemVerilog. | Unsized integer expressions were assigned to narrower signals. | The build still succeeds, but the expressions should be explicitly sized before production use. | Open cleanup item |
| I-015 | The UVM smoke test passed without proving the predicted digit is correct. | The scoreboard only checks that a nonzero-cycle result arrives. | Add a golden-reference transaction field generated by the Python quantized model and compare digit, acceptance, confidence range, and margin. | Open |
| I-016 | The RTL classifier is not yet proven numerically equivalent to Python. | The current RTL accumulation/scaling is a first hardware reference and has not completed cycle-accurate fixed-point matching. | Keep the Python quantized report as the reference and add directed vectors before LCD integration. | Open |
| I-017 | The generated `.sof` is not ready for physical-board use. | No board pin mapping, LCD wrapper, touch transport, or board-level reset/clock integration is included. | Keep synthesis and UVM as pre-integration milestones. Add a board wrapper only after numerical verification. | Open |

## Current verified state

- The SystemVerilog UVM smoke test runs on the installed ModelSim-Altera
  simulator with 0 UVM errors and 0 UVM fatals.
- The SystemVerilog Quartus project compiles for `EP2C5T144C8` with 0 errors.
- The VHDL reference project also compiles for `EP2C5T144C8` with 0 errors.
- The UVM smoke test result is a liveness/protocol result only; it is not an
  accuracy benchmark.
- Timing closure at 50 MHz, exact Python/RTL equivalence, board pin mapping,
  and LCD/USB integration are still open.

## Recommended order of future work

1. Replace the all-zero smoke frame with a small checked-in set of normalized
   digit vectors and expected Python outputs.
2. Extend the UVM sequence and scoreboard to compare the RTL digit and
   `NON_RECOGNIZABLE` decision with those golden outputs.
3. Fix the SystemVerilog width-truncation warnings explicitly.
4. Pipeline or simplify the MAC datapath and repeat timing analysis.
5. Add the board wrapper and real pin assignments only after the above tests
   pass.
6. Integrate LCD touch frames using the same 196-pixel classifier interface.

## Detailed diagnosis and resolution notes

### 1. Quartus says that the top-level entity is undefined

**Meaning.** Quartus successfully opened the project, but the name in
`TOP_LEVEL_ENTITY` does not match any entity/module compiled from the source
files. This is a project configuration problem, not an FPGA hardware fault.

**How to diagnose.** Read the first Analysis & Synthesis messages. A healthy
build contains a message such as `Found entity ml_inference` followed by
`Elaborating entity "ml_inference"`. If the error appears before elaboration,
check the source assignment and the top-level name.

**Resolution.** Set all three items consistently:

```text
TOP_LEVEL_ENTITY = ml_inference
source file      = ml_inference.vhd  or  ml_inference.sv
revision         = the intended Quartus revision
```

The principal project is now SystemVerilog: `ml_inference.sv` and
`ml_inference.qsf`. The VHDL source is retained only for legacy comparison;
`ml_inference_sv.qsf` remains as an explicitly named equivalent SV build.

**Prevention.** Always compile from the directory containing the matching QSF
and use the same revision name shown by Quartus:

```powershell
quartus_sh --flow compile ml_inference_sv
```

### 2. Quartus or ModelSim cannot find the MIF files

**Meaning.** The neural-network weights are external ROM initialization files.
The path is interpreted relative to the current tool/project context; it is
not automatically relative to the HDL source file.

**How to diagnose.** Look for `Can't find Memory Initialization File` in
Quartus or `Failed to open file ...mif` in ModelSim. A successful log also
shows the four ROM instances with the expected `init_file` values.

**Resolution.** Use paths appropriate to the tool's working directory:

- Quartus project in `D:\fpga\cyclone2-handwriting-ml\rtl`: use
  `../../artifacts/*.mif` in the SystemVerilog project.
- UVM simulation in `...\verification\uvm`: use the same
  `../../artifacts/*.mif` path from that simulation directory.

Do not copy a random MIF into the current directory to hide the problem. The
MIF must come from the current Python export, otherwise hardware and software
may use different weights.

**Prevention.** Regenerate the files with:

```powershell
$env:PYTHONPATH='D:\Programs\cyclone2_ml\python-libs;D:\fpga\cyclone2-handwriting-ml\python'
python D:\fpga\cyclone2-handwriting-ml\python\quantized_reference.py `
  --data D:\fpga\cyclone2-handwriting-ml\data\mnist `
  --artifacts D:\fpga\cyclone2-handwriting-ml\artifacts
```

Then verify that `metadata.json` and `quantized_report.json` correspond to the
same export before compiling RTL.

### 3. The output layer used the wrong hidden neuron

**Meaning.** The classifier could synthesize and run while silently computing
the wrong network. This is a functional RTL bug, not a Quartus warning.

**Root cause.** The original `O_SETUP` state assigned `neuron <= 0` on every
output-layer setup cycle. The next state therefore repeatedly multiplied
hidden neuron 0 instead of visiting neurons 0 through 31.

**Resolution.** Reset `neuron` only when starting a new output score. In the
output MAC loop, increment it from 0 to 31; after score 31, increment
`output_n` and reset `neuron` for the next digit.

**How to verify.** Add a directed test with a frame that causes at least two
hidden activations to differ. A test that only checks `result_valid` will not
detect this bug.

### 4. Bias values were sampled before the ROM address changed

**Meaning.** A synchronous state machine can update a ROM address and read the
old ROM data in the same clock edge. This creates a one-address or stale-bias
error that may look like random classification failure.

**Root cause.** The setup state both changed the bias address and copied the
current bias output into the accumulator. Nonblocking/register updates do not
make the new address data available until after the edge.

**Resolution.** Setup states now present the address and enter the MAC state.
The first MAC cycle consumes the settled ROM output and adds the bias; later
MAC cycles add products to the accumulator.

**Prevention.** Treat every memory access as a two-step operation:

```text
cycle N:   drive address
cycle N+1: consume data
```

This rule must also be applied if the ROM is later changed to registered
output, in which case an additional wait state may be required.

### 5. Compilation succeeds but 50 MHz timing fails

**Meaning.** Synthesis and fitting succeeded, but the placed-and-routed logic
cannot complete its longest path in one 20 ns clock period. This is different
from a syntax or programming-file error.

**Evidence.** TimeQuest reports approximately `-101.8 ns` worst-case setup
slack for the current reference design. Hold slack is positive, so the main
problem is setup delay.

**Root cause.** The reference implementation performs a wide signed multiply
and accumulator operation in one MAC cycle. The Cyclone II must route a large
arithmetic path at 50 MHz.

**Resolution options.**

1. Register/pipeline the multiplier and adder.
2. Use narrower, explicitly scaled fixed-point intermediates.
3. Time-multiplex a smaller arithmetic unit with a slower clock.
4. Lower the requested clock temporarily while validating functionality.

Do not call this timing-clean until TimeQuest reports non-negative setup and
hold slack for the intended board clock.

### 6. ModelSim-Altera rejects VHDL plus SystemVerilog UVM

**Meaning.** The simulator is not reporting a DUT bug. The Altera-bundled
ModelSim edition supports only a single HDL in this configuration.

**Evidence.** The mixed-language top level stops with:

```text
ALTERA version supports only a single HDL
```

**Resolution.** A SystemVerilog implementation of the DUT was added at
`rtl/ml_inference.sv` and made the principal RTL source. The UVM test now
compiles only SystemVerilog plus the Altera memory-function library. The VHDL
source is retained only as a separate legacy reference implementation.

**Alternative.** With Questa or ModelSim SE/PE, the original VHDL DUT can be
used with the SystemVerilog UVM environment by restoring the `vcom` step in
the simulator script.

### 7. UVM fails with a null DPI function pointer

**Meaning.** UVM 1.1c contains optional DPI-based command-line and HDL access
helpers. The legacy ModelSim-Altera installation did not provide the matching
DPI shared library.

**Resolution.** The local test compiles UVM with `UVM_NO_DPI`. This is safe for
the current driver, monitor, and scoreboard because they use virtual
interfaces and do not call UVM HDL/DPI helper functions.

**Limitation.** If later tests need UVM DPI features, use a simulator/library
combination that supplies the matching UVM DPI implementation instead of
silently ignoring the failure.

### 8. UVM run phase started at a nonzero simulation time

**Meaning.** UVM requires `run_test()` to be called at simulation time zero;
otherwise its run phase may already be considered late.

**Root cause.** The top-level testbench waited four clock edges for reset and
only then called `run_test()`.

**Resolution.** The testbench now calls `run_test()` immediately at time zero.
Reset is initialized low in the same time-zero process and released from a
separate process after four clocks.

### 9. UVM script compiled but did not actually run the test

**Meaning.** A nested `vsim -do` inside an already running `vsim` session was
ignored by ModelSim-Altera. Compilation appeared successful, but no reliable
test result was produced.

**Resolution.** `run.do` now performs these operations in one active session:

```text
compile libraries and sources
vsim tb_top
run -all
quit -f
```

The current verified result is a real UVM report with 0 errors and 0 fatals,
not merely a successful source compilation.

### 10. A smoke test passed without proving digit accuracy

**Meaning.** The UVM smoke test only proves that a complete frame is accepted
and that the DUT eventually emits `result_valid` with a nonzero cycle count.
It does not prove that the digit is correct.

**Resolution required.** Add a vector transaction containing 196 normalized
pixels and the expected result generated by `quantized_reference.py`. The
scoreboard must compare:

- predicted digit;
- accepted versus `NON_RECOGNIZABLE` decision;
- confidence and margin bounds;
- completion-cycle bound.

Only after those checks pass should the core be connected to LCD touch input.

### 11. SystemVerilog width-truncation warnings

**Meaning.** Quartus reports that unsized integer expressions are being
truncated into address or output fields. The build succeeds, but relying on
implicit truncation is unsafe.

**Resolution required.** Replace implicit expressions with explicitly sized
casts or bounded counters, for example:

```systemverilog
wire [12:0] l1_addr = 13'(neuron * 196 + pixel_idx);
```

The exact cast syntax should be checked against the Quartus 13.0 SystemVerilog
subset before committing the cleanup. The warning must be removed before
using the SystemVerilog core as the production implementation.

## Reproduction commands

From the UVM directory:

```powershell
cd D:\fpga\cyclone2-handwriting-ml\verification\uvm
& 'D:\Program\altera\13.0sp1\modelsim_ase\win32aloem\vsim.exe' -c -do run.do
```

From the RTL directory:

```powershell
cd D:\fpga\cyclone2-handwriting-ml\rtl
& 'D:\Program\altera\13.0sp1\quartus\bin64\quartus_sh.exe' --flow compile ml_inference_sv
```

The frequency experiment and measured setup/hold slack are documented in
[`rtl/synthesis/frequency_sweep/README.md`](../rtl/synthesis/frequency_sweep/README.md).

The register/combinational-path comparison is documented in
[`rtl/synthesis/pipeline_versions/README.md`](../rtl/synthesis/pipeline_versions/README.md).
