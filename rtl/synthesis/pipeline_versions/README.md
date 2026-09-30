# Register/combinational-path comparison

This experiment compares the principal baseline against two SystemVerilog
variants on the same `EP2C5T144C8` target and the same MIF weights. The table
below is the apples-to-apples comparison: all three were freshly synthesized
and fitted with the same 5 MHz slow timing constraint (200 ns period).

The earlier table below is retained as the historical 10 MHz comparison.

| Version | Arithmetic structure | Slow setup slack at 10 MHz | Hold slack | Logic elements | Registers | Approx. latency |
|---|---|---:|---:|---:|---:|---:|
| Baseline | ROM → multiply → accumulator add in one MAC cycle | -32.507 ns | +0.499 ns | 4,078 | 985 | 13,408 cycles |
| Pipe2 | ROM → multiplier register → accumulator add | -18.246 ns | +0.499 ns | 4,061 | 1,051 | about 20,000 cycles |
| Pipe3 | ROM/read register → multiplier register → accumulator add | -17.798 ns | +0.499 ns | 4,050 | 1,061 | about 26,500 cycles |

## Same-constraint 5 MHz comparison

| Version | Slow setup slack | Hold slack | Logic elements | Registers | Memory bits | DSP elements |
|---|---:|---:|---:|---:|---:|---:|
| Baseline | +76.426 ns | +0.499 ns | 4,188 | 985 | 56,880 | 9 |
| Pipe2 | +72.153 ns | +0.499 ns | 4,207 | 1,051 | 56,880 | 9 |
| Pipe3 | +71.355 ns | +0.499 ns | 4,188 | 1,061 | 56,880 | 9 |

At 5 MHz, all three versions pass timing. Pipe3 ties the baseline for logic
elements, but uses 76 more registers. Pipe2 uses 19 more logic elements and
66 more registers than the baseline. Therefore the baseline is the smallest
and simplest 5 MHz implementation; Pipe2 and Pipe3 do not provide a useful
resource advantage at this frequency.

All three versions use 9 DSP elements. Pipe2 and Pipe3 improve setup slack by
about 14 ns, but neither reaches timing closure at 10 MHz. Pipe3 improves
Pipe2 by only 0.448 ns while adding another state and more latency.

## Decision

Do not promote either experiment to principal RTL yet. The current tradeoff is:

- use the baseline at 8 MHz for the selected implementation;
- use Pipe2 as the next optimization candidate because it captures most of
  the timing improvement with less latency than Pipe3;
- use Pipe3 only if a critical-path report proves the ROM-to-multiply boundary
  is the dominant limitation.

Neither pipeline has passed golden-vector UVM comparison yet. Before hardware
use, verify numerical equivalence and then repeat the frequency sweep. The
next high-value optimization is an explicitly bounded fixed-point accumulator
and a registered Cyclone II DSP output, rather than adding arbitrary general
purpose registers.

The experimental source files are `ml_inference_pipe2.sv` and
`ml_inference_pipe3.sv` in this directory. The archived 5 MHz projects and
reports are in `baseline_5mhz`, `pipe2_5mhz`, and `pipe3_5mhz`.

## Same-constraint 8 MHz and 10 MHz comparison

These six builds use identical project structure, device, MIF files, and
frequency-specific SDC constraints. Resource counts are final fitter counts.

| Frequency | Version | Setup slack | Hold slack | Logic elements | Registers | Memory bits | DSP |
|---|---|---:|---:|---:|---:|---:|---:|
| 8 MHz | Baseline | +1.438 ns | +0.499 ns | 4,092 | 985 | 56,880 | 9 |
| 8 MHz | Pipe2 | +1.039 ns | +0.499 ns | 4,109 | 1,051 | 56,880 | 9 |
| 8 MHz | Pipe3 | +5.015 ns | +0.499 ns | 4,094 | 1,061 | 56,880 | 9 |
| 10 MHz | Baseline | -32.507 ns | +0.499 ns | 4,078 | 985 | 56,880 | 9 |
| 10 MHz | Pipe2 | -18.246 ns | +0.499 ns | 4,061 | 1,051 | 56,880 | 9 |
| 10 MHz | Pipe3 | -17.798 ns | +0.499 ns | 4,050 | 1,061 | 56,880 | 9 |

At 8 MHz all three pass timing, but the baseline has the fewest registers and
Pipe3 has the largest timing margin. At 10 MHz all three fail setup timing;
Pipe3 is slightly better than Pipe2, and the baseline is worst. The fitter
uses different logic-element counts at different timing constraints because
Quartus changes optimization and placement, so resource counts must always be
compared at the same frequency constraint.

## Final selection

The selected implementation for the current Cyclone II target is the
**baseline SystemVerilog design at 8 MHz**:

- setup slack: `+1.438 ns`
- hold slack: `+0.499 ns`
- logic elements: `4,092`
- registers: `985`
- memory bits: `56,880`
- DSP elements: `9`

This is the preferred balance of timing closure, low register usage, and
implementation simplicity. Pipe3 has more timing margin at 8 MHz, but uses 76
more registers and adds latency. None of the three versions closes timing at
10 MHz.

## Next step

1. Make the principal Quartus project use the baseline 8 MHz SDC constraint.
2. Re-run the SystemVerilog/UVM golden-vector test against the selected RTL.
3. Compile the final 8 MHz project and confirm the timing report.
4. Program the generated SOF to the EP2C5 board and perform a hardware smoke
   test with one known digit and one non-recognizable input.

The 5 MHz, 8 MHz, and 10 MHz projects and reports remain archived in this
directory for future comparison.
