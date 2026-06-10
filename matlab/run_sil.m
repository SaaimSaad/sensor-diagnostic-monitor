function run_sil()
% run_sil.m  —  Software-in-the-loop equivalence for DiagMonitor.
% Original work, MIT licence.
%
% Generates code, runs the tc_confirm and tc_heal stimuli in SIL mode, and
% asserts MIL/SIL output equivalence (state, dtc, mil identical).
%
% Requires: Embedded Coder + a supported C compiler (run `mex -setup`).
% Usage:  diag_params; build_model; run_sil

    mdl = 'diag_monitor';
    if ~exist([mdl '.slx'], 'file'); build_model(); end

    scenarios = {'tc_confirm', 'tc_heal'};
    for i = 1:numel(scenarios)
        name   = scenarios{i};
        milOut = simulateMode(mdl, name, 'normal');
        silOut = simulateMode(mdl, name, 'sil');

        ds = max(abs(double(milOut.state) - double(silOut.state)));
        dd = max(abs(double(milOut.dtc)   - double(silOut.dtc)));
        dm = max(abs(double(milOut.mil)   - double(silOut.mil)));
        ok = (ds == 0) && (dd == 0) && (dm == 0);
        tag = '[PASS]'; if ~ok; tag = '[FAIL]'; end
        fprintf('%s  %-12s  d_state=%d d_dtc=%d d_mil=%d\n', tag, name, ds, dd, dm);
        assert(ok, 'run_sil: MIL/SIL mismatch on %s', name);
    end
    fprintf('run_sil: MIL/SIL equivalence verified.\n');
end

function out = simulateMode(mdl, scenarioName, mode) %#ok<INUSD>
    sub = [mdl '/DiagMonitor'];
    set_param(sub, 'SimulationMode', mode);   % 'normal' or 'sil'
    in  = Simulink.SimulationInput(mdl);
    in  = in.setModelParameter('StopTime', '6');
    so  = sim(in);
    set_param(sub, 'SimulationMode', 'normal');
    out.state = reshapeLog(so, 'state');
    out.dtc   = reshapeLog(so, 'dtc');
    out.mil   = reshapeLog(so, 'mil');
end

function v = reshapeLog(so, name)
    try; v = so.(name); if isa(v,'timeseries'); v = v.Data; end
    catch; v = so.yout.get(name).Values.Data; end
end
