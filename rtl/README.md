# RTL inference core

`ml_inference.sv` is the primary reusable classifier boundary. It accepts one
14×14 frame as 196 streamed unsigned 4-bit pixels, then evaluates the
`196 -> 32 -> 10` network using sequential MAC operations and the exported
Quartus ROM files in `artifacts/`.

The VHDL file `ml_inference.vhd` is retained only as a legacy comparison
reference. New synthesis, simulation, and verification work must use the
SystemVerilog source. The core is not yet connected to LCD touch or the USB
protocol. The principal project targets `EP2C5T144C8` at 8 MHz. The next
verification step is a deterministic UVM test that compares its result with
`quantized_reference.py`.

## Verified smoke build

The project was compiled with Quartus II 13.0.1 SP1 from this directory:

```powershell
cd D:\fpga\cyclone2-handwriting-ml\rtl
& 'D:\Program\altera\13.0sp1\quartus\bin64\quartus_sh.exe' --flow compile ml_inference
```

Result: full compilation succeeded with 0 errors and 15 warnings. The output
programming file is `ml_inference.sof` in this directory. The build confirms
that the VHDL, ROM initialization files, target device, fitter, assembler,
and SDC file are accepted by the installed Quartus toolchain.

The smoke build intentionally leaves inference-result pins unassigned because
the core is a reusable block, not yet a board-level design. Quartus therefore
reports unassigned-pin warnings. It also reports negative setup slack at the
requested 50 MHz clock (worst-case slow slack about -101.763 ns). This is an
expected first-reference limitation: the current MAC uses a wide combinational
multiply/add path. It must be pipelined or clocked more slowly before using
this core as a timing-clean board image.

The generated `.sof` is not yet ready to program the physical board: no board
pin mapping or LCD transport wrapper has been added, and the RTL arithmetic
still needs cycle-accurate comparison against the Python quantized reference.

## SystemVerilog primary implementation

`ml_inference.sv` is the project’s principal RTL source. The default Quartus
project is now `ml_inference.qsf`; `ml_inference_sv.qsf` is retained as an
explicitly named equivalent build configuration:

```powershell
cd D:\fpga\cyclone2-handwriting-ml\rtl
& 'D:\Program\altera\13.0sp1\quartus\bin64\quartus_sh.exe' --flow compile ml_inference
```

The SystemVerilog build completed full compilation with 0 errors for
`EP2C5T144C8`, producing `ml_inference.sof`. It has the same unresolved
50 MHz timing result (about `-101.821 ns` worst-case setup slack), so it is a
verification/synthesis milestone, not yet a board-ready image.

The measured clock sweep is documented in
`synthesis/frequency_sweep/README.md`: 5 MHz passes with comfortable margin,
8 MHz barely passes, and 10 MHz or higher fails the slow timing model.

The register tradeoff experiment is documented in
`synthesis/pipeline_versions/README.md`. Pipe2 is the recommended next
optimization candidate, but neither experimental pipeline is principal yet
because golden-vector verification is still required.

All generated synthesis reports and programming files are retained under
`synthesis/`. See `synthesis/README.md` for the archive structure and rules
for adding future comparison runs.
