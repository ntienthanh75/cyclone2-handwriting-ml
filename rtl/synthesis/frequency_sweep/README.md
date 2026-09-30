# Clock-frequency synthesis sweep

This experiment uses the principal SystemVerilog RTL source
`rtl/ml_inference.sv`, target `EP2C5T144C8`, and the same generated MIF
weights. Each frequency has its own Quartus project and SDC constraint.

The **slow timing model** is used for the decision because it is the
conservative Cyclone II corner. Positive setup and hold slack means the timing
requirement passed for that corner.

| Clock | Period | Slow setup slack | Slow hold slack | Result |
|---:|---:|---:|---:|---|
| 5 MHz | 200 ns | +76.426 ns | +0.499 ns | PASS |
| 8 MHz | 125 ns | +1.438 ns | +0.499 ns | PASS, marginal |
| 10 MHz | 100 ns | -32.507 ns | +0.499 ns | FAIL |
| 20 MHz | 50 ns | -69.922 ns | +0.499 ns | FAIL |
| 50 MHz | 20 ns | -101.821 ns | +0.499 ns | FAIL |

The fast-model setup slack was positive at 8, 10, and 20 MHz, but that does
not override the slow-model failure. Placement can also make the exact slack
non-linear between frequency points.

## Conclusion

The current unpipelined reference core is timing-clean at 5 MHz and barely
passes at 8 MHz. Use 5 MHz as the conservative temporary clock for hardware
experiments. Do not use 10 MHz or higher until the MAC datapath is pipelined
or otherwise shortened.

## Reproduction

```powershell
cd D:\fpga\cyclone2-handwriting-ml\rtl\synthesis\frequency_sweep
& 'D:\Program\altera\13.0sp1\quartus\bin64\quartus_sh.exe' --flow compile freq_5mhz
& 'D:\Program\altera\13.0sp1\quartus\bin64\quartus_sh.exe' --flow compile freq_8mhz
& 'D:\Program\altera\13.0sp1\quartus\bin64\quartus_sh.exe' --flow compile freq_10mhz
& 'D:\Program\altera\13.0sp1\quartus\bin64\quartus_sh.exe' --flow compile freq_20mhz
```

The 50 MHz result is from `rtl/ml_inference.sta.rpt`.
