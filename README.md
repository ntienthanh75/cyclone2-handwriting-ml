# Cyclone II Handwriting ML

Specification for a reusable photo-to-digit FPGA inference project that recognizes handwritten digits `0–9` or returns `NON_RECOGNIZABLE` on the shared Waveshare/CoreEP2C5 Cyclone II board.

Read [SPEC.md](SPEC.md) before implementation. The first phase is PC photo normalization, training, and benchmarking with MNIST; the FPGA phase will implement reusable quantized inference at the board's 50 MHz clock. LCD touch and photo input must share the same classifier interface.

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
