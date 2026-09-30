# Cyclone II Handwriting ML

Specification for a reusable photo-to-digit FPGA inference project that recognizes handwritten digits `0–9` or returns `NON_RECOGNIZABLE` on the shared Waveshare/CoreEP2C5 Cyclone II board. SystemVerilog is the principal RTL language for this project.

Read [SPEC.md](SPEC.md) before implementation. The first phase is PC photo normalization, training, and benchmarking with MNIST; the FPGA phase will implement reusable quantized inference at the board's selected 8 MHz clock. LCD touch and photo input must share the same classifier interface.

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

LCD touch integration is tracked separately in
`D:\fpga\lcd_touch_ml\README.md`. It converts touch strokes into the same
14×14 tensor used by this classifier and does not create a second ML model.

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
