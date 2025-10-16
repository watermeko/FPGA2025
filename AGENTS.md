# Repository Guidelines

## Project Structure & Module Organization
- `rtl/` contains synthesizable Verilog/SystemVerilog; use subfolders (such as `dds/` or `clk/`) to mirror logical blocks and keep shared primitives near the root.
- `tb/` holds self-contained benches named `<module>_tb.sv`; stage helpers beside the bench to prevent cross-module coupling.
- `sim/` stores ModelSim setups; each module has its own folder with `run_sim.do`, Gowin library bootstrap scripts, and captured logs.
- `constraints/` collects device pin/timing files; document device variants and clock sources whenever edits are made.
- `software/` hosts the PC-side tooling that speaks the USB/UART protocol; sync protocol changes with matching RTL updates.
- `doc/` tracks design notes; treat generated folders such as `impl/` and `transcript/` as disposable artifacts.

## Build, Test, and Development Commands
- Launch Gowin FPGA Designer and open `fpga_project.gprj` for synth/place/route; the IDE regenerates `impl/` and timing reports.
- For headless builds, run `gowinsh -batch fpga_project.gprj` from the repo root to execute the default project flow.
- Execute simulations with `vsim -c -do sim/<bench>/run_sim.do`; the script auto-compiles Gowin libraries via `compile_gowin_lib.do` before invoking `cmd_*.do`.

## Coding Style & Naming Conventions
- Indent RTL with four spaces; align port declarations and parameter lists for readability.
- Name modules, files, and signals in `lower_snake_case`; reserve all-caps for parameters and macro constants.
- Prefer `logic` for SystemVerilog nets, keep synchronous blocks `always_ff`, and use `// --- Section ---` headers when grouping logic.
- Run `vlog -sv` on touched files before committing.

## Testing Guidelines
- Mirror every synthesizable module with a `<module>_tb.sv` bench in `tb/`; keep stimulus sequences in tasks for reuse.
- Capture new benches under `sim/<module>_tb/` by copying an existing folder and updating `run_sim.do`.
- Commit key artifacts: pass/fail logs and configuration notes; omit heavy VCDs unless they document a regression.
- Cover CDC and protocol edges; note remaining gaps in the pull request.

## Commit & Pull Request Guidelines
- Follow the existing history pattern: `[TYPE] Short present-tense summary` (e.g., `[FEATURE] Add CDC upload path`); use `[FIX]`, `[DOC]`, `[REFINE]`, or `[CHORE]` as needed.
- Reference tracking issues in the body and call out interface or constraint updates explicitly.
- PRs should list affected modules, describe verification evidence (command log or waveform snapshot), and attach screenshots for GUI or host-tool changes.

## Configuration Tips
- Keep device tweaks in `constraints/`; note board IDs in commits.
- Exclude IDE caches via `.gitignore` before opening a PR.
