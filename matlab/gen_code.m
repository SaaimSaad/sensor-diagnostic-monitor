function gen_code()
% gen_code.m  —  Generate MISRA-style C for the DiagMonitor subsystem.
% Original work, MIT licence.
%
% Configures Embedded Coder for production C and builds code for the atomic
% subsystem diag_monitor/DiagMonitor. Output lands in ../generated/.
%
% Requires: Simulink, Embedded Coder (and a supported C compiler for SIL).
% Usage:  diag_params; build_model; gen_code

    mdl = 'diag_monitor';
    sub = [mdl '/DiagMonitor'];
    if ~exist([mdl '.slx'], 'file'); build_model(); end
    load_system(mdl);

    outDir = fullfile('..', 'generated');
    if ~exist(outDir, 'dir'); mkdir(outDir); end

    % ---- System target: embedded real-time (ert.tlc) -------------------
    set_param(mdl, 'SystemTargetFile', 'ert.tlc');
    set_param(mdl, 'TargetLang',       'C');
    set_param(mdl, 'GenCodeOnly',      'on');
    set_param(mdl, 'CodeInterfacePackaging', 'Reusable function');

    % ---- Production-quality / MISRA-aligned settings -------------------
    set_param(mdl, 'MatFileLogging',        'off');
    set_param(mdl, 'SupportNonFinite',      'off');
    set_param(mdl, 'SupportContinuousTime', 'off');
    set_param(mdl, 'GenerateComments',      'on');
    set_param(mdl, 'RequirementsInCode',    'on');
    set_param(mdl, 'GenerateReport',        'on');
    set_param(mdl, 'CodeStyleApplied',      'on');

    try
        set_param(mdl, 'PackageGeneratedCodeAndArtifacts', 'on');
        cs = getActiveConfigSet(mdl);
        attachComponent(cs, 'Code Generation Advisor'); %#ok<NASGU>
    catch
        warning('gen_code:advisor', 'MISRA objective not applied automatically; set it via Code Generation Advisor.');
    end

    fprintf('gen_code: generating C for %s ...\n', sub);
    rtwbuild(sub);

    src = dir(fullfile(pwd, 'DiagMonitor_ert_rtw', '*.c'));
    for k = 1:numel(src)
        copyfile(fullfile(src(k).folder, src(k).name), outDir);
    end
    fprintf('gen_code: C source copied to %s\n', outDir);
end
