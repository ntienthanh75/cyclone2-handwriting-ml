# Cyclone II Handwriting ML

Specification for a reusable photo-to-digit FPGA inference project that recognizes handwritten digits `0–9` or returns `NON_RECOGNIZABLE` on the shared Waveshare/CoreEP2C5 Cyclone II board. SystemVerilog is the principal RTL language for this project.

Read [SPEC.md](SPEC.md) and the shared [board specification](https://github.com/ntienthanh75/fpga-cyclone2-5led/blob/main/docs/board-spec.md) before implementation. The canonical board specification covers the CoreEP2C5 connections to the LCD/touch module, SDRAM board, CY7C68013A FX2 USB FIFO, USB-Blaster/JTAG, LEDs, buzzer, clock, and reset. The local `BOARD_SPEC.md` is only a compatibility pointer. The first phase is PC photo normalization, training, and benchmarking with MNIST; the FPGA phase will implement reusable quantized inference. LCD touch and photo input must share the same classifier interface.

## PC baseline completed

`python/train.py` now downloads MNIST, trains the `196 → 32 → 10` reference
MLP, calibrates rejection thresholds on a held-out validation split, reports a
confusion matrix, and exports quantized weights and metadata.

Latest baseline run:

| Metric | Result |
|---|---:|
| Floating-point test accuracy | 89.72% |
| Accepted coverage | 88.91% |
| Accuracy among accepted frames | 94.66% |

The dataset is kept locally under `data/mnist/` and is not part of the source
artifact. Exported files are under `artifacts/`. NumPy and Pillow are installed
under `D:\Programs\cyclone2_ml\python-libs`.

Run it with:

```powershell
$env:PYTHONPATH='D:\Programs\cyclone2_ml\python-libs'
python python\train.py --data data\mnist --out artifacts --epochs 8
```

The primary hardware-test interface for this project is the PC-photo path.
LCD touch is deliberately outside the required path and is tracked separately
in `D:\fpga\lcd_touch_ml\README.md`. The classifier must be testable without
connecting or programming the LCD.

## 200-sample hardware benchmark

On 2026-10-03, the first 200 labeled images from the downloaded MNIST test
resource (`t10k-images-idx3-ubyte.gz` and `t10k-labels-idx1-ubyte.gz`) were
normalized with the same `normalize_mnist()` function used by training and
sent through the physical CY7C68013A FX2 WinUSB bridge to the FPGA. The
complete per-sample record is saved in
`artifacts/hardware_benchmark_200.csv` (the dataset itself remains ignored).

| Metric | Result |
|---|---:|
| Samples attempted | 200 |
| FPGA responses accepted | 200 (100.00%) |
| Correct labels | 17 (8.50%) |
| Accuracy among accepted responses | 8.50% |
| Transport recoveries | 19 |
| Unrecovered transport errors | 0 |

This initial result was a transport/liveness success but an ML-accuracy
failure. It exposed two RTL bugs that are now corrected: the FPGA used raw
uint4 pixels without the training scale, and the ROM addresses treated the
row-major MIF files as transposed. A software reproduction of the corrected
shift-only fixed-point formula reaches 94.5% on these same 200 images, and
the corrected FPGA matches the software reference during stable USB runs.
The remaining blocker is FX2 recovery: after a WinUSB timeout, the bridge can
still replay an old frame or accept a repeated frame. The benchmark records
this separately and must not be called a final accuracy result until the
frame-sequence protocol is made deterministic.

Reproduce it with:

```powershell
$env:PYTHONPATH='D:\Programs\cyclone2_ml\python-libs;D:\fpga\cyclone2-handwriting-ml\python'
python python\run_hardware_benchmark.py --data data\mnist --count 200 `
  --out artifacts\hardware_benchmark_200.csv
```

The benchmark script writes one row per labeled sample, including expected
label, FPGA digit, acceptance, confidence, margin, FPGA cycle count, transport
time, correctness, and any recovery/error.

### Accuracy issue found by the benchmark

The PC preprocessing and transport are not enough to prove that the FPGA is
using numerically equivalent weights. The 100% response rate with only 8.50%
accuracy points to an inference/data-path mismatch rather than a missing USB
response. The likely candidates are the fixed-point scale/sign convention,
MIF weight/bias ordering, or a frame/accumulator state error. The 19 recoveries
are a separate FX2 packet-boundary/flush issue; they were recovered without
losing a benchmark row.

The completed numerical resolution is in `rtl/ml_inference.sv`: input scaling
uses a resource-safe shift approximation, output scaling uses a shift, and
the ROM addresses now match NumPy row-major layout. The remaining resolution
is to add a transaction sequence number or explicit FPGA reset/flush handshake
to the FX2 protocol, then rerun all 200 samples without frame replay. See
[verification/ISSUES_AND_LESSONS.md](verification/ISSUES_AND_LESSONS.md) for
the root-cause tracking entries.

## Primary test path: PC photo to FPGA

The intended benchmark path is:

```text
Photo on PC
   |
   v
PC preprocessing
  crop, grayscale, resize, center, normalize
   |
   v
14x14 pixel frame (196 values)
   |
   v
PC-to-FPGA transport
  USB/UART or a JTAG-to-register bridge
   |
   v
FPGA input wrapper
  receives pixels and asserts frame_valid/frame_last
   |
   v
SystemVerilog ML core
   |
   v
Digit 0..9, confidence, or NON_RECOGNIZABLE
   |
   v
Return result to the PC and record benchmark data
```

This means the ML project can be tested with real PC images without using the
LCD. The PC software will use the same preprocessing rules as training, send
the resulting 196-pixel frame to the FPGA, wait for `result_valid`, and save
the returned digit, confidence, margin, and latency.

The USB-Blaster is currently used for FPGA configuration. `quartus_pgm` can
download a `.sof`, but it is not by itself a convenient continuous photo
stream. For direct PC-photo testing, the next hardware addition is a small
transport wrapper. The preferred first implementation is a simple UART/USB
byte protocol; a JTAG register bridge is an alternative if the available
board connection supports it. The transport choice must not change the
classifier interface.

### Proposed result protocol and benchmark record

The first transport implementation should use a byte-oriented UART link. The
PC sends one frame, then waits for one result packet:

```text
PC → FPGA:  0xA5, 196 pixel bytes
FPGA → PC:  0x5A, digit, accepted, confidence, margin(u16 LE),
            cycles(u32 LE), XOR checksum
```

Each pixel is one unsigned byte on the link (`0..15` is the classifier value),
although the ML core receives the lower four bits. The FPGA wrapper converts
the packet into `input_pixel_index`, `input_pixel`, `input_frame_valid`, and
`input_frame_last`. When `result_valid` is asserted, the wrapper captures the
ML outputs and transmits them to the PC. `accepted=0` is recorded as
`NON_RECOGNIZABLE`, not as a digit.

The PC benchmark runner stores one CSV row per photo, for example:

```text
sample_id,source_path,expected_label,fpga_digit,accepted,confidence,margin,cycles,correct,error
000001,data/mnist/test/7.png,7,7,1,238,912,13411,1,
000002,data/mnist/test/3.png,3,8,1,121,44,13411,0,wrong_digit
000003,data/mnist/test/9.png,9,,0,12,3,13411,0,non_recognizable
```

`expected_label` comes from the dataset or the user-provided label. The runner
computes `correct` only when the FPGA accepts the frame and its digit equals
the expected label. From the CSV it can report accepted accuracy, rejection
rate, total accuracy, average FPGA cycles, and transport latency. The original
photo and the exact normalized 14×14 frame should be stored beside the CSV so
an incorrect result can be reproduced.

This protocol is a design specification until the FPGA UART/USB wrapper and
the PC serial runner are implemented. It does not require LCD touch or Nios.

The first implementation is now present in `rtl/ml_uart_bridge.sv` and
`python/uart_benchmark.py`. The wrapper is reusable RTL, but the board-specific
clock and UART pin assignments are intentionally still separate. Install the
Python dependency with the project environment, then run one labeled image
after the UART-capable `.sof` has been compiled and downloaded:

```powershell
$env:PYTHONPATH='D:\Programs\cyclone2_ml\python-libs;D:\fpga\cyclone2-handwriting-ml\python'
python python\uart_benchmark.py --port COM7 --image data\example\seven.png --label 7
```

The default output is `artifacts/fpga_benchmark.csv`. It records the original
image path, expected label, FPGA digit, acceptance, confidence, margin,
processing cycles, transport time, and correctness.

## PC–FPGA architecture

The project has two separate communication planes. They must not be confused:

```text
                    CONFIGURATION PLANE
 Quartus Programmer ───── USB-Blaster ───── JTAG ───── FPGA configuration
       writes the complete .sof before runtime testing

                       RUNTIME PLANE
 PC benchmark runner  ⇄  USB-Blaster/JTAG Virtual JTAG  ⇄  FPGA wrapper
       sends a frame                                  returns one result
                                      |
                                      v
                                ML core
                                      |
                                      v
                         digit/confidence/cycles
                                      |
                                      v
                              PC CSV/JSON log
```

### Block responsibilities

| Block | Responsibility | Does not do |
|---|---|---|
| PC preprocessing | Opens the original photo, applies the trained crop/grayscale/resize/normalization rules, and creates 196 four-bit pixels | Does not decide the FPGA result |
| PC runtime driver | Sends one frame, waits for completion, reads the result, and stores the original path and expected label | Does not program the FPGA for every image |
| USB-Blaster/JTAG | Loads the `.sof`; later, its Virtual JTAG channel can carry test frames and result registers | Is not automatically a general-purpose file-transfer device |
| FPGA runtime wrapper | Implements the Virtual JTAG command/register interface, accepts 196 pixels, starts the ML core, and captures outputs | Does not preprocess camera/photo files |
| `ml_inference.sv` | Performs quantized inference and produces digit, acceptance, confidence, margin, and cycle count | Does not know about USB, JTAG, LCD, or files |
| PC benchmark logger | Writes CSV/JSON and compares `fpga_digit` against `expected_label` | Does not alter the FPGA result |

### Runtime transaction

One benchmark sample follows this transaction:

```text
1. PC loads photo and known label.
2. PC creates normalized frame[0..195].
3. PC obtains a JTAG Virtual JTAG session.
4. PC writes START=0 and clears STATUS.
5. PC writes the 196 pixel values to the FPGA frame registers.
6. PC writes START=1.
7. FPGA wrapper streams the frame to ml_inference.sv.
8. FPGA asserts DONE when result_valid arrives.
9. PC reads DIGIT, ACCEPTED, CONFIDENCE, MARGIN, and CYCLES.
10. PC writes one CSV/JSON record and compares against the known label.
```

The FPGA register map should be kept stable and independent of the ML
implementation:

| Register | Direction | Meaning |
|---|---|---|
| `CONTROL` | PC → FPGA | `START`, `CLEAR` |
| `PIXEL_INDEX` | PC → FPGA | Selects pixel 0–195 |
| `PIXEL_DATA` | PC → FPGA | Four-bit normalized pixel |
| `STATUS` | FPGA → PC | `BUSY`, `DONE`, `ERROR` |
| `RESULT_DIGIT` | FPGA → PC | Digit 0–9 |
| `RESULT_ACCEPTED` | FPGA → PC | 0 means `NON_RECOGNIZABLE` |
| `RESULT_CONFIDENCE` | FPGA → PC | Quantized confidence |
| `RESULT_MARGIN` | FPGA → PC | Difference from second-best score |
| `RESULT_CYCLES` | FPGA → PC | ML processing cycle count |

### Why JTAG is the first implementation

JTAG Virtual JTAG is appropriate for the first proof because the frame is only
196 pixels and the objective is functional correctness and benchmarking, not
maximum throughput. The same USB-Blaster cable can therefore perform both
`.sof` configuration and controlled runtime register transfers, but these are
two separate operations and require separate FPGA logic.

The CY7C68013A USB board is a later high-throughput option. It requires USB
firmware, a PC driver/API, and an FPGA FIFO endpoint, so it is not part of the
first JTAG proof. LCD touch remains outside this architecture and can later be
added only as another producer of the same 14×14 frame.

LCD touch is therefore optional: it can later become another producer of the
same 14×14 frame, but it is not part of the PC benchmark and is not required
to validate the ML core.

## Quantized reference and FPGA files

After training, verify the exported int8 model and generate signed
two's-complement Quartus memory files:

```powershell
$env:PYTHONPATH='D:\Programs\cyclone2_ml\python-libs;D:\fpga\cyclone2-handwriting-ml\python'
python python\quantized_reference.py --data data\mnist --artifacts artifacts
```

This creates `weights_l1.mif`, `bias_l1.mif`, `weights_l2.mif`, and
`bias_l2.mif`, plus `quantized_report.json`. The MIF weights are row-major:
layer 1 is 196×32 and layer 2 is 32×10.

The first reusable SystemVerilog RTL inference boundary is now in `rtl/`. It accepts a
streamed 14×14 frame and returns a digit, confidence, margin, cycle count,
and an acceptance flag for the `NON_RECOGNIZABLE` policy. Its current
EP2C5T144C8 smoke build succeeds, but it is a reference implementation only:
timing closure, exact RTL/Python numerical equivalence, board pin mapping,
and LCD/USB integration remain separate verification steps.

UVM verification sources are in `verification/uvm/`. They use a
SystemVerilog UVM driver/monitor/scoreboard around the principal
SystemVerilog core in `rtl/ml_inference.sv`. The original VHDL file remains
only as a legacy comparison reference.
The detailed troubleshooting and learning record is in
[`verification/ISSUES_AND_LESSONS.md`](verification/ISSUES_AND_LESSONS.md).

## Processing flow: from a test frame to a digit

The PC-input path is now implemented and hardware-tested through the
CY7C68013A FX2 bridge. LCD touch remains deliberately outside this benchmark.

```text
PC 14x14 frame
  -> pack as A5A5 + 98 little-endian 16-bit words
  -> FX2 EP2 OUT
  -> Cyclone II FIFO receiver and dual-port frame RAM
  -> SystemVerilog ML core at the 5 MHz enable rate
  -> two result frames grouped in one 24-byte EP6 packet
  -> FX2 EP6 IN
  -> PC decoder scans C33C marker and benchmark report
```

The current project has two different execution paths. The first path is
already implemented and verified in simulation. The second path is the future
board integration path; it is described here so the boundary is clear.

### Current simulation path

```text
14x14 test frame (196 pixels, 4 bits each)
        |
        v
UVM sequence / driver
        |
        v
ml_inference.sv
  1. accept pixels at input_pixel_index 0..195
  2. store the frame in the input buffer
  3. calculate the first 32-neuron layer
  4. calculate the 10 output scores
  5. select the highest-scoring digit
  6. calculate confidence and margin
        |
        v
result_valid + result_digit[3:0]
             + result_confidence[7:0]
             + result_margin[15:0]
             + result_cycles[31:0]
```

The UVM test supplies known frames, waits until `busy` is clear, sends all
196 pixels, and checks the result against the golden reference. This proves
the RTL computation and its handshaking, but it does not program or exercise
the physical FPGA board.

### Planned hardware path: PC input first

```text
PC photo
        |
        v
PC preprocessing and 14x14 conversion
        |
        v
USB/UART or JTAG input wrapper
        |
        v
board wrapper sends 196 pixels to ml_inference.sv
        |
        v
digit + confidence + acceptance decision
        |
        +--> LEDs or temporary board output
        +--> USB/UART result to the PC
```

The LCD touch controller is not shown in this primary path. It is an optional
later input adapter only.

The phrase “generate one known 14×14 test frame inside the FPGA” means a
temporary hardware source, normally a small ROM or counter-controlled test
pattern, connected to the same 196-pixel classifier interface. It is useful
because it checks the complete FPGA `.sof` download and result display before
LCD wiring is introduced. It is not the final handwriting input.

### What is and is not complete

| Stage | Status | Meaning |
|---|---|---|
| PC training and quantized reference | Complete | Model trained and exported |
| SystemVerilog ML core | Complete reference | Accepts a streamed 14×14 frame |
| UVM golden-vector verification | Complete | RTL results and handshaking checked in simulation |
| PC-to-FPGA transport wrapper | Complete and hardware-tested | WinUSB EP2/EP6 bridge |
| Hardware test-frame wrapper | Optional fallback | Useful for checking the FPGA without a PC link |
| LCD touch-to-14×14 wrapper | Not required here | Tracked by the separate LCD/ML integration project |
| `.sof` download and physical PC-photo inference | Complete for four-point benchmark | Photo UI uses the same packed-frame path |

The standalone ML core is connected to the board transport in
`rtl/fx2_ml_bridge/`. Use its README and `python/run_hardware_benchmark.py` for
the reproducible hardware test. LCD integration is intentionally postponed and
is not a dependency of this project.
