function build_model()
% build_model.m  —  Construct the sensor diagnostic monitor AS CODE.
% Original work, MIT licence. Generic OBD-style rationality + confirmation monitor.
%
% Creates diag_monitor.slx containing:
%   - DiagMonitor : atomic subsystem = Rationality (MATLAB Function) +
%                   Confirmation supervisor (Stateflow). This is the
%                   code-generated unit. The supervisor latches the DTC,
%                   captures a one-shot freeze-frame at confirmation, drives
%                   the MIL, and heals after a sustained clean run.
%   - a unit delay on v1 to provide the previous sample for the rate test.
%
% Prerequisite: run `diag_params` first so struct D exists in the base workspace.
%
% Defining the model in code (rather than hand-drawing a .slx) keeps the
% design reviewable and diffable in version control.
%
% NOTE: authored for a clean personal MATLAB (Home / trial / Online) with
% Simulink + Stateflow; validate there. Do not build on a client install.

    mdl = 'diag_monitor';
    if ~evalin('base', 'exist(''D'',''var'')')
        error('build_model:noParams', 'Run `diag_params` first to load struct D.');
    end

    close_system(mdl, 0); %#ok<*NASGU>
    if exist([mdl '.slx'], 'file'); delete([mdl '.slx']); end
    new_system(mdl);
    open_system(mdl);

    set_param(mdl, 'SolverType', 'Fixed-step', ...
                   'Solver',     'FixedStepDiscrete', ...
                   'FixedStep',  'D.Ts', ...
                   'StopTime',   '6');

    addInports(mdl);
    addMonitor(mdl);          % atomic subsystem: Rationality + Supervisor
    addScopesAndLogging(mdl);
    wireModel(mdl);

    Simulink.BlockDiagram.arrangeSystem(mdl);
    save_system(mdl);
    fprintf('build_model: created %s.slx\n', mdl);
end

% =======================================================================
function addInports(mdl)
    names = {'v1','v2','rpm','load','ect'};
    for i = 1:numel(names)
        add_block('simulink/Sources/In1', [mdl '/' names{i}], 'Position', pos(40, 40 + (i-1)*54));
    end
end

% =======================================================================
function addMonitor(mdl)
    sub = [mdl '/DiagMonitor'];
    add_block('built-in/Subsystem', sub, 'Position', pos(280, 60));
    set_param(sub, 'TreatAsAtomicUnit', 'on');   % atomic -> code-gen unit

    % Rationality (MATLAB Function): tests + shared debounced counter, and it
    % forwards pct1/pct2 + the thresholds so the chart needs no parameters.
    add_block('simulink/User-Defined Functions/MATLAB Function', ...
              [sub '/Rationality'], 'Position', pos(220, 60));
    setFcn(mdl, 'DiagMonitor/Rationality', rationalityCode());

    % Confirmation supervisor (Stateflow chart) placed INSIDE the subsystem
    add_block('sflib/Chart', [sub '/Supervisor'], 'Position', pos(460, 60));
    buildSupervisorChart(sub);

    % previous-sample delay for the rate test (provides v1_prev)
    add_block('simulink/Discrete/Unit Delay', [sub '/v1_z'], ...
              'Position', pos(120, 220), 'SampleTime', 'D.Ts');

    addSubsysPorts(sub);
    wireMonitor(sub);
end

% =======================================================================
function buildSupervisorChart(sub)
% Build the NO_FAULT/PENDING/CONFIRMED/HEALING confirmation machine with DTC
% latching, one-shot freeze-frame capture, MIL, and healing.
    rt    = sfroot;
    chart = rt.find('-isa', 'Stateflow.Chart', '-and', 'Path', [sub '/Supervisor']);
    chart.ChartUpdate = 'DISCRETE';
    chart.SampleTime  = 'D.Ts';

    % ---- Chart data (ports appear in creation order) -------------------
    % Inputs: from Rationality + the operating point (for the freeze-frame).
    inNames = {'failCnt','any_bad','enable','testbits','confirm_cnt','heal_cnt', ...
               'rpm','load','ect','v1','pct1','pct2'};
    inTypes = {'double','boolean','boolean','uint8','double','double', ...
               'double','double','double','double','double','double'};
    for i = 1:numel(inNames); addData(chart, inNames{i}, 'Input', inTypes{i}); end
    % Outputs: match the SWC / subsystem interface.
    outNames = {'state','dtc','mil','ff_valid'};
    outTypes = {'uint8','uint8','boolean','boolean'};
    for i = 1:numel(outNames); addData(chart, outNames{i}, 'Output', outTypes{i}); end
    % Locals: heal counter + freeze-frame store (captured once at confirmation).
    locNames = {'healCnt','ff_rpm','ff_load','ff_ect','ff_v1','ff_pct1','ff_pct2'};
    for i = 1:numel(locNames); addData(chart, locNames{i}, 'Local', 'double'); end

    % ---- States --------------------------------------------------------
    names = {'NO_FAULT','PENDING','CONFIRMED','HEALING'};
    S = struct();
    for i = 1:numel(names)
        st = Stateflow.State(chart);
        st.Name     = names{i};
        st.Position  = [60, 60 + (i-1)*120, 200, 80];
        S.(names{i}) = st;
    end
    % NO_FAULT also archives/clears the DTC + freeze-frame on heal (REQ-DIAG-008).
    S.NO_FAULT.LabelString  = sprintf(['NO_FAULT\n' ...
        'en: state = uint8(0); mil = false;\n' ...
        'dtc = uint8(0); ff_valid = false; healCnt = 0;']);
    S.PENDING.LabelString   = sprintf(['PENDING\n' ...
        'en: state = uint8(1); mil = false;']);
    % CONFIRMED captures the freeze-frame exactly once (REQ-DIAG-006), keeps the
    % MIL on (REQ-DIAG-007), and accumulates multi-test DTC bits while active.
    S.CONFIRMED.LabelString = sprintf(['CONFIRMED\n' ...
        'en: state = uint8(2); mil = true;\n' ...
        'if ~ff_valid\n' ...
        '  dtc = testbits;\n' ...
        '  ff_rpm = rpm; ff_load = load; ff_ect = ect;\n' ...
        '  ff_v1 = v1; ff_pct1 = pct1; ff_pct2 = pct2;\n' ...
        '  ff_valid = true;\n' ...
        'end\n' ...
        'du: dtc = bitor(dtc, testbits);']);
    % HEALING counts consecutive clean samples; MIL stays on until it clears.
    S.HEALING.LabelString   = sprintf(['HEALING\n' ...
        'en: state = uint8(3); mil = true; healCnt = 0;\n' ...
        'du: healCnt = healCnt + 1;']);

    % Default transition into NO_FAULT
    dt = Stateflow.Transition(chart);
    dt.Destination = S.NO_FAULT;

    addTrans(chart, S.NO_FAULT,  S.PENDING,   'failCnt > 0');
    addTrans(chart, S.PENDING,   S.CONFIRMED, 'failCnt >= confirm_cnt');   % debounced confirm (REQ-DIAG-004)
    addTrans(chart, S.PENDING,   S.NO_FAULT,  'failCnt == 0');
    addTrans(chart, S.CONFIRMED, S.HEALING,   'enable && ~any_bad');
    addTrans(chart, S.HEALING,   S.CONFIRMED, 'any_bad');                  % re-fail re-confirms (REQ-DIAG-008)
    addTrans(chart, S.HEALING,   S.NO_FAULT,  'healCnt >= heal_cnt');      % archive + clear (REQ-DIAG-008)
end

function d = addData(chart, name, scope, dtype)
    d = Stateflow.Data(chart);
    d.Name     = name;
    d.Scope    = scope;        % 'Input' | 'Output' | 'Local'
    d.DataType = dtype;        % e.g. 'uint8', 'boolean', 'double'
end

function addTrans(chart, src, dst, cond)
    t = Stateflow.Transition(chart);
    t.Source      = src;
    t.Destination = dst;
    t.LabelString = ['[' cond ']'];
end

% =======================================================================
function addScopesAndLogging(mdl)
    add_block('simulink/Sinks/Out1', [mdl '/state'],    'Position', pos(900, 60));
    add_block('simulink/Sinks/Out1', [mdl '/dtc'],      'Position', pos(900, 114));
    add_block('simulink/Sinks/Out1', [mdl '/mil'],      'Position', pos(900, 168));
    add_block('simulink/Sinks/Out1', [mdl '/ff_valid'], 'Position', pos(900, 222));
end

% =======================================================================
function addSubsysPorts(sub)
    inports = {'v1','v2','rpm','load','ect'};
    for i = 1:numel(inports)
        add_block('simulink/Sources/In1', [sub '/' inports{i}], ...
                  'Position', pos(40, 40 + (i-1)*54));
    end
    outports = {'state','dtc','mil','ff_valid'};
    for i = 1:numel(outports)
        add_block('simulink/Sinks/Out1', [sub '/' outports{i}], ...
                  'Position', pos(740, 40 + (i-1)*54));
    end
end

% =======================================================================
function wireMonitor(sub)
% Internal wiring of the DiagMonitor subsystem. Chart ports follow the data
% creation order in buildSupervisorChart (inputs 1..12, outputs 1..4).
    R = 'Rationality';   % MATLAB Function: in (v1,v2,v1_prev,ect)
                         %                  out (failCnt,any_bad,enable,testbits,confirm_cnt,heal_cnt,pct1,pct2)
    C = 'Supervisor';    % Stateflow chart

    % operating-point inports -> Rationality / delay / chart
    autoConnect(sub, 'v1/1',   [R '/1']);     % v1   -> Rationality.v1
    autoConnect(sub, 'v1/1',   'v1_z/1');     % v1   -> unit delay
    autoConnect(sub, 'v1/1',   [C '/10']);    % v1   -> chart.v1
    autoConnect(sub, 'v2/1',   [R '/2']);     % v2   -> Rationality.v2
    autoConnect(sub, 'v1_z/1', [R '/3']);     % v1_prev -> Rationality.v1_prev
    autoConnect(sub, 'ect/1',  [R '/4']);     % ect  -> Rationality.ect
    autoConnect(sub, 'ect/1',  [C '/9']);     % ect  -> chart.ect
    autoConnect(sub, 'rpm/1',  [C '/7']);     % rpm  -> chart.rpm
    autoConnect(sub, 'load/1', [C '/8']);     % load -> chart.load

    % Rationality outputs -> chart inputs (1:1 by port order)
    autoConnect(sub, [R '/1'], [C '/1']);     % failCnt
    autoConnect(sub, [R '/2'], [C '/2']);     % any_bad
    autoConnect(sub, [R '/3'], [C '/3']);     % enable
    autoConnect(sub, [R '/4'], [C '/4']);     % testbits
    autoConnect(sub, [R '/5'], [C '/5']);     % confirm_cnt
    autoConnect(sub, [R '/6'], [C '/6']);     % heal_cnt
    autoConnect(sub, [R '/7'], [C '/11']);    % pct1
    autoConnect(sub, [R '/8'], [C '/12']);    % pct2

    % chart outputs -> subsystem outports
    autoConnect(sub, [C '/1'], 'state/1');
    autoConnect(sub, [C '/2'], 'dtc/1');
    autoConnect(sub, [C '/3'], 'mil/1');
    autoConnect(sub, [C '/4'], 'ff_valid/1');
end

% =======================================================================
function wireModel(mdl)
    autoConnect(mdl, 'v1/1',   'DiagMonitor/1');
    autoConnect(mdl, 'v2/1',   'DiagMonitor/2');
    autoConnect(mdl, 'rpm/1',  'DiagMonitor/3');
    autoConnect(mdl, 'load/1', 'DiagMonitor/4');
    autoConnect(mdl, 'ect/1',  'DiagMonitor/5');

    autoConnect(mdl, 'DiagMonitor/1', 'state/1');
    autoConnect(mdl, 'DiagMonitor/2', 'dtc/1');
    autoConnect(mdl, 'DiagMonitor/3', 'mil/1');
    autoConnect(mdl, 'DiagMonitor/4', 'ff_valid/1');
end

function autoConnect(sys, src, dst)
    try
        add_line(sys, src, dst, 'autorouting', 'smart');
    catch ME
        warning('build_model:wire', 'Could not connect %s -> %s (%s).', src, dst, ME.message);
    end
end

% =======================================================================
function setFcn(mdl, blockRelPath, code)
    S  = sfroot;
    fn = S.find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/' blockRelPath]);
    fn.Script = code;
end

function p = pos(x, y)
    p = [x, y, x + 110, y + 40];
end

% =======================================================================
% ---- Embedded MATLAB: Rationality (the deployed tests + debounce) ------
function c = rationalityCode()
c = [ ...
"function [failCnt, any_bad, enable, testbits, confirm_cnt, heal_cnt, pct1, pct2] = Rationality(v1, v2, v1_prev, ect)" newline ...
"%#codegen" newline ...
"%  Range + rate + correlation rationality tests with a shared debounced" newline ...
"%  fail counter. Counter is frozen unless enable conditions are met. Also" newline ...
"%  forwards the confirm/heal thresholds and the normalised percentages so" newline ...
"%  the supervisor can latch the DTC and capture the freeze-frame." newline ...
"D = diag_const();" newline ...
"persistent fc; if isempty(fc); fc = 0; end" newline ...
"" newline ...
"pct1 = (v1 - D.v1_lo) / (D.v1_hi - D.v1_lo) * 100;" newline ...
"pct2 = (v2 - D.v2_lo) / (D.v2_hi - D.v2_lo) * 100;" newline ...
"" newline ...
"range_bad = (v1 < D.v_oor_lo) || (v1 > D.v_oor_hi);" newline ...
"rate_bad  = abs(v1 - v1_prev) > D.dv_max;" newline ...
"corr_bad  = abs(pct1 - pct2) > D.corr_tol;" newline ...
"any_bad   = range_bad || rate_bad || corr_bad;" newline ...
"testbits  = uint8(range_bad) + uint8(2)*uint8(rate_bad) + uint8(4)*uint8(corr_bad);" newline ...
"" newline ...
"enable = ect >= D.warm_min;" newline ...
"if enable" newline ...
"    if any_bad; fc = min(fc + 1, D.confirm_cnt); else; fc = max(fc - 1, 0); end" newline ...
"end" newline ...
"failCnt     = fc;" newline ...
"confirm_cnt = D.confirm_cnt;" newline ...
"heal_cnt    = D.heal_cnt;" newline ...
"end" ];
end
