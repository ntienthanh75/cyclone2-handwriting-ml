"""Send normalized handwriting frames to the FPGA UART wrapper.

The FPGA protocol is:
  PC -> FPGA: 0xA5 + 196 pixel bytes (values 0..15)
  FPGA -> PC: 0x5A + digit + accepted + confidence + margin(u16 LE)
              + cycles(u32 LE) + XOR checksum

This script stores the FPGA result beside the original label in CSV so the
hardware result can be compared with the dataset label.
"""
from __future__ import annotations

import argparse
import csv
import time
from pathlib import Path

import serial

from train import normalize_photo


def read_packet(port: serial.Serial) -> dict:
    while True:
        marker = port.read(1)
        if not marker:
            raise TimeoutError("timeout waiting for FPGA result")
        if marker == b"\x5A":
            break
    body = port.read(10)  # digit, accepted, confidence, margin(2), cycles(4), xor
    if len(body) != 10:
        raise TimeoutError("incomplete FPGA result packet")
    payload = bytes((0x5A,)) + body[:-1]
    checksum = 0
    for value in payload:
        checksum ^= value
    if checksum != body[-1]:
        raise ValueError(f"result checksum mismatch: {checksum:#x} != {body[-1]:#x}")
    return {
        "fpga_digit": body[0],
        "accepted": body[1],
        "confidence": body[2],
        "margin": int.from_bytes(body[3:5], "little"),
        "cycles": int.from_bytes(body[5:9], "little"),
    }


def classify_one(port: serial.Serial, image: Path, expected: int | None) -> dict:
    frame = bytes(int(value) & 0x0F for value in normalize_photo(image))
    if len(frame) != 196:
        raise ValueError(f"expected 196 pixels, got {len(frame)}")
    port.reset_input_buffer()
    started = time.perf_counter()
    port.write(b"\xA5" + frame)
    port.flush()
    result = read_packet(port)
    result["transport_ms"] = (time.perf_counter() - started) * 1000.0
    result["source_path"] = str(image)
    result["expected_label"] = "" if expected is None else expected
    result["correct"] = "" if expected is None else int(
        bool(result["accepted"]) and result["fpga_digit"] == expected
    )
    if not result["accepted"]:
        result["error"] = "non_recognizable"
    elif expected is not None and result["fpga_digit"] != expected:
        result["error"] = "wrong_digit"
    else:
        result["error"] = ""
    return result


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True, help="Windows COM port, e.g. COM7")
    ap.add_argument("--image", type=Path, required=True)
    ap.add_argument("--label", type=int, choices=range(10))
    ap.add_argument("--csv", type=Path, default=Path("artifacts/fpga_benchmark.csv"))
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--timeout", type=float, default=5.0)
    args = ap.parse_args()

    args.csv.parent.mkdir(parents=True, exist_ok=True)
    row = classify_one(
        serial.Serial(args.port, args.baud, timeout=args.timeout),
        args.image,
        args.label,
    )
    row = {"sample_id": args.image.stem, **row}
    fields = [
        "sample_id", "source_path", "expected_label", "fpga_digit", "accepted",
        "confidence", "margin", "cycles", "transport_ms", "correct", "error",
    ]
    exists = args.csv.exists()
    with args.csv.open("a", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        if not exists:
            writer.writeheader()
        writer.writerow(row)
    print(row)


if __name__ == "__main__":
    main()
