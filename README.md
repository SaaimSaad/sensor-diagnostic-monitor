# Sensor Diagnostic Monitor

> **OBD-style redundant-sensor diagnostic monitor — model-based design (Simulink/Stateflow
> model-as-code → generated C → MIL/SIL, MCDC coverage, AUTOSAR SWC).**

A model-based design (MBD) of an **OBD-style sensor diagnostic monitor** for a
safety-relevant redundant sensor pair, built the way production powertrain
diagnostics are built: requirements → Simulink/Stateflow model → generated C →
MIL/SIL verification with structural coverage.

It runs range / rate / cross-correlation **rationality tests** every sample,
**debounces** failures so a single glitch never trips a code, and manages the full
DTC lifecycle (`NO_FAULT → PENDING → CONFIRMED → HEALING`) — including freeze-frame
capture, MIL control, and healing — through a Stateflow machine.

The monitor is defined **as code** — `matlab/build_model.m` constructs the Simulink
model and the Stateflow fault-state machine programmatically through the Simulink
API, so the design is reviewable, diffable, and version-controlled rather than living
in an opaque binary `.slx`.

This is one of a set of automotive MBD projects following the same
requirements → model-as-code → generated C → MIL/SIL → coverage workflow:

- **[boost-pressure-control](https://github.com/SaaimSaad/boost-pressure-control)** — diesel
  turbocharger boost-pressure (air-path) PI + feed-forward controller.
- **[torque-safety-monitor](https://github.com/SaaimSaad/torque-safety-monitor)** — ISO 26262 /
  E-Gas 3-level functional-safety torque monitor.

> **This is an original, generic design** derived from public OBD / diagnostic
> first principles (range / rate / correlation rationality, debounced fault
> confirmation, freeze-frame, healing). It contains no employer/client signals,
> calibrations, requirements, or proprietary structure.

---

## What it does

A redundant analog position sensor pair (e.g. an accelerator-pedal sensor, APP1 /
APP2) is monitored for plausibility. The monitor:

- runs three **rationality tests** every sample — electrical **range** (out-of-range),
  **rate** (implausible step / spike), and **cross-signal correlation** (the primary
  and redundant sensor must agree within tolerance);
- **debounces** failures: a fault is only **CONFIRMED** after it persists for a
  calibrated number of samples — a single-sample glitch never trips it;
- manages **DTC** state through a Stateflow machine (`NO_FAULT → PENDING →
  CONFIRMED → HEALING`), captures a **freeze-frame** of the operating point at
  confirmation, and drives the **MIL** (malfunction lamp);
- **heals** a confirmed fault only after a sustained clean run (standing in for the
  OBD "N consecutive clean warm-up cycles"), then archives the DTC and clears the MIL;
- runs its tests only when **enable conditions** are met (warm engine / valid
  operating region), so cold-start transients never set a code.

See [docs/design.md](docs/design.md) for the monitor logic and rationale, and
[docs/requirements.md](docs/requirements.md) for the traceable requirements.

---

## Repository layout

```
sensor-diagnostic-monitor/
├── README.md
├── docs/
│   ├── requirements.md      # REQ-DIAG-### requirements + traceability
│   ├── design.md            # rationality tests, state machine, freeze-frame, healing
│   └── test-plan.md         # MIL/SIL scenarios + coverage targets
├── matlab/
│   ├── diag_params.m        # single source of monitor parameters (base workspace)
│   ├── diag_const.m         # code-gen-friendly constant companion (mirrors diag_params)
│   ├── build_model.m        # builds the Simulink + Stateflow model via API
│   ├── run_mil.m            # MIL simulation, requirement checks, plots
│   ├── run_sil.m            # SIL build + MIL/SIL equivalence
│   ├── gen_code.m           # Embedded Coder configuration + code generation
│   ├── collect_coverage.m   # decision / condition / MCDC coverage + report
│   └── test/
│       └── test_diag_monitor.m  # requirement-linked reference tests
├── autosar/
│   └── DiagMonitor.arxml    # hand-authored AUTOSAR Classic SWC description
├── generated/               # generated C output (created by gen_code.m)
├── assets/                  # exported model + coverage screenshots
└── verify_diag_logic.js     # headless requirement check (no MATLAB needed)
```

---

## How to verify it today (no MATLAB required)

The monitor logic is re-proven headlessly, independent of Simulink:

```bash
node verify_diag_logic.js
```

```
=== Sensor-diagnostic-monitor logic verification ===
[PASS]  REQ-DIAG-001 range/OOR detected
[PASS]  REQ-DIAG-002 rate/spike detected
[PASS]  REQ-DIAG-003 correlation fault detected
[PASS]  REQ-DIAG-004 confirms at threshold             pending→confirmed at 20 samples (200 ms)
[PASS]  REQ-DIAG-004 no false trip on 1-sample glitch
[PASS]  REQ-DIAG-006 freeze-frame captured
[PASS]  REQ-DIAG-007 MIL on when confirmed
[PASS]  REQ-DIAG-008 heals & MIL clears
[PASS]  REQ-DIAG-009 disabled: no confirm when cold
[PASS]  REQ-DIAG-010 outputs in declared range
ALL CHECKS PASSED
```

The same logic runs live in the project showcase page (`sensor-diagnostics.html`).

---

## How to run the MATLAB toolchain

> **Requires a personal MATLAB** — MATLAB Home, a 30-day trial, a student licence, or
> MATLAB Online — with **Simulink, Stateflow, and Embedded Coder** (SIL/coverage also
> use Simulink Coverage). **Do not build this on an employer/client MATLAB install.**

Tested target: MATLAB R2022a or later.

```matlab
cd matlab
diag_params            % load parameters into the base workspace
build_model            % create diag_monitor.slx (Simulink + Stateflow)
run_mil                % simulate the diagnostic scenarios, check requirements
gen_code               % generate MISRA-style C into ../generated/
collect_coverage       % run coverage and export an HTML report
```

After a run, export the model diagram and coverage report into `assets/`.

---

## MBD workflow this demonstrates

| Stage | Artifact |
|---|---|
| Requirements | `docs/requirements.md` (REQ-DIAG-001 … 010) |
| Design (model-as-code) | `matlab/build_model.m` → `diag_monitor.slx` |
| Model-in-the-loop (MIL) | `matlab/run_mil.m` + requirement assertions |
| Headless logic check | `verify_diag_logic.js` (no MATLAB) |
| Code generation | `matlab/gen_code.m` → `generated/*.c/.h` (MISRA-C style) |
| Software-in-the-loop (SIL) | `matlab/run_sil.m` (MIL/SIL equivalence) |
| Structural coverage | `matlab/collect_coverage.m` (decision / condition / MCDC) |
| Architecture | `autosar/DiagMonitor.arxml` (AUTOSAR Classic SWC) |

---

## Status

- [x] Requirements, design, and test plan authored
- [x] Monitor defined as code (`build_model.m`) + parameters + test/codegen/coverage scripts
- [x] Logic re-proven headlessly (`verify_diag_logic.js`) and live in the showcase page
- [x] AUTOSAR Classic SWC description (`autosar/DiagMonitor.arxml`)
- [ ] `.slx`, generated C, and coverage report produced on a clean personal MATLAB
- [ ] Model + coverage screenshots exported to `assets/`

## Licence

MIT — see [LICENSE](LICENSE). Original work; no third-party or proprietary content.
