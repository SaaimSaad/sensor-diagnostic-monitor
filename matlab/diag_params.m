% diag_params.m  —  Single source of parameters for the sensor diagnostic monitor.
% Original work, MIT licence. Generic OBD-style rationality + confirmation monitor;
% no proprietary content.
%
% Run this first; it populates struct `D` in the base workspace. The Simulink
% model, the test scripts, and the browser simulation all share these values.

D = struct();

% ---- Timing -------------------------------------------------------------
D.Ts        = 0.01;     % monitor sample time [s]  (100 Hz)

% ---- Sensor scaling (redundant pair APP1 / APP2) ------------------------
% APP1 (primary)   : 0.5 .. 4.5 V over 0 .. 100 %
% APP2 (redundant) : 0.25 .. 2.25 V over 0 .. 100 % (half-scale)
D.v1_lo     = 0.5;      % APP1 volts at 0 %
D.v1_hi     = 4.5;      % APP1 volts at 100 %
D.v2_lo     = 0.25;     % APP2 volts at 0 %
D.v2_hi     = 2.25;     % APP2 volts at 100 %

% ---- Rationality test thresholds ----------------------------------------
D.v_oor_lo  = 0.20;     % electrical out-of-range low  [V]  (short to gnd / open)
D.v_oor_hi  = 4.80;     % electrical out-of-range high [V]  (short to batt)
D.dv_max    = 1.50;     % max plausible step per sample [V] (rate / spike)
D.corr_tol  = 10.0;     % max allowed |pct1 - pct2| mismatch [%] (correlation)

% ---- Confirmation / healing ---------------------------------------------
D.confirm_cnt = 20;     % sustained failing samples to CONFIRM (= 200 ms)
D.heal_cnt    = 300;    % consecutive clean samples to heal (~3 warm-up cycles)

% ---- Enable conditions --------------------------------------------------
D.warm_min  = 60.0;     % coolant temp above which diagnostics run [degC]

% ---- DTC bit positions (range / rate / correlation) ---------------------
D.BIT.RANGE = uint8(1); % bit0
D.BIT.RATE  = uint8(2); % bit1
D.BIT.CORR  = uint8(4); % bit2

% ---- State enum (kept in sync with Stateflow / generated code) ----------
D.STATE.NO_FAULT  = uint8(0);
D.STATE.PENDING   = uint8(1);
D.STATE.CONFIRMED = uint8(2);
D.STATE.HEALING   = uint8(3);

assignin('base', 'D', D);
fprintf('diag_params: loaded %d parameters (Ts = %g s).\n', numel(fieldnames(D)), D.Ts);
