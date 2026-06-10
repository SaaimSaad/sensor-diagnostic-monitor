# Design — Sensor Diagnostic Monitor

This document describes the monitored signals, the three rationality tests, the
fault-confirmation state machine, freeze-frame capture, and healing. All numeric
parameters live in [`../matlab/diag_params.m`](../matlab/diag_params.m); the same
values are mirrored in the browser simulation so both tell the same story.

## 1. Monitored signals

A safety-relevant **redundant analog position sensor pair** (e.g. an
accelerator-pedal position sensor, APP1 / APP2). Two independent transducers measure
the same mechanical quantity on different electrical scales so a single failure can be
detected by disagreement:

| Signal | Electrical | Maps to |
|---|---|---|
| `v1` (APP1, primary)   | 0.5 … 4.5 V | 0 … 100 % |
| `v2` (APP2, redundant) | 0.25 … 2.25 V (half-scale) | 0 … 100 % |

Normalisation to percent:

```
pct1 = (v1 − 0.5 ) / 4.0 · 100
pct2 = (v2 − 0.25) / 2.0 · 100
```

Using different electrical scales is deliberate: a short across the two lines, or a
common-mode supply fault, moves the two percentages apart and is caught by the
correlation test.

## 2. Rationality tests (one sample)

Three independent tests run every `Ts`; each produces a per-sample boolean and sets a
bit in the instantaneous test result:

```
range_bad = (v1 < v_oor_lo) || (v1 > v_oor_hi)             // REQ-DIAG-001, bit0
rate_bad  = |v1 − v1_prev| > dv_max                        // REQ-DIAG-002, bit1
corr_bad  = |pct1 − pct2| > corr_tol                       // REQ-DIAG-003, bit2
any_bad   = range_bad || rate_bad || corr_bad
```

| Symbol | Meaning | Nominal |
|---|---|---|
| `v_oor_lo` / `v_oor_hi` | electrical out-of-range thresholds | 0.20 V / 4.80 V |
| `dv_max` | max plausible step per sample | 1.50 V |
| `corr_tol` | max allowed `pct1` vs `pct2` mismatch | 10 % |

- **Range** catches shorts to ground / battery and open circuits (the signal parks
  outside the legitimate band, which the nominal pedal travel never reaches).
- **Rate** catches spikes, EMI bursts, and dropouts — physically impossible jumps.
- **Correlation** catches the subtler single-channel drift / stuck failures where one
  transducer is still in-range but no longer tracks the other.

## 3. Fault confirmation — debounce (REQ-DIAG-004/005)

The three tests share one **debounced fail counter**:

```
if enable
    if any_bad : failCnt = min(failCnt + 1, confirm_cnt);  healCnt = 0
    else       : failCnt = max(failCnt − 1, 0)
```

| Symbol | Meaning | Nominal |
|---|---|---|
| `confirm_cnt` | failing samples to confirm | 20 ( = 200 ms ) |
| `heal_cnt` | clean samples to heal | 300 (≈ 3 warm-up cycles) |
| `warm_min` | coolant temp enabling diagnostics | 60 °C |

A single bad sample raises `failCnt` to 1 (→ **PENDING**) and ages straight back to 0
on the next clean sample, so it **never** confirms — this is the no-false-trip property
verified by `tc_glitch` / `verify_diag_logic.js`.

## 4. Supervisor (Stateflow)

```
        ┌──────────┐  failCnt>0   ┌─────────┐  failCnt≥confirm_cnt  ┌───────────┐
  ─────▶│ NO_FAULT │ ───────────▶ │ PENDING │ ────────────────────▶ │ CONFIRMED │
        └──────────┘ ◀─────────── └─────────┘                       └───────────┘
              ▲        failCnt==0                                    ▲     │ enable
              │                                              re-fail │     │ & clean
              │      heal_cnt clean samples                 ┌────────┘     ▼
              └──────────────────────────────────────────  │         ┌─────────┐
                                                            └──────── │ HEALING │
                                                                      └─────────┘
```

- **NO_FAULT** — `failCnt == 0`. No active DTC; MIL off.
- **PENDING** — `0 < failCnt < confirm_cnt`. A pending (unconfirmed) DTC; MIL still off
  (REQ-DIAG-005). Decays back to NO_FAULT if the fault clears before confirmation.
- **CONFIRMED** — `failCnt ≥ confirm_cnt`. DTC latched (bitfield), **freeze-frame
  captured once** (REQ-DIAG-006), **MIL on** (REQ-DIAG-007).
- **HEALING** — entered from CONFIRMED once tests pass again; counts consecutive clean
  samples. A re-failure returns to CONFIRMED (REQ-DIAG-008). After `heal_cnt` clean
  samples the DTC is archived to history, the freeze-frame is released, the MIL clears,
  and the monitor returns to NO_FAULT.

The MIL stays on through HEALING — exactly like a real OBD lamp that only extinguishes
after the required clean warm-up cycles.

## 5. Freeze-frame (REQ-DIAG-006)

On the transition into CONFIRMED the monitor latches a snapshot of the conditions
present when the fault was confirmed:

```
freeze = { rpm, load, ect, v1, pct1, pct2, code = dtc, t }
```

It is captured **once** (subsequent confirmations of the same fault do not overwrite it)
and released only on heal — so a technician reads the conditions at first detection.

## 6. Enable conditions (REQ-DIAG-009)

Accumulation and healing run only when `ect ≥ warm_min`. Below that the fail counter is
frozen, so cold-start sensor settling and warm-up transients cannot set a code. In
production this gate also includes operating-region checks (plausible rpm/load window);
the model keeps the coolant-temperature gate as the representative enable condition.

## 7. Why these choices (interview notes)

- **Shared debounced counter** over per-test latches — diagnostics should confirm on
  *persistence*, not instantaneous noise; one saturating counter with decay is the
  standard, low-RAM pattern and gives a clean PENDING→CONFIRMED→HEALING story.
- **Different electrical scales for the redundant pair** — makes common-mode faults
  observable by the correlation test, not just independent opens/shorts.
- **Freeze-frame captured once** — preserves the first-detection conditions for
  diagnosis; re-confirmations must not overwrite the original evidence.
- **Heal on sustained clean run, MIL latched until then** — mirrors OBD MIL-off after N
  clean warm-up cycles; safety indicators should not flicker on intermittent recovery.
