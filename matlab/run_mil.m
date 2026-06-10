function results = run_mil()
% run_mil.m  —  Model-in-the-loop verification of diag_monitor.
% Original work, MIT licence.
%
% Runs the test cases from docs/test-plan.md, evaluates the requirement
% thresholds, plots the key signals, and prints a pass/fail summary that
% traces each test case to its requirement(s).
%
% Usage:  diag_params; build_model; run_mil

    mdl = 'diag_monitor';
    if ~exist([mdl '.slx'], 'file'); build_model(); end
    D = evalin('base', 'D');

    cases = {
        'tc_range'     , @scn_range
        'tc_rate'      , @scn_rate
        'tc_corr'      , @scn_corr
        'tc_confirm'   , @scn_confirm
        'tc_glitch'    , @scn_glitch
        'tc_heal'      , @scn_heal
        'tc_enable'    , @scn_enable
        'tc_range_out' , @scn_range_out
    };

    results = struct('name', {}, 'req', {}, 'pass', {}, 'detail', {});
    figure('Name', 'Sensor Diagnostic Monitor — MIL', 'Color', 'w');

    for i = 1:size(cases, 1)
        name = cases{i, 1};
        scn  = cases{i, 2}(D);
        out  = simulateScenario(mdl, scn, D);
        [pass, req, detail] = evaluate(name, out, D);
        results(end+1) = struct('name', name, 'req', req, 'pass', pass, 'detail', detail); %#ok<AGROW>
        subplot(size(cases,1), 1, i); plotCase(name, out);
    end

    printSummary(results);
end

% =======================================================================
function out = simulateScenario(mdl, scn, D)
    in = Simulink.SimulationInput(mdl);
    in = in.setExternalInput(scn.signals);
    in = in.setModelParameter('StopTime', num2str(scn.tEnd));
    so = sim(in);
    out.t        = so.tout;
    out.state    = getLog(so, 'state');
    out.dtc      = getLog(so, 'dtc');
    out.mil      = getLog(so, 'mil');
    out.ff_valid = getLog(so, 'ff_valid');
end

function v = getLog(so, name)
    try
        v = so.(name); if isa(v, 'timeseries'); v = v.Data; end
    catch
        v = so.yout.get(name).Values.Data;
    end
end

% =======================================================================
function [pass, req, detail] = evaluate(name, out, D)
    confirmed = any(out.state == D.STATE.CONFIRMED);
    milOn     = any(out.mil > 0.5);
    switch name
        case 'tc_range'
            pass = confirmed && any(bitand(uint8(out.dtc), D.BIT.RANGE) > 0);
            req  = 'REQ-DIAG-001';
            detail = 'electrical OOR confirmed; range DTC bit set';
        case 'tc_rate'
            pass = confirmed && any(bitand(uint8(out.dtc), D.BIT.RATE) > 0);
            req  = 'REQ-DIAG-002';
            detail = 'implausible-step (rate) DTC bit set';
        case 'tc_confirm'
            idx  = find(out.state == D.STATE.CONFIRMED, 1, 'first');
            ms   = isempty(idx) * NaN + ~isempty(idx) * (out.t(idx) - 1.0) * 1000;
            pass = confirmed && milOn && any(out.ff_valid > 0.5);
            req  = 'REQ-DIAG-004/005/006/007';
            detail = sprintf('confirmed @ ~%.0f ms after onset; freeze-frame valid', ms);
        case 'tc_glitch'
            pass = ~confirmed && ~milOn;
            req  = 'REQ-DIAG-004';
            detail = sprintf('single-sample glitch did not confirm (mil never on)');
        case 'tc_corr'
            pass = confirmed && any(bitand(uint8(out.dtc), D.BIT.CORR) > 0);
            req  = 'REQ-DIAG-003';
            detail = 'correlation DTC bit set';
        case 'tc_heal'
            healedBack = out.state(end) == D.STATE.NO_FAULT && out.mil(end) < 0.5;
            pass = confirmed && healedBack;
            req  = 'REQ-DIAG-008';
            detail = sprintf('healed to NO_FAULT; MIL cleared');
        case 'tc_enable'
            pass = ~confirmed && ~milOn;
            req  = 'REQ-DIAG-009';
            detail = 'cold engine: no confirmation';
        case 'tc_range_out'
            % REQ-DIAG-010: outputs stay within declared ranges over a mixed run.
            pass = all(out.state >= 0 & out.state <= 3) && ...
                   all(out.mil == 0 | out.mil == 1) && ...
                   all(out.dtc >= 0 & out.dtc <= 255);
            req  = 'REQ-DIAG-010';
            detail = 'state∈[0,3] · mil∈{0,1} · dtc∈[0,255]';
        otherwise
            pass = false; req = '?'; detail = 'unknown case';
    end
    inRange = all(out.state >= 0 & out.state <= 3) && all(out.dtc >= 0 & out.dtc <= 255);
    pass    = pass && inRange;
    detail  = [detail sprintf(' | range_ok=%d', inRange)];
end

% =======================================================================
% ---- Scenario builders -------------------------------------------------
function scn = scn_confirm(D)
    scn.tEnd = 3;
    bad = @(t) (t >= 1.0);          % electrical OOR from t=1s
    scn.signals = sigBus(D, scn.tEnd, @(t) v1(D, 40) + bad(t)*4.5, @(t) v2(D, 40), 2500, 55, 90);
end
function scn = scn_glitch(D)
    scn.tEnd = 2;
    spike = @(t) (abs(t - 1.0) < D.Ts/2);
    scn.signals = sigBus(D, scn.tEnd, @(t) v1(D, 40) + spike(t)*4.5, @(t) v2(D, 40), 2000, 40, 90);
end
function scn = scn_corr(D)
    scn.tEnd = 3;
    drift = @(t) (t >= 1.0) * 30;   % 30% mismatch
    scn.signals = sigBus(D, scn.tEnd, @(t) v1(D, 40), @(t) v2(D, 40 - drift(t)), 2000, 40, 90);
end
function scn = scn_heal(D)
    scn.tEnd = 6;
    bad = @(t) (t >= 0.5 & t < 1.5);
    scn.signals = sigBus(D, scn.tEnd, @(t) v1(D, 40) + bad(t)*4.5, @(t) v2(D, 40), 2000, 40, 90);
end
function scn = scn_enable(D)
    scn.tEnd = 2;
    scn.signals = sigBus(D, scn.tEnd, @(t) v1(D, 40) + 4.5, @(t) v2(D, 40), 600, 5, 40); % cold
end
function scn = scn_range(D)
    scn.tEnd = 3;
    bad = @(t) (t >= 1.0);                            % sustained electrical OOR-high on v1
    scn.signals = sigBus(D, scn.tEnd, @(t) v1(D, 40) + bad(t)*4.5, @(t) v2(D, 40), 2000, 40, 90);
end
function scn = scn_rate(D)
    scn.tEnd = 3;
    on  = @(t) (t >= 1.0);
    alt = @(t) (mod(round(t/D.Ts), 2) == 1);         % toggles every sample once active
    pct = @(t) 40 + on(t)*alt(t)*40;                 % 40% <-> 80% step (1.6 V > dv_max) each sample
    % both channels follow the same %, so they stay correlated -> only the rate test trips
    scn.signals = sigBus(D, scn.tEnd, @(t) v1(D, pct(t)), @(t) v2(D, pct(t)), 2000, 40, 90);
end
function scn = scn_range_out(D)
    scn.tEnd = 6;                                     % mixed run: clean -> fault -> heal
    bad = @(t) (t >= 0.5 & t < 1.5);
    scn.signals = sigBus(D, scn.tEnd, @(t) v1(D, 40) + bad(t)*4.5, @(t) v2(D, 40), 2000, 40, 90);
end

function val = v1(D, pct); val = D.v1_lo + pct/100*(D.v1_hi - D.v1_lo); end
function val = v2(D, pct); val = D.v2_lo + pct/100*(D.v2_hi - D.v2_lo); end

function bus = sigBus(D, tEnd, fv1, fv2, rpm, load, ect)
    t = (0:D.Ts:tEnd)';
    bus = Simulink.SimulationData.Dataset;
    bus = bus.addElement(asTs(t, fv1,  'v1'));
    bus = bus.addElement(asTs(t, fv2,  'v2'));
    bus = bus.addElement(asTs(t, rpm,  'rpm'));
    bus = bus.addElement(asTs(t, load, 'load'));
    bus = bus.addElement(asTs(t, ect,  'ect'));
end

function ts = asTs(t, v, name)
    if isa(v, 'function_handle'); data = arrayfun(v, t); else; data = v + 0*t; end
    ts = timeseries(data, t, 'Name', name);
end

% =======================================================================
function plotCase(name, out)
    yyaxis left;  stairs(out.t, double(out.state), 'LineWidth', 1.1); ylabel('state'); ylim([-0.5 3.5]);
    yyaxis right; stairs(out.t, double(out.mil),   'LineWidth', 0.9); ylabel('MIL');   ylim([-0.2 1.2]);
    title(name, 'Interpreter', 'none'); grid on;
end

function printSummary(results)
    fprintf('\n=== Diagnostic-monitor MIL summary ===\n');
    npass = 0;
    for i = 1:numel(results)
        r = results(i); tag = '[PASS]'; if ~r.pass; tag = '[FAIL]'; end
        npass = npass + r.pass;
        fprintf('%s  %-12s %-26s  %s\n', tag, r.name, r.req, r.detail);
    end
    fprintf('--------------------------------------\n%d/%d test cases passed.\n\n', npass, numel(results));
    assert(npass == numel(results), 'run_mil: one or more requirement checks FAILED.');
end
