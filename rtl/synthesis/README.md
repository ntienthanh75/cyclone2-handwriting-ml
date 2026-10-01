# Synthesis results archive

This directory is a permanent reference archive. Do not delete or overwrite
the result folders when running a new experiment; create a new named folder
or project revision instead.

## Reference sets

| Set | Location | Purpose |
|---|---|---|
| Principal SystemVerilog build | `../ml_inference.*.rpt` and `../ml_inference.sof` | Current default RTL synthesis for `EP2C5T144C8` |
| Frequency sweep | `frequency_sweep/` | 5, 8, 10, and 20 MHz SDC-constrained builds; 50 MHz is recorded from the principal build |
| Pipeline comparison | `pipeline_versions/` | Baseline comparison against Pipe2 and Pipe3 register experiments at 10 MHz |

Each experiment must retain, when generated:

- the `.qsf` project configuration;
- the `.sdc` timing constraint;
- the source revision used;
- `.map.rpt`, `.fit.rpt`, `.sta.rpt`, and `.flow.rpt` reports;
- the `.sof` file when assembly succeeds;
- a README explaining the result and any warnings.

## Current reference numbers

The principal SystemVerilog build uses approximately 4,078 fitted logic
elements, 985 registers, 56,880 memory bits, and 9 DSP elements. At 50 MHz it
has approximately `-101.821 ns` slow-corner setup slack.

The frequency result table is maintained in
`frequency_sweep/README.md`. The register tradeoff table is maintained in
`pipeline_versions/README.md`.

## Consolidated decision record

All values below are final fitter/timing results for the same
`EP2C5T144C8` device and the same generated MIF weights. Setup slack is from
the slow Cyclone II timing model; a negative value means the design misses the
requested period.

### Frequency sweep: baseline ML core

| Frequency | Logic elements | Slow setup slack | Slow hold slack | Decision |
|---:|---:|---:|---:|---|
| 5 MHz | 4,188 | +76.426 ns | +0.499 ns | Safe timing margin |
| 8 MHz | 4,092 | +1.438 ns | +0.499 ns | Smallest standalone baseline that passes |
| 10 MHz | 4,078 | -32.507 ns | +0.499 ns | Fails setup |
| 20 MHz | 4,078 | -69.922 ns | +0.499 ns | Fails setup |
| 50 MHz | 4,078 | -101.821 ns | +0.499 ns | Fails setup |

### Register/combinational-path options

| Frequency | Version | Logic elements | Registers | Slow setup slack | Approx. latency |
|---:|---|---:|---:|---:|---:|
| 8 MHz | Baseline | 4,092 | 985 | +1.438 ns | 13,408 cycles |
| 8 MHz | Pipe2 | 4,109 | 1,051 | +1.039 ns | about 20,000 cycles |
| 8 MHz | Pipe3 | 4,094 | 1,061 | +5.015 ns | about 26,500 cycles |
| 10 MHz | Baseline | 4,078 | 985 | -32.507 ns | 13,408 cycles |
| 10 MHz | Pipe2 | 4,061 | 1,051 | -18.246 ns | about 20,000 cycles |
| 10 MHz | Pipe3 | 4,050 | 1,061 | -17.798 ns | about 26,500 cycles |

At 8 MHz, Pipe3 has the best timing margin, but it uses 76 more registers
than the baseline and has greater latency. The baseline is therefore the
smallest and simplest standalone ML implementation that passes timing. At
10 MHz, adding these registers is not enough to close timing; a deeper MAC
redesign would be required.

### Why two frequencies are recorded

The standalone ML-core reference uses **8 MHz** because it passes timing with
the fewest registers among the tested options. The PC-to-FPGA FX2 streaming
wrapper uses a **5 MHz clock-enable rate** because it is the conservative
hardware integration point: it gives a large timing margin while the 50 MHz
board clock services the USB FIFO. This is not a claim that the core needs a
5 MHz clock; it is the selected safe rate for the first physical USB test.

The current downloadable FX2 wrapper result is archived in
`../fx2_ml_bridge/`. Its final fitted result uses 4,278 logic elements and
has +73.997 ns setup slack and +0.499 ns hold slack at the 5 MHz ML enable
rate. The FX2 wrapper streams pixels directly and does not use the LCD path.

The complete source projects, Quartus reports, SDC files, and generated SOF
files remain in `frequency_sweep/` and `pipeline_versions/`; these folders are
the permanent comparison reference and must not be overwritten.

## Archive rule

New experiments should use a unique descriptive name, for example:

```text
synthesis/pipeline_versions/pipe2_8mhz_after_width_fix/
```

Never replace an older report with a newer run unless the README explicitly
records that it is a deliberate rebaseline. This keeps timing and resource
comparisons reproducible.
