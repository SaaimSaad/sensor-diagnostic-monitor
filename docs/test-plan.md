# Test Plan — Sensor Diagnostic Monitor

Verification is performed at **MIL** (model-in-the-loop) and **SIL**
(software-in-the-loop), with **structural coverage** collected during MIL. Every test
case traces back to one or more requirements in [requirements.md](requirements.md). The
monitor logic is additionally re-proven headlessly by `verify_diag_logic.js`,
independent of Simulink.

## Coverage targets

| Metric | Target |
|---|---|
| Decision | 100 % |
| Condition | 100 % |
| MCDC (modified condition / decision) | 100 % |

Coverage is collected by `matlab/collect_coverage.m` and exported as an HTML report.
Any gaps are closed by adding test cases (not by disabling checks).

## Test cases

| ID | Scenario | Stimulus | Pass criteria | Traces to |
|---|---|---|---|---|
| **tc_range** | Electrical out-of-range | `v1` driven > `v_oor_hi` (and < `v_oor_lo`), warm engine | `range_bad` set; bit0 of `dtc` after confirmation | REQ-DIAG-001 |
| **tc_rate** | Implausible step | `v1` jumps by > `dv_max` in one sample | `rate_bad` set; bit1 of `dtc` | REQ-DIAG-002 |
| **tc_corr** | Single-channel drift | `pct1` and `pct2` forced apart by > `corr_tol`, both in range | `corr_bad` set; bit2 of `dtc` | REQ-DIAG-003 |
| **tc_confirm** | Confirmation + freeze-frame | Sustained range fault for ≥ `confirm_cnt` samples | PENDING then CONFIRMED at `confirm_cnt` (200 ms); freeze-frame valid; MIL on | REQ-DIAG-004/005/006/007 |
| **tc_glitch** | Single-sample glitch | One bad sample, then clean | Never CONFIRMED; MIL stays off; returns to NO_FAULT | REQ-DIAG-004 |
| **tc_heal** | Healing | Confirm a fault, then clean for ≥ `heal_cnt` samples | Heals to NO_FAULT; MIL off; DTC archived; re-fail during HEALING re-confirms | REQ-DIAG-008 |
| **tc_enable** | Disabled (cold) | Sustained fault with `ect < warm_min` | No confirmation; `failCnt` frozen at 0; MIL off | REQ-DIAG-009 |
| **tc_range_out** | Output range | All of the above | `state ∈ [0,3]`, `mil ∈ {0,1}`, `dtc ∈ [0,255]` at every step | REQ-DIAG-010 |

## MIL procedure (`run_mil.m`)

1. `diag_params` then `build_model` to ensure `diag_monitor.slx` exists.
2. For each test case, set inputs, run `sim`, and evaluate pass criteria with assertions.
3. Plot the test results, the fail counter, `state`, and `mil` for visual inspection.
4. Print a pass/fail summary table mapping test cases to requirements.

## SIL procedure (`run_sil.m`)

1. `gen_code` to generate C for the monitor subsystem.
2. Run the `tc_confirm` and `tc_heal` stimuli through the SIL block.
3. Assert MIL vs SIL output equivalence (`state`, `dtc`, `mil` identical).

## Coverage procedure (`collect_coverage.m`)

1. Enable decision / condition / MCDC recording.
2. Run the full test suite as a single coverage session.
3. Export the HTML report to `../assets/coverage/`.
4. Fail the run if any metric is below target.
