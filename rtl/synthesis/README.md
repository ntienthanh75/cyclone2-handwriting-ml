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

## Archive rule

New experiments should use a unique descriptive name, for example:

```text
synthesis/pipeline_versions/pipe2_8mhz_after_width_fix/
```

Never replace an older report with a newer run unless the README explicitly
records that it is a deliberate rebaseline. This keeps timing and resource
comparisons reproducible.
