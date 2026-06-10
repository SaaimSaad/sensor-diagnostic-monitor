# Requirements — Sensor Diagnostic Monitor

Requirements are written to be testable and individually traceable to design
elements and test cases. IDs follow `REQ-DIAG-###`. Each maps to a verification
method (analysis / MIL test / SIL test) in [test-plan.md](test-plan.md).

## Interface

The monitor is a discrete component running at `Ts = 0.01 s` (100 Hz).

| Direction | Signal | Type / units | Range | Notes |
|---|---|---|---|---|
| In | `v1` | single, V | 0 … 5 | Primary sensor (APP1) electrical level |
| In | `v2` | single, V | 0 … 5 | Redundant sensor (APP2), half-scale |
| In | `rpm` | single, rpm | 0 … 7000 | Operating point (freeze-frame) |
| In | `load` | single, % | 0 … 100 | Operating point (freeze-frame) |
| In | `ect` | single, °C | −40 … 130 | Coolant temp (enable condition) |
| Out | `state` | uint8 (enum) | 0 … 3 | `NO_FAULT, PENDING, CONFIRMED, HEALING` |
| Out | `dtc` | uint8 | 0 … 255 | 0 = no fault; bit0 range, bit1 rate, bit2 correlation |
| Out | `mil` | boolean | 0 / 1 | Malfunction indicator lamp |
| Out | `ff_valid` | boolean | 0 / 1 | Freeze-frame captured & valid |

## Rationality (test) requirements

| ID | Type | Requirement | Verification |
|---|---|---|---|
| **REQ-DIAG-001** | Functional | The monitor shall flag a **range** fault when the primary sensor is electrically out of range (`v1 < v_oor_lo` or `v1 > v_oor_hi`). | MIL: `tc_range` · `verify_diag_logic.js` |
| **REQ-DIAG-002** | Functional | The monitor shall flag a **rate** fault when the primary sensor changes by more than `dv_max` between consecutive samples (spike / implausible step). | MIL: `tc_rate` · `verify_diag_logic.js` |
| **REQ-DIAG-003** | Functional | The monitor shall flag a **correlation** fault when the normalised primary and redundant signals disagree by more than `corr_tol`. | MIL: `tc_corr` · `verify_diag_logic.js` |

## Confirmation / DTC requirements

| ID | Type | Requirement | Verification |
|---|---|---|---|
| **REQ-DIAG-004** | Safety / Robustness | A fault shall be **CONFIRMED** only after a monitored test fails for `confirm_cnt` debounced samples; a single-sample glitch shall **never** confirm a DTC or light the MIL. | MIL: `tc_confirm`, `tc_glitch` |
| **REQ-DIAG-005** | Functional | While a detected fault is below the confirmation threshold the monitor shall report **PENDING** (an unconfirmed/“pending” DTC), with the MIL off. | MIL: `tc_confirm` |
| **REQ-DIAG-006** | Functional | On confirmation the monitor shall capture a **freeze-frame** snapshot of the operating point (`rpm`, `load`, `ect`, the sensor values, and the tripping test code) and latch `ff_valid`. | MIL: `tc_confirm` |
| **REQ-DIAG-007** | Functional | The **MIL** shall be on if and only if at least one DTC is confirmed (it remains on through HEALING until the fault is cleared). | MIL: `tc_confirm`, `tc_heal` |
| **REQ-DIAG-008** | Functional | A confirmed DTC shall **heal** (clear, MIL off, freeze-frame released, DTC archived to history) only after `heal_cnt` consecutive clean samples — standing in for the OBD "N consecutive clean warm-up cycles." A re-failure during HEALING shall re-confirm the DTC. | MIL: `tc_heal` |

## Mode / enable requirements

| ID | Type | Requirement | Verification |
|---|---|---|---|
| **REQ-DIAG-009** | Functional | The monitor shall run its tests and accumulate failures **only** when enable conditions are met (`ect ≥ warm_min`); when disabled, the fail counter shall be frozen so cold-start transients cannot set a code. | MIL: `tc_enable` |
| **REQ-DIAG-010** | Interface | The component shall conform to the interface table above; outputs shall remain within their declared ranges at all times (`state ∈ [0,3]`, `mil ∈ {0,1}`, `dtc ∈ [0,255]`). | Analysis + range checks in all MIL tests |

## Derived design constraints

- The three rationality tests share one debounced fail counter (`confirm_cnt`),
  saturating at the confirmation threshold; on a clean sample the counter decrements
  toward zero (so brief noise ages out without confirming).
- The DTC is a bitfield so multiple tests can be attributed to one confirmed fault.
- The freeze-frame is captured **once**, at the first confirmation, and released only
  on heal (it records the conditions present when the fault was first confirmed).
- Healing is gated on enable conditions, exactly as accumulation is.

> Numeric values for `Ts`, thresholds, and counters live in `matlab/diag_params.m`
> so requirements and implementation share one source of truth.
