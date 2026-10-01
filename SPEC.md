# Cyclone II Handwriting Digit Recognition — Specification

Status: specification only. No FPGA implementation or training run is included yet.

## 1. Purpose

Create a reusable machine-learning inference system for the shared Waveshare/CoreEP2C5 board. It will accept a photo or drawing containing one handwritten digit, normalize it to a fixed grayscale tensor, and return either digit `0` through `9` or `NON_RECOGNIZABLE`.

Training happens on the PC. The FPGA performs the trained model's forward pass and returns the predicted digit, confidence, and recognition status. The classifier core must not depend on the LCD, touch controller, USB-Blaster, Nios II, or a particular photo source. This separation is required because the Cyclone II board is suitable for compact inference, but not for training a neural network.

## 2. Common hardware target

The complete shared-board connection specification is maintained in
[BOARD_SPEC.md](BOARD_SPEC.md). It must be consulted before adding LCD,
touch, SDRAM, FX2 USB, UART, joystick, or JTAG connections.

| Item | Specification |
|---|---|
| Board | Waveshare/CoreEP2C5 |
| FPGA | Intel/Altera Cyclone II `EP2C5T144C8` |
| Logic elements | 4,608 |
| Embedded memory | 119,808 bits |
| DSP blocks | 26 |
| Board clock | 50 MHz |
| Toolchain | Quartus II 13.0 SP1; VHDL/SystemVerilog as appropriate |
| Default sound | Buzzer muted |

The design must preserve the existing board pin assignments and must not use `lcd_photo` as a dependency.

## 3. Free training source and benchmark

The primary dataset is the original MNIST handwritten-digit database by Yann LeCun, Corinna Cortes, and Chris Burges:

- Training set: 60,000 labeled 28×28 images.
- Official test set: 10,000 labeled 28×28 images.
- Source: <https://yann.lecun.org/exdb/mnist/index.html>

The official test set must remain untouched during training and calibration. The benchmark must report overall accuracy, per-digit accuracy, a 10×10 confusion matrix, and the number of rejected/invalid input frames.

## 4. First implementation target

The first FPGA model will be a compact quantized multilayer perceptron:

```text
Input:       14×14 grayscale image, unsigned 4-bit pixels  (196 values)
Layer 1:     196 → 32 fully connected, signed int8 weights
Activation:  ReLU and int8 saturation
Layer 2:     32 → 10 fully connected, signed int8 weights
Output:      argmax of 10 signed scores, digit 0–9
```

The PC preprocessing step converts MNIST's 28×28 pixels to 14×14 by area averaging and quantizes them to 4 bits. The FPGA does not perform floating-point arithmetic.

Estimated parameter storage:

- Layer 1 weights: `196 × 32 = 6,272` bytes at int8.
- Layer 2 weights: `32 × 10 = 320` bytes at int8.
- Biases and metadata: less than 1 KB.
- Total model storage: approximately 7 KB, leaving room for input buffers, result buffers, and control logic in embedded RAM.

The accelerator should reuse a small number of signed multiply-accumulate units over time instead of instantiating one multiplier per weight. A later optimization may use power-of-two or binary weights if resource or speed measurements require it.

## 5. Input and output interfaces

### Reusable classifier contract

The classifier consumes exactly one normalized 14×14 frame per transaction. It
must not depend on the LCD, touch controller, USB-Blaster, Nios II, or a
particular photo source.

```text
input_frame_valid   : one-cycle pulse
input_pixel_index   : 0..195
input_pixel         : unsigned 4-bit grayscale pixel
input_frame_last    : asserted with pixel index 195
input_frame_error   : invalid source/crop/format indication

result_valid        : one-cycle pulse
result_status       : ACCEPTED or NON_RECOGNIZABLE
result_digit        : 0..9 when ACCEPTED, otherwise 0
result_confidence   : unsigned score/255
result_margin       : best_score - second_best_score
result_error        : protocol or arithmetic error
```

A photo file, PC test-vector sender, LCD touch capture, and a future camera
input must all feed this same normalized-frame interface.

### Photo input pipeline

The photo adapter runs outside the classifier and performs deterministic steps:

1. Decode the photo and convert it to grayscale.
2. Detect foreground using a background estimate and threshold.
3. Reject frames with no foreground, multiple candidates, or an unusable box.
4. Crop the digit, preserve aspect ratio, center it on a square canvas, and
   resize to 28×28.
5. Area-average to 14×14 and quantize to unsigned 4-bit pixels.
6. Send the normalized frame to the reusable classifier contract.

The adapter must export both the intermediate 28×28 image and final 14×14
tensor for debugging. A raw JPEG/PNG is never sent directly to the FPGA model.

### Recognition decision

The model always produces ten scores, but the public result is
`NON_RECOGNIZABLE` if preprocessing rejects the frame, the best score is below
the calibrated threshold, or the margin over the second-best score is too
small. Thresholds are selected on a validation split and frozen before the
official MNIST test benchmark; they are stored in model metadata.

### MVP: PC-fed inference

The first hardware test uses the existing JTAG/USB-Blaster path or a documented
serial bridge:

1. PC reads a photo or test image and runs the photo adapter.
2. PC sends a frame header, 196 quantized pixels, and a checksum.
3. FPGA validates the frame and starts inference.
4. FPGA returns `0–9` or `NON_RECOGNIZABLE`, ten scores, confidence, margin,
   inference cycle count, and status.

The protocol must support one image at a time and reject bad headers, wrong
lengths, and checksum failures without locking the accelerator.

### Later: LCD touch input

The LCD touch interface will use the same crop, center, resize, and 14×14
normalization contract, then feed the same inference core. The touch/UI layer
remains separate so MNIST and photo benchmarks remain reproducible.

## 6. PC training and conversion tools

The project will contain a reproducible Python training/conversion utility that:

- downloads or reads the MNIST files;
- trains the reference model;
- evaluates the untouched official test set;
- quantizes weights and biases;
- exports synthesizable memory files (`.mif` or `.hex`);
- exports a compact test-vector file for FPGA/PC comparison;
- records the random seed, preprocessing version, model dimensions, quantization scale, and accuracy.

The PC reference implementation and FPGA integer implementation must run the same exported test vectors and produce the same predicted digit for every accepted vector in the verification set.

## 7. Verification and benchmark plan

Success is measured in stages:

| Stage | Requirement |
|---|---|
| Python reference | Train successfully and report MNIST test accuracy and confusion matrix |
| Quantized reference | Measure accuracy after 14×14/int8 conversion; record any loss from the floating-point reference |
| RTL simulation | Match the quantized Python outputs on a deterministic vector set |
| Quartus fit | Fit `EP2C5T144C8` with no errors and preserve board pin assignments |
| Timing | Meet the 50 MHz constraint with non-negative setup and hold slack |
| Hardware | Correctly classify PC-fed frames and report a stable result |
| Optional touch mode | Classify hand-drawn digits after touch preprocessing |

The README must record logic elements, memory bits, DSP usage, pins, Fmax/timing slack, inference latency in cycles, and MNIST accuracy for every model revision.

## 8. Resource and risk limits

- Do not place training, floating-point operators, or a full software stack on the FPGA.
- Keep the first design below 80% of logic elements and embedded memory where practical, leaving margin for the communication and LCD/touch control logic.
- Do not claim full end-to-end touch recognition until the touch normalization step has been measured separately.
- Treat MNIST accuracy and accuracy on handwriting drawn on the LCD as separate metrics; the latter is an out-of-distribution test.
- Keep the buzzer muted in all hardware images.

## 9. Planned project structure

```text
cyclone2-handwriting-ml/
├── README.md
├── SPEC.md
├── python/
│   ├── train.py
│   ├── quantize.py
│   ├── benchmark.py
│   └── export_vectors.py
├── rtl/
│   ├── ml_inference.vhd
│   ├── mac_engine.vhd
│   ├── frame_protocol.vhd
│   └── model_weights.mif
├── simulation/
├── synthesis/
└── data/                 # ignored; never commit the downloaded dataset
```

The next implementation step is the PC reference trainer and quantizer. FPGA RTL should be started only after the quantized model's accuracy and exported-vector format are fixed.
