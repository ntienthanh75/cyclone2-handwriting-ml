# LCD touch to FPGA handwriting-recognition integration

This document defines the integration between `D:\fpga\Lcd_touch` and
`D:\fpga\cyclone2-handwriting-ml`.

The current projects use different FPGA hardware images. The LCD Nios `.sof`
does not contain the FX2 ML bridge, and the ML bridge `.sof` does not contain
the LCD Nios/touch system. They cannot both be loaded into the FPGA at once.

## Resource feasibility of simultaneous Nios + ML

The saved Quartus fit reports show that the current implementations do not
fit together in the EP2C5T144:

| Resource | LCD/Nios image | ML bridge image | Naive combined total | Device total |
|---|---:|---:|---:|---:|
| Logic elements | 4,282 (93%) | 3,135 (68%) | 7,417 (161%) | 4,608 |
| Registers | 2,886 | 800 | 3,686 | 4,608 |
| Memory bits | 33,792 (28%) | 56,912 (48%) | 90,704 (76%) | 119,808 |
| 9-bit multipliers | 4 (15%) | 5 (19%) | 9 (35%) | 26 |
| PLLs | 1 (50%) | 0 | 1 (50%) | 2 |
| Top-level pins | 78 (88%) | 31 (35%) | 109 (123%) | 89 |

The logic-element and pin totals are already over the device limits. Logic
sharing might reduce a small amount, but it cannot remove the roughly 2,809
logic-element excess or resolve all pin conflicts. Therefore the existing
Nios image and ML bridge cannot simply be merged into one `.sof`.

## Recommended first milestone: Option 1

Use the already validated PC path as the integration boundary:

```text
User writes on LCD
        |
        v
LCD touch controller -> Nios LCD application -> LCD live drawing
        |
        v
JTAG-UART -> PC touch viewer -> saved drawing file
                                      |
                                      v
                         PC normalizes one 14x14 frame
                                      |
                                      v
                            FX2 EP2 -> FPGA ML core
                                      |
                            FPGA digit result
                                      v
                            FX2 EP6 -> PC collector
```

### Option 1 sequence

1. The user draws on the LCD.
2. `Lcd_touch` displays the stroke and sends touch samples to the PC.
3. The user finishes the drawing using the existing finish action.
4. The PC saves one completed drawing under `D:\fpga\Lcd_touch\captures`.
5. The ML UI or an integration runner reads that saved drawing.
6. The PC applies the same normalization used by the MNIST benchmark.
7. The PC sends 196 normalized 4-bit pixels through FX2 EP2.
8. The FPGA ML core returns digit, accepted flag, confidence, margin, and cycles.
9. The PC stores the drawing name, prediction, timing, and session ID.

Option 1 is recommended first because LCD drawing, PC capture, normalization,
FX2 transfer, FPGA recognition, and result collection can be tested separately.
On the current board it is a two-phase workflow: use the LCD/Nios `.sof` to
capture and save the drawing, then program the ML bridge `.sof` and recognize
that saved drawing. The drawing file and PC result collector preserve the
session across the FPGA reprogramming step.

## Option 2: direct LCD frame to FPGA

Option 2 is the final embedded architecture:

```text
LCD touch -> FPGA/Nios frame buffer ->+-> LCD display
                                     +-> FX2/ML input -> ML core
                                     +-> FX2/PC mirror
                                              |
                                     digit/result -> PC collector
```

The FPGA must capture a complete drawing frame, store it in on-chip or
external memory, normalize it to the ML 14x14 input format, and feed the ML
core. A second read port or controlled replay is needed to mirror the same
frame to the PC.

Option 2 requires a new unified Quartus design containing:

- LCD controller and XPT2046 touch interface
- Nios or equivalent touch-capture controller
- frame-buffer ownership/arbitration
- ML input-stream adapter
- FX2 EP2/EP6 interface
- result/status registers for the PC
- one coherent clock/reset and pin assignment set

This is a later hardware project, not a PC UI-only change.

## Option 2 resource calculation

Using the measured ML bridge as the fixed part of a unified design, the
remaining upper-bound budget is:

| Resource | EP2C5 total | ML bridge used | Remaining budget for direct LCD/touch logic |
|---|---:|---:|---:|
| Logic elements | 4,608 | 3,135 | 1,473 |
| Pins | 89 | 31 | 58 |
| Memory bits | 119,808 | 56,912 | 62,896 |
| 9-bit multipliers | 26 | 5 | 21 |
| PLLs | 2 | 0 | 2 |

The existing LCD/Nios implementation needs 4,282 logic elements and 78 pins.
To coexist with the current ML bridge, it would have to shrink to at most
1,473 logic elements and at most 58 pins. That means removing at least 2,809
logic elements, or 65.6% of the current LCD/Nios logic, plus at least 20 pins.
Therefore an Option 2 design that keeps the existing Nios system is not
realistic on this device.

A possible Option 2 redesign would remove Nios and implement only a small RTL
touch collector: an XPT2046 SPI state machine, coordinate mapping, a 14×14
bitmap RAM, finish/clear control, and a shared FX2 frame streamer. That design
must still include whatever LCD pixel-write logic is needed for live drawing.
Its feasibility cannot be claimed from addition alone; it must be written and
compiled as a new top level. The first acceptance criterion is a successful
Quartus fit below 1,473 logic elements for the direct LCD/touch side while
preserving the ML bridge timing and all required pins.

## PC result collection format

The collector should append one record per completed drawing:

| Field | Meaning |
|---|---|
| `session_id` | One drawing session identifier |
| `source_name` | Saved LCD capture filename |
| `source_path` | Original local capture path |
| `frame_width` / `frame_height` | Source dimensions before normalization |
| `expected_label` | Optional label entered by the user |
| `fpga_digit` | FPGA prediction 0-9 |
| `accepted` | FPGA confidence gate result |
| `confidence` | FPGA confidence value |
| `margin` | Difference from second-best score |
| `fpga_cycles` | FPGA processing counter |
| `pc_round_trip_ms` | PC send-to-result time |
| `transport_recoveries` | FX2 reconnect/retry count |
| `error` | Empty, wrong digit, non-recognizable, or transport error |

The existing hardware benchmark CSV already contains most FPGA result fields.
The LCD integration should add source filename and session fields instead of
inventing a second result format.

## Implementation order

### Step 1 - Freeze the independent baselines

Verify `Lcd_touch` can save one complete drawing and that the ML UI can send a
chosen photo to the FPGA and display a result.

### Step 2 - Reprogram between capture and recognition

After `DRAW_FINISH` saves the drawing, stop the LCD Nios application, program
`D:\fpga\cyclone2-handwriting-ml\rtl\fx2_ml_bridge\fx2_ml_bridge.sof`, and
connect the FX2 runtime path. The saved capture is then sent through the ML
bridge. This is required with the current resource usage; it is not a reset
of the PC session.

### Step 3 - Add a PC integration runner

Create a runner that watches or receives one completed file from
`D:\fpga\Lcd_touch\captures`, calls the existing normalization code, sends the
frame through the existing FX2 `FX2.transact()` path, and appends the result
record above. It should not change FPGA RTL.

### Step 4 - Add session control

Use `DRAW_FINISH` as the boundary between drawings. Assign a new `session_id`,
save the original capture, run recognition once, append one result, and wait
for the next drawing. Keep `DRAW_SHUTDOWN` as a clean stop command.

### Step 5 - Validate end to end

Run at least ten LCD drawings and check that each saved drawing has exactly one
matching FPGA result. Compare the PC viewer image, normalized 14x14 frame, and
stored prediction for the same `session_id`.

### Step 6 - Decide whether Option 2 is justified

Only move to Option 2 after Option 1 is stable. Option 2 is justified when PC
round-trip handling is too slow, the PC must not preprocess the drawing, or
the system must operate without a host-side capture application.

## Current decision

Implement Option 1 first. It is a software integration around two working
projects and gives a complete, measurable LCD-to-ML-to-PC flow. Keep Option 2
as a separate unified-FPGA design so it does not destabilize the working LCD
touch project or the validated ML bridge.
