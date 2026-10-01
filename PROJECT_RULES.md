# Rules for New Cyclone II FPGA Repositories

These rules keep the repositories coherent inside the private GitHub project
**Cyclone II FPGA Board**.

## 1. Naming

- Every repository name starts with `cyclone2-`.
- Use lowercase kebab-case after the prefix.
- Name the repository by its main function, for example:
  - `cyclone2-lcd-photo`
  - `cyclone2-lcd-touch`
  - `cyclone2-joystick-leds`
  - `cyclone2-handwriting-ml`
- Do not use the generic word `project` in repository names.
- The GitHub Project is the collection; each repository is one independent
  subproject inside it.
- Existing repositories may retain their historical names unless explicitly
  renamed, but all new repositories follow this rule.

## 2. Target hardware declaration

The canonical shared board document is
<https://github.com/ntienthanh75/fpga-cyclone2-5led/blob/main/docs/board-spec.md>.
New repositories should link to it rather than copy a second board
specification.

Every repository README must state the target explicitly:

```text
Board: Waveshare CoreEP2C5 / CoreEP2C5 USB development board
FPGA: Altera/Intel Cyclone II EP2C5T144C8
Package: TQFP-144
Clock: state the actual board clock and the design frequency
Programming: USB-Blaster/JTAG
```

If an add-on is used, identify it separately: LCD, touch controller,
joystick, CY7C68013A FX2 USB board, SDRAM board, or UART adapter.

## 3. Local directory layout

- Store active FPGA work under `D:\fpga\<repository-name>`.
- Install new tools under `D:\Programs` or another D: drive location.
- Do not install new tools or create project work under `C:` unless a Windows
  installer requires a system component there.
- Keep each repository self-contained and do not silently reuse generated
  files from another repository.

## 4. Required README content

Each repository must contain a README before it is considered complete. It
must explain:

- purpose and scope;
- target board and exact FPGA part;
- external wiring and pin assignments;
- clock frequency, reset polarity, and default buzzer state;
- source files created or modified and how they were created;
- Quartus version and programming command;
- exact steps to compile and download the `.sof`;
- expected board behavior and a hardware test procedure;
- known limitations, warnings, and unresolved issues;
- how to reproduce verification and synthesis results.

The README must not claim hardware success when only simulation or synthesis
has been completed.

## 5. RTL and verification defaults

- Use SystemVerilog as the principal RTL language for new designs.
- Keep UVM or the existing verification flow for reusable ML/datapath blocks.
- Separate hardware-specific wrappers from reusable cores.
- Keep LCD, USB, UART, joystick, and ML interfaces as separate modules where
  practical.
- Default the buzzer to muted (`buzz=1'b1` for the active-low buzzer used on
  the board) unless the user explicitly requests sound.
- Add a small self-checking test or golden-vector test for every new data
  path.

## 6. Synthesis archive rules

- Store synthesis experiments under `rtl/synthesis/`.
- Never overwrite an earlier experiment; use a unique descriptive folder.
- Preserve the source revision, `.qsf`, `.sdc`, `.map.rpt`, `.fit.rpt`,
  `.sta.rpt`, `.flow.rpt`, and `.sof` when available.
- Record device, frequency, resource use, setup slack, hold slack, latency,
  warnings, and the reason an option was selected or rejected.
- Compare resource usage only between builds using the same device, weights,
  source variant, and timing constraint.

## 7. Git and GitHub rules

- Keep the repositories inside the private GitHub Project **Cyclone II FPGA
  Board**.
- Commit source, documentation, reproducible scripts, selected reports, and
  final programming files when useful.
- Do not commit large temporary Quartus databases, UVM work directories, or
  unrelated generated files unless explicitly needed as a reference.
- Use descriptive commits, for example:
  `Add 5 MHz FX2 streaming ML bridge`.
- Push only after the local build/test status is recorded in the README.
- Do not place a personal signature or author name in source files unless the
  user explicitly requests it.

## 8. Completion checklist

Before closing a new repository task, verify:

1. consistent `cyclone2-` name;
2. README with target board and download instructions;
3. source and pin constraints compile successfully;
4. synthesis results archived and explained;
5. simulation/UVM or software test result recorded;
6. buzzer default is muted;
7. local commit created;
8. GitHub push completed or authentication failure clearly reported;
9. repository linked to the private **Cyclone II FPGA Board** project.
