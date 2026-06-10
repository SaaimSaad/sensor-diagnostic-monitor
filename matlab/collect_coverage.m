function collect_coverage()
% collect_coverage.m  —  Structural coverage for diag_monitor.
% Original work, MIT licence.
%
% Records decision / condition / MCDC coverage over the full MIL test suite
% and exports an HTML report to ../assets/coverage/. Fails the run if any
% metric is below the target in docs/test-plan.md.
%
% Requires: Simulink Coverage.
% Usage:  diag_params; build_model; collect_coverage

    mdl = 'diag_monitor';
    if ~exist([mdl '.slx'], 'file'); build_model(); end

    target = 100;   % percent, for decision / condition / MCDC

    set_param(mdl, 'CovEnable',                'on');
    set_param(mdl, 'CovMetricStructuralLevel', 'MCDC');
    set_param(mdl, 'RecordCoverage',           'on');
    set_param(mdl, 'CovScope',                 'Subsystem');
    set_param(mdl, 'CovPath',                  '/DiagMonitor');

    scenarios = {'tc_range','tc_rate','tc_corr','tc_confirm','tc_glitch','tc_heal','tc_enable','tc_range_out'};
    cumCov = [];
    for i = 1:numel(scenarios)
        in    = Simulink.SimulationInput(mdl);
        in    = in.setModelParameter('StopTime', '6');
        in    = in.setModelParameter('CovEnable', 'on');
        cdata = cvsim(in); %#ok<NASGU>
        cumCov = appendCoverage(cumCov, cdata);
    end

    outDir = fullfile('..', 'assets', 'coverage');
    if ~exist(outDir, 'dir'); mkdir(outDir); end
    cvhtml(fullfile(outDir, 'index.html'), cumCov);

    d  = decisioninfo(cumCov, [mdl '/DiagMonitor']);
    c  = conditioninfo(cumCov, [mdl '/DiagMonitor']);
    m  = mcdcinfo(cumCov, [mdl '/DiagMonitor']);
    pd = 100 * d(1) / max(d(2), 1);
    pc = 100 * c(1) / max(c(2), 1);
    pm = 100 * m(1) / max(m(2), 1);

    fprintf('\n=== Coverage (DiagMonitor) ===\n');
    fprintf('Decision : %.1f%%\nCondition: %.1f%%\nMCDC     : %.1f%%\n', pd, pc, pm);
    fprintf('Report   : %s\n\n', fullfile(outDir, 'index.html'));

    assert(all([pd pc pm] >= target - 1e-9), ...
           'collect_coverage: coverage below %d%% target — add test cases.', target);
end

function acc = appendCoverage(acc, c)
    if isempty(acc); acc = c; else; acc = acc + c; end
end
