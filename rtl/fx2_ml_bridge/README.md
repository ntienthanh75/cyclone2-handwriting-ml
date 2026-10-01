# CY7C68013A USB-FIFO ML bridge

This is the board-level runtime wrapper for the CoreEP2C5 USB interface. It
reuses the proven pin assignments from the existing `USB_LED` project:

- `EP2 OUT`, `FIFOADR=00`: PC to FPGA input
- `EP6 IN`, `FIFOADR=10`: FPGA to PC result
- 16-bit FX2 data bus
- board clock on pin 17; the ML step scheduler runs at an exact 5 MHz rate
- active-low reset on pin 88

The FPGA is configured with USB-Blaster/JTAG. Runtime image transfer uses the
CY7C68013A WinUSB device, not UART and not the LCD.

## Runtime packet

The PC writes 99 little-endian 16-bit words to EP2:

1. `0xA5A5` frame marker
2. 98 words, each containing two 4-bit pixels:
   - pixel `2*n` in bits `[3:0]`
   - pixel `2*n+1` in bits `[11:8]`

The FPGA writes six 16-bit words to EP6:

1. `0x5A5A`
2. digit in `[3:0]`, accepted in bit `[8]`
3. confidence in `[7:0]`
4. margin
5. processing cycles `[15:0]`
6. processing cycles `[31:16]`

`accepted=0` means `NON_RECOGNIZABLE`.

The board USB/FIFO wrapper uses the 50 MHz board clock for the FX2 interface
and advances the ML core at 5 MHz using a clock-enable scheduler. This is an
intentional hardware choice: the direct 8 MHz PLL configuration is not legal
on this Cyclone II PLL, while 5 MHz provides a clean ten-cycle multicycle
timing budget and remains fast enough for one-image benchmarking.

The USB device currently appears in Windows as `EZ-USB FX2`, VID `0547`, PID
`1002`, using the installed WinUSB driver and interface GUID
`{8f2f6d1e-5c4c-4bc4-a2d2-6b5a6fce7a21}`.

This project must be compiled and tested against the actual FX2 firmware before
the result packet is considered hardware-validated. The older VHDL USB LED
project proves the electrical pin mapping, but not this ML packet format.

## Board-free validation

When the board is not connected, run:

```powershell
C:\Python313\python.exe D:\fpga\cyclone2-handwriting-ml\python\fx2_protocol_test.py --write D:\fpga\cyclone2-handwriting-ml\rtl\fx2_ml_bridge\four_points_frame.txt
```

This checks the `A5A5 + 98 words` frame length, 4-bit pixel packing, row-major
pixel order, and result-word decoding. It does not replace the final hardware
test: USB-Blaster programming and live WinUSB endpoint traffic require the
board and CY7C68013A connection.
