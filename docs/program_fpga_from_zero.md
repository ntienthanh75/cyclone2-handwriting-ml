# Program the Cyclone II ML core from zero

This guide loads the complete FPGA image used by the handwriting recognizer.
The image is a Quartus `.sof` file containing the FX2 USB bridge, the ML
inference RTL, ROM weights, clock/reset logic, and board pin assignments.
There is no separate “ML core download” step and Nios is not required.

## Step 1 — Prepare the hardware and software

Use:

- CoreEP2C5 Cyclone II board, powered on
- USB-Blaster connected to the board JTAG header and this PC
- CY7C68013A FX2 USB board connected to the FX2/FIFO header
- Quartus Programmer installed under `D:\altera\24.1std`
- This repository under `D:\fpga\cyclone2-handwriting-ml`

The USB-Blaster is used only to load the FPGA. The CY7C68013A is a separate
runtime USB data path for sending image frames and receiving digit results.

## Step 2 — Confirm the USB-Blaster and FPGA

Open PowerShell and run:

```powershell
& 'D:\altera\24.1std\qprogrammer\bin64\jtagconfig.exe'
```

Expected output contains:

```text
1) USB-Blaster [USB-0]
  020B10DD  EP2C5
```

If no USB-Blaster appears, fix its Windows driver/cable/power connection
before opening Programmer. Do not use the FX2 USB device as a substitute for
the USB-Blaster.

## Step 3 — Choose the correct SOF

The ready-to-program image is:

```text
D:\fpga\cyclone2-handwriting-ml\rtl\fx2_ml_bridge\fx2_ml_bridge.sof
```

This image was built for the `EP2C5T144` device. A `.sof` is volatile SRAM
configuration: it is lost when the FPGA board is powered off or reset. The
image must be programmed again after a power cycle unless a configuration
flash image is intentionally created and programmed.

## Step 4 — Program the FPGA: choose one method

After completing Steps 1–3, choose either Step 4A or Step 4B below. They are
alternative methods; do not program the same SOF twice.

### Step 4A — Program from the command line

This is the shortest repeatable method:

```powershell
& 'D:\altera\24.1std\qprogrammer\bin64\quartus_pgm.exe' `
  --no_banner -m JTAG -c 'USB-Blaster [USB-0]' `
  -o 'p;D:\fpga\cyclone2-handwriting-ml\rtl\fx2_ml_bridge\fx2_ml_bridge.sof'
```

Success ends with:

```text
Configuration succeeded -- 1 device(s) configured
Successfully performed operation(s)
```

Programming the FPGA does not start the PC UI and does not send an image. It
only puts the bridge and ML hardware into the Cyclone II configuration SRAM.

### Step 4B — Alternative programming method: Quartus Programmer UI

1. Start **Quartus Prime Programmer**.
2. Select **Hardware Setup** and choose `USB-Blaster [USB-0]`.
3. Set mode to **JTAG**.
4. Click **Auto Detect**.
5. The chain must contain one device: `EP2C5T144`/`EP2C5`.
6. If an old second device appears, select it and click **Delete**. It is a
   stale chain entry, not evidence that a second FPGA is connected.
7. Click **Add File** and select the SOF path above.
8. Check **Program/Configure** on the EP2C5T144 row.
9. Click **Start** and wait for the green 100% success message.

The error `expected 2 device(s) but found 1 device(s)` means the `.cdf` chain
file contains a stale extra device. Delete the extra row, or create a fresh
one-device chain with Auto Detect, then add the SOF again.

## Step 5 — Connect the runtime FX2 path and run the UI

After the FPGA has been programmed:

1. Keep the board powered and connect the CY7C68013A USB cable.
2. Confirm Windows shows the FX2 WinUSB interface. The expected device is
   `EZ-USB FX2`, VID `0547`, PID `1002`.
3. Start the UI from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File `
  D:\fpga\cyclone2-handwriting-ml\run_fx2_ml_ui.ps1
```

4. Follow the buttons from left to right:

   - **1. Connect FX2**: opens the CY7C68013A WinUSB interface. The log
     should show an OUT endpoint, normally `OUT 0x02`, and an IN endpoint,
     normally `IN 0x86`. This button does not program the FPGA.
   - **2A. Four-point test**: loads a built-in diagnostic frame with four
     black pixels. It only changes the preview; it does not send anything.
   - **2B. Load MNIST sample**: loads a labeled sample from the local MNIST
     test set. The label is shown beside the preview for comparison.
   - **2C. Choose photo**: opens a file picker for one handwriting image and
     applies the same photo normalization used by the benchmark.
   - **3. Send sample to FPGA**: sends the currently displayed 14×14 frame,
     waits for the FPGA response, and displays the recognized digit.

5. For the first test, click **1. Connect FX2**, then **2A. Four-point test**,
   then **3. Send sample to FPGA**.
6. The log should show sending 99 words, receiving six result words, and then
   show a digit, confidence, margin, FPGA cycles, and round-trip time.
7. After the diagnostic succeeds, use **2B** or **2C** and send the new sample
   with **3. Send sample to FPGA**.

If the first response is incomplete or times out, the UI automatically closes
and reopens the FX2 interface and retries the same transaction up to two times.
The log shows each recovery. If all three attempts fail, reprogram the SOF
using Step 4A or 4B, reconnect the FX2, and repeat Step 5.

The request is 99 little-endian 16-bit words (198 bytes). The FPGA returns a
24-byte packet containing two redundant six-word result frames. `accepted=0`
is displayed as `NON-RECOGNIZABLE`.

## Optional Step 6 — Rebuild the SOF after RTL changes

Use this only when changing RTL or constraints. The installed Quartus II
13.0sp1 toolchain is the compatible compiler for this Cyclone II project:

```powershell
Set-Location D:\fpga\cyclone2-handwriting-ml\rtl\fx2_ml_bridge
& 'D:\Program\altera\13.0sp1\quartus\bin64\quartus_sh.exe' `
  --flow compile fx2_ml_bridge
```

After a successful build, program the newly generated:

```text
D:\fpga\cyclone2-handwriting-ml\rtl\fx2_ml_bridge\fx2_ml_bridge.sof
```

Do not program a `.pof` or `.jdi` when the immediate goal is volatile JTAG
configuration. The `.sof` is the correct file for **Program/Configure** in
JTAG mode.

## Step 7 — Troubleshooting checklist

| Symptom | Meaning | Action |
|---|---|---|
| `jtagconfig` finds nothing | USB-Blaster/JTAG path unavailable | Check power, JTAG cable, and driver |
| Chain expects two devices | Stale `.cdf` entry | Delete the extra device and Auto Detect again |
| Programmer succeeds but UI cannot connect | FX2 runtime path unavailable | Check FX2 cable, firmware, and WinUSB driver |
| `WinUSB interface not found` | FX2 is not enumerated with the expected driver | Reconnect FX2 and check Device Manager |
| UI sends but times out | FPGA image, FX2 firmware, or FIFO path is not running | Reprogram SOF, reconnect FX2, click Connect FX2 again |
| FPGA works until restart | `.sof` configuration is volatile | Program the SOF again after power/reset, or later create a flash image |

The complete flow is:

```text
USB-Blaster + Quartus Programmer
        -> fx2_ml_bridge.sof into EP2C5 FPGA
CY7C68013A FX2 WinUSB
        -> 99-word image frame into FPGA
FPGA ML core
        -> 24-byte result packet back to PC UI
```
