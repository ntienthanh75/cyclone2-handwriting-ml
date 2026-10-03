# Processing timing and throughput

This document records the measured timing of the SystemVerilog handwriting
recognizer running on the physical CoreEP2C5 Cyclone II board.

## Configuration

- FPGA clock: 50 MHz
- Clock period: 20 ns
- ML clock-enable step: approximately once every 9 FPGA clocks
- Input: one normalized 14×14, 4-bit grayscale frame
- Transport: CY7C68013A FX2 WinUSB, 99 16-bit words per input frame
- Output: six 16-bit result words in a 24-byte response packet

## FPGA processing speed

The result cycle counter measures ML clock-enable cycles. A normal inference
takes 13,412 enabled cycles:

```text
13,412 × 9 FPGA clocks / 50,000,000 clocks per second
  = 2.414 ms per image
```

Therefore the classifier core's theoretical processing rate is approximately:

```text
1 / 0.002414 = 414 images per second
```

The cycle counter is cumulative across frames. Differences of 26,824, 40,236,
or 67,060 cycles indicate missed/retried USB transactions, not a slower ML
calculation.

## Normal end-to-end transaction timing

For successful non-recovery transactions in the final benchmark:

| Statistic | Time |
|---|---:|
| Minimum | 2.941 ms |
| Median | 3.026 ms |
| Average | 3.066 ms |
| 95th percentile | 3.158 ms |
| Maximum normal transaction | 6.464 ms |

The median PC → FX2 → FPGA → FX2 → PC rate is approximately:

```text
1 / 0.003026 = 330 images per second
```

This includes USB transfer and host-side protocol handling, but not the
deliberate delay inserted between benchmark samples.

## Final 200-sample benchmark

Source: `artifacts/hardware_benchmark_200_final_fixed.csv`

| Metric | Result |
|---|---:|
| Samples requested | 200 |
| Accepted responses | 197 |
| Correct predictions | 187 |
| Accuracy overall | 93.50% |
| Accuracy among accepted responses | 94.92% |
| Recoveries | 44 |
| Unrecovered transport errors | 3 |
| Sum of per-sample measured transaction times | 103.913 s |
| Effective rate including recovery delays | 1.92 images/s |

The benchmark used a deliberate 0.75-second pause between samples. Therefore
the 1.92 images/second figure is not the maximum hardware throughput; it
includes recovery delays and is from the benchmark procedure. The practical
normal transaction rate is approximately 330 images/second, while the FPGA
classifier itself can process approximately 414 images/second.

## Quartus timing and resources

- Worst-case setup slack: +68.935 ns
- Worst-case hold slack: +0.499 ns
- Logic elements: 3,135 / 4,608 (68%)
- Registers: 800
- Memory bits: 56,912 / 119,808 (48%)
- DSP elements: 5

The design meets the 50 MHz timing requirement. The remaining performance
limitation is FX2/WinUSB recovery behavior, not the ML datapath timing.

