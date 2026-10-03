"""Interactive PC -> FX2 -> Cyclone II ML viewer.

The UI deliberately reuses the validated FX2 WinUSB implementation from
``fx2_winusb_ui.py``.  It does not program the FPGA; load the bridge SOF with
Quartus Programmer first.
"""
from __future__ import annotations

import queue
import random
import threading
import time
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

import numpy as np

from fx2_protocol_test import make_four_points, pack_frame
from fx2_winusb_ui import FX2
from train import load_mnist, normalize_mnist, normalize_photo


class MLViewer:
    CELL = 24

    def __init__(self, root: tk.Tk, data_dir: Path) -> None:
        self.root = root
        self.data_dir = data_dir
        self.dev = FX2()
        self.events: queue.Queue[tuple[str, object]] = queue.Queue()
        self.pixels = list(make_four_points())
        self.source = "built-in four-point sample"
        self.expected: int | None = None
        self.busy = False
        self.test_images: np.ndarray | None = None
        self.test_labels: np.ndarray | None = None

        root.title("Cyclone II handwriting ML viewer")
        root.geometry("900x720")
        root.minsize(820, 650)

        top = ttk.Frame(root, padding=10)
        top.pack(fill="x")
        self.status = tk.StringVar(value="Not connected")
        ttk.Label(top, textvariable=self.status, font=("Segoe UI", 11, "bold")).pack(side="left")
        self.connect_button = ttk.Button(top, text="1. Connect FX2", command=self.connect)
        self.connect_button.pack(side="left", padx=(18, 0))

        controls = ttk.LabelFrame(root, text="2. Select an input sample", padding=8)
        controls.pack(fill="x", padx=10, pady=(0, 8))
        self.sample_button = ttk.Button(controls, text="2A. Four-point test", command=self.four_points)
        self.sample_button.pack(side="left")
        ttk.Button(controls, text="2B. Random MNIST sample", command=self.load_sample).pack(side="left", padx=6)
        ttk.Button(controls, text="2C. Choose photo", command=self.choose_photo).pack(side="left")
        self.source_label = tk.StringVar(value=self.source)
        ttk.Label(controls, textvariable=self.source_label).pack(side="left", padx=12)

        preview = ttk.Frame(root, padding=(10, 0))
        preview.pack(fill="x")
        left = ttk.LabelFrame(preview, text="Input sent to FPGA (14×14)", padding=8)
        left.pack(side="left", fill="both", expand=True, padx=(0, 5))
        right = ttk.LabelFrame(preview, text="FPGA result (same frame + digit)", padding=8)
        right.pack(side="left", fill="both", expand=True, padx=(5, 0))
        self.input_canvas = tk.Canvas(left, width=14 * self.CELL, height=14 * self.CELL,
                                      background="white", highlightthickness=1,
                                      highlightbackground="#aaaaaa")
        self.input_canvas.pack()
        self.output_canvas = tk.Canvas(right, width=14 * self.CELL, height=14 * self.CELL,
                                       background="white", highlightthickness=1,
                                       highlightbackground="#aaaaaa")
        self.output_canvas.pack()
        self.result_detail = tk.StringVar(value="No FPGA result yet")
        ttk.Label(right, textvariable=self.result_detail, font=("Segoe UI", 10, "bold")).pack(pady=(6, 0))

        action = ttk.Frame(root, padding=10)
        action.pack(fill="x")
        self.send_button = ttk.Button(action, text="3. Send sample to FPGA", command=self.send)
        self.send_button.pack(side="left")
        self.progress = ttk.Progressbar(action, mode="indeterminate", length=220)
        self.progress.pack(side="left", padx=12)
        self.result = tk.StringVar(value="Result: —")
        ttk.Label(action, textvariable=self.result, font=("Segoe UI", 14, "bold")).pack(side="left")

        log_frame = ttk.LabelFrame(root, text="Processing log", padding=6)
        log_frame.pack(fill="both", expand=True, padx=10, pady=(0, 10))
        self.log = tk.Text(log_frame, height=12, state="disabled", font=("Consolas", 9))
        self.log.pack(side="left", fill="both", expand=True)
        scroll = ttk.Scrollbar(log_frame, command=self.log.yview)
        scroll.pack(side="right", fill="y")
        self.log.configure(yscrollcommand=scroll.set)

        self.draw(self.input_canvas, self.pixels)
        self.draw(self.output_canvas, self.pixels, outline="#999999")
        root.after(100, self.poll)
        root.protocol("WM_DELETE_WINDOW", self.close)

    def write(self, text: str) -> None:
        stamp = time.strftime("%H:%M:%S")
        self.log.configure(state="normal")
        self.log.insert("end", f"[{stamp}] {text}\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def draw(self, canvas: tk.Canvas, pixels: list[int], outline: str = "#dddddd") -> None:
        canvas.delete("all")
        for row in range(14):
            for col in range(14):
                value = int(pixels[row * 14 + col])
                shade = max(0, min(255, 255 - value * 17))
                color = f"#{shade:02x}{shade:02x}{shade:02x}"
                x, y = col * self.CELL, row * self.CELL
                canvas.create_rectangle(x, y, x + self.CELL, y + self.CELL,
                                        fill=color, outline=outline)

    def set_sample(self, pixels: list[int], source: str, expected: int | None = None) -> None:
        self.pixels = [max(0, min(15, int(v))) for v in pixels]
        self.source, self.expected = source, expected
        self.source_label.set(source if expected is None else f"{source} (label {expected})")
        self.result.set("Result: —")
        self.result_detail.set("No FPGA result yet — click 3. Send sample to FPGA")
        self.draw(self.input_canvas, self.pixels)
        self.draw(self.output_canvas, self.pixels, outline="#999999")
        self.write(f"sample ready: {source}; 196 normalized pixels")

    def connect(self) -> None:
        try:
            self.dev.close()
            message = self.dev.open()
            self.status.set(message)
            self.write(message)
        except Exception as exc:
            self.status.set("Not connected")
            self.write(f"connect error: {exc}")

    def load_sample(self) -> None:
        try:
            if self.test_images is None:
                self.write("loading local MNIST test set...")
                _, _, self.test_images, self.test_labels = load_mnist(self.data_dir)
            idx = random.SystemRandom().randrange(len(self.test_images))
            pixels = normalize_mnist(self.test_images[idx:idx + 1])[0].tolist()
            label = int(self.test_labels[idx])
            sample_name = f"mnist_test_{idx:05d}_label_{label}.png"
            self.set_sample(pixels, sample_name, label)
        except Exception as exc:
            messagebox.showerror("Load MNIST sample", str(exc))
            self.write(f"sample error: {exc}")

    def choose_photo(self) -> None:
        path = filedialog.askopenfilename(
            title="Choose one handwriting photo",
            filetypes=[("Image files", "*.png *.jpg *.jpeg *.bmp"), ("All files", "*.*")])
        if not path:
            return
        try:
            pixels = normalize_photo(Path(path)).tolist()
            self.set_sample(pixels, str(Path(path)))
        except Exception as exc:
            messagebox.showerror("Photo normalization", str(exc))
            self.write(f"photo error: {exc}")

    def four_points(self) -> None:
        self.set_sample(list(make_four_points()), "built-in four-point sample")

    def send(self) -> None:
        if self.busy:
            self.write("busy: wait for the current FPGA transaction")
            return
        self.busy = True
        self.send_button.configure(state="disabled")
        self.sample_button.configure(state="disabled")
        self.progress.start(12)
        self.result.set("Result: sending...")
        threading.Thread(target=self.worker, args=(self.pixels[:], self.source), daemon=True).start()

    def worker(self, pixels: list[int], source: str) -> None:
        started = time.perf_counter()
        try:
            self.events.put(("log", f"starting FPGA transaction for {source}"))
            if not self.dev.usb:
                self.events.put(("log", "FX2 not open; connecting automatically"))
                message = self.dev.open()
                self.events.put(("connected", message))
            self.dev.sequence = (self.dev.sequence + 1) & 0xFF
            sequence = self.dev.sequence
            self.events.put(("log", f"stage 1/3: sending 99 words / 198 bytes, ID {sequence}"))
            self.events.put(("stage", "sending"))
            result = None
            recovered = False
            for attempt in range(3):
                try:
                    result = self.dev.transact(pack_frame(pixels, sequence))
                    break
                except (OSError, TimeoutError) as exc:
                    if attempt == 2:
                        raise
                    recovered = True
                    self.events.put(("log", f"recovery {attempt + 1}/2: {exc}"))
                    self.dev.close()
                    time.sleep(0.25)
                    message = self.dev.open()
                    self.events.put(("connected", message))
            if result is None:
                raise OSError("no FPGA result after three attempts")
            if recovered:
                # A failed EP6 read can leave the bridge's redundant response
                # queued after the retry.  Drain it before the next sample.
                time.sleep(0.25)
                self.dev._drain_stale_in()
            elapsed = (time.perf_counter() - started) * 1000.0
            self.events.put(("stage", "received"))
            self.events.put(("result", (result, elapsed)))
        except Exception as exc:
            self.dev.close()
            self.events.put(("error", exc))

    def poll(self) -> None:
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "log":
                    self.write(str(payload))
                elif kind == "connected":
                    self.status.set(str(payload)); self.write(str(payload))
                elif kind == "stage":
                    if payload == "sending":
                        self.status.set("Sending frame to FPGA...")
                    else:
                        self.status.set("Receiving result from FPGA...")
                        self.write("stage 2/3: FPGA response received; decoding six result words")
                elif kind == "result":
                    result, elapsed = payload
                    accepted = bool(result["accepted"])
                    digit = int(result["digit"])
                    verdict = f"digit {digit}" if accepted else "NON-RECOGNIZABLE"
                    self.result.set(f"Result: {verdict}")
                    self.result_detail.set(
                        f"FPGA recognized: {verdict} | confidence {result['confidence']} | "
                        f"{elapsed:.3f} ms")
                    self.draw(self.output_canvas, self.pixels, outline="#35a853" if accepted else "#cc3333")
                    self.write(
                        f"stage 3/3: {verdict}; confidence={result['confidence']}; "
                        f"margin={result['margin']}; FPGA cycles={result['cycles']}; "
                        f"round trip={elapsed:.3f} ms")
                    if self.expected is not None:
                        self.write(f"comparison: expected {self.expected}; "
                                   f"{'CORRECT' if accepted and digit == self.expected else 'WRONG'}")
                    self.status.set("Result received")
                    self.busy = False
                    self.progress.stop()
                    self.send_button.configure(state="normal")
                    self.sample_button.configure(state="normal")
                elif kind == "error":
                    self.write(f"transfer error: {payload}")
                    self.status.set("Transfer failed; ready to retry")
                    self.result.set("Result: —")
                    self.result_detail.set("No complete FPGA result")
                    self.busy = False
                    self.progress.stop()
                    self.send_button.configure(state="normal")
                    self.sample_button.configure(state="normal")
        except queue.Empty:
            pass
        self.root.after(100, self.poll)

    def close(self) -> None:
        self.dev.close()
        self.root.destroy()


def main() -> None:
    root = tk.Tk()
    MLViewer(root, Path(__file__).resolve().parents[1] / "data" / "mnist")
    root.mainloop()


if __name__ == "__main__":
    main()
