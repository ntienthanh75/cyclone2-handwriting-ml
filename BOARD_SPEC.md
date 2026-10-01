# Shared Cyclone II FPGA Board Specification

This is the canonical hardware specification shared by the repositories in
the private GitHub Project **Cyclone II FPGA Board**.

## Main board

| Item | Specification |
|---|---|
| Board | Waveshare CoreEP2C5 / CoreEP2C5 USB development board |
| FPGA | Altera/Intel Cyclone II `EP2C5T144C8` |
| Package | TQFP-144 |
| FPGA family | Cyclone II |
| Main board clock | 50 MHz, FPGA pin 17 (`CLK`) |
| Reset | Active-low reset, FPGA pin 88 (`RESET`) |
| User LEDs | FPGA pins 8, 9, 24, 25; normally `LED[0]..LED[3]` |
| Buzzer | Primary buzzer output FPGA pin 4; active-low, default muted with logic `1` |
| Configuration | USB-Blaster/JTAG into the board JTAG header |
| Configuration file | Quartus `.sof` downloaded to SRAM; power cycling loses the image unless flash programming is used |
| FPGA tools | Quartus II 13.0sp1 for Cyclone II compilation; Quartus Programmer 24.1 also works for JTAG programming |

The 50 MHz value is the physical board clock. A design frequency such as
8 MHz or 5 MHz is a derived processing rate or clock-enable rate and must not
be confused with the board oscillator.

## Connected hardware stack

The working setup can contain all of the following at the same time:

```text
PC
├── USB-Blaster ── JTAG ── CoreEP2C5 FPGA configuration
├── CY7C68013A FX2 USB board ── 16-bit FIFO ── CoreEP2C5 FPGA runtime data
└── optional USB-UART adapter ── UART pins ── CoreEP2C5 FPGA runtime data

CoreEP2C5 expansion headers
├── 3.2-inch 320x240 ILI9325 LCD/touch module
├── SDRAM board (used by the Nios/LCD design)
└── joystick or other GPIO accessory (pin assignment is project-specific)
```

USB-Blaster/JTAG is the programming and debug path. It is not automatically
the runtime image-data path. The CY7C68013A is a separate WinUSB/FIFO data
path. The LCD is a parallel display plus SPI touch-controller path. These
interfaces must not share FPGA pins in one Quartus project unless the design
explicitly multiplexes them.

## LCD and touch module

The following assignments are confirmed by the existing `lcd_photo_hdl` and
`lcd_touch` Quartus projects. The module is a 3.2-inch 320x240 TFT LCD with a
16-bit parallel ILI9325-style display bus and an SPI resistive touch
controller.

### LCD parallel bus

| Signal | FPGA pin |
|---|---:|
| `LCD_DATA[0]..[15]` | 93, 94, 96, 97, 99, 100, 101, 103, 104, 112, 113, 114, 115, 118, 119, 120 |
| `LCD_CS` | 121 |
| `LCD_RS` / command-data | 122 |
| `LCD_WR` | 125 |
| `LCD_RD` | 126 |
| `LCD_RST` | 132 |

The LCD data bus is bidirectional because display writes and optional display
reads use the same 16 pins. Most drawing designs should keep `LCD_RD` high
and drive the display through write cycles.

### Touch controller SPI

| Signal | FPGA pin |
|---|---:|
| `TOUCH_CS` | 134 |
| `TOUCH_IRQ` | 129 |
| `TOUCH_SCLK` | 133 |
| `TOUCH_MOSI` | 136 |
| `TOUCH_MISO` | 135 |

The touch controller is separate from the LCD pixel bus. A design that only
draws pixels may leave the touch signals inactive; a touch design must also
implement the SPI transaction timing and IRQ handling.

## CY7C68013A FX2 USB FIFO

The existing CoreEP2C5 USB LED project and the current ML bridge confirm the
following FPGA-side FIFO assignments:

| Signal | FPGA pin |
|---|---:|
| `clk` | 17 |
| `rst` | 88 |
| `FIFOADR[0]`, `FIFOADR[1]` | 75, 76 |
| `FIFODATA[0..15]` | 81, 86, 87, 92, 93, 94, 96, 97, 99, 100, 101, 103, 104, 112, 113, 114 |
| `SLWR` | 73 |
| `SLOE` | 72 |
| `SLRD` | 74 |
| `FLAGA` | 71 |
| `FLAGB` | 79 |
| `FLAGC` | 80 |

For the ML bridge:

- `FIFOADR=00` selects EP2 OUT, PC to FPGA.
- `FIFOADR=10` selects EP6 IN, FPGA to PC.
- The PC sends `0xA5A5` plus 98 16-bit words containing two 4-bit pixels.
- The FPGA returns `0x5A5A` plus digit, confidence, margin, and cycle count.
- The current bridge uses the 50 MHz board clock and a 5 MHz ML clock-enable
  schedule; it does not use the LCD or Nios II.

The CY7C68013A is detected by Windows as `EZ-USB FX2`, VID `0547`, PID
`1002`, with the installed WinUSB interface GUID:

```text
{8f2f6d1e-5c4c-4bc4-a2d2-6b5a6fce7a21}
```

## SDRAM board

The attached SDRAM board is used by the existing Nios/LCD design. Its
assignments are preserved in `D:\fpga\lcd_touch\synthesis\lcd_nios.qsf`.
The interface includes:

- 16-bit `DQ` data bus;
- row/address bus `RA`;
- bank address `BA[1:0]`;
- `RAS`, `CAS`, `WE`, `CS`, `CKE`, `S_CLK`, and byte-mask signals.

SDRAM is not part of the direct FX2 ML bridge. A project must not reuse these
pins for LCD, FX2, or UART signals in the same Quartus revision.

## Joystick and UART status

The joystick is physically an optional GPIO accessory, but a single canonical
pin map has not yet been confirmed in the current project files. New joystick
projects must document the exact header pin, direction, pull-up/pull-down,
active level, and debounce method before programming hardware.

The UART adapter is also optional. Its RX/TX FPGA pins are project-specific
and must be declared in the QSF and README. Do not assume that the FX2 FIFO
pins or LCD pins are UART pins.

## Resource and connection rules

1. One Quartus revision must use one explicit pin map; do not merge QSF files
   from LCD, SDRAM, FX2, and UART designs without checking conflicts.
2. Every repository README must link to this file and list only the signals it
   actually uses.
3. Keep the buzzer muted by default.
4. Treat USB-Blaster/JTAG as configuration/debug and FX2/UART as runtime data
   interfaces unless the design documents a different choice.
5. Preserve the original synthesis reports and pin files under
   `rtl/synthesis/` for every hardware variant.

## Source of truth

Confirmed assignments come from these local projects:

- `D:\fpga\lcd_photo_hdl\lcd_photo_hdl.qsf` — LCD and touch pins;
- `D:\fpga\lcd_touch\synthesis\lcd_nios.qsf` — LCD, touch, SDRAM, LEDs, and buzzer;
- `rtl/fx2_ml_bridge/fx2_ml_bridge.qsf` — CY7C68013A FX2 FIFO pins;
- the existing CoreEP2C5 `USB_LED` project — proven FX2 electrical mapping.

If a future board revision differs, create a new board-revision section and
do not silently change these assignments.
