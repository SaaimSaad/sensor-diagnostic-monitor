function tests = test_diag_monitor()
% test_diag_monitor.m  —  Requirement-linked tests (MATLAB unit test).
% Original work, MIT licence.
%
% Pure-MATLAB reference checks of the monitor logic, independent of Simulink,
% so the diagnostic algorithm can be verified quickly and traced to
% requirements. Mirrors verify_diag_logic.js.
%
% Usage:  cd matlab; results = runtests('test/test_diag_monitor.m')

    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(here, '..'));           % for diag_const
    tc.TestData.D = diag_const();
end

% --- REQ-DIAG-001/002/003 : each rationality test fires -----------------
function test_tests_fire_REQ001_002_003(tc)
    D = tc.TestData.D;
    verifyTrue(tc, rangeBad(D, 4.90),               'REQ-DIAG-001 OOR-high');
    verifyTrue(tc, rangeBad(D, 0.10),               'REQ-DIAG-001 OOR-low');
    verifyTrue(tc, abs(2.0) > D.dv_max,             'REQ-DIAG-002 rate');
    verifyTrue(tc, corrBad(D, v1(D,40), v2(D,70)),  'REQ-DIAG-003 correlation');
    verifyFalse(tc, corrBad(D, v1(D,40), v2(D,42)), 'small mismatch must not trip');
end

% --- REQ-DIAG-004 : confirmation requires sustained failures ------------
function test_confirm_debounce_REQ004(tc)
    D = tc.TestData.D;
    st = run_seq(D, repmat(4.90, 1, D.confirm_cnt), v2(D,40), 90);
    verifyEqual(tc, double(st.state), 2, 'REQ-DIAG-004 confirms after threshold');
    verifyEqual(tc, st.mil, 1, 'REQ-DIAG-007 MIL on when confirmed');
end

% --- REQ-DIAG-004 : single-sample glitch must not confirm ---------------
function test_no_false_trip_REQ004(tc)
    D = tc.TestData.D;
    v = [v1(D,40), 4.90, repmat(v1(D,40), 1, 50)];   % one bad sample, then clean
    st = run_seq(D, v, v2(D,40), 90);
    verifyEqual(tc, double(st.state), 0, 'no confirmation on a glitch');
    verifyEqual(tc, st.milEver, 0, 'MIL never lit on a glitch');
end

% --- REQ-DIAG-005 : an unconfirmed detected fault reports PENDING --------
function test_pending_REQ005(tc)
    D = tc.TestData.D;
    st = run_seq(D, [v1(D,40), 4.90], v2(D,40), 90);   % one clean, then one bad sample
    verifyEqual(tc, double(st.state), 1, 'REQ-DIAG-005 PENDING on first detected fault');
    verifyEqual(tc, st.mil, 0, 'MIL off while only PENDING');
end

% --- REQ-DIAG-008 : heal after a sustained clean run --------------------
function test_heal_REQ008(tc)
    D = tc.TestData.D;
    v = [repmat(4.90, 1, D.confirm_cnt), repmat(v1(D,40), 1, D.heal_cnt + 5)]; % confirm, then clean
    st = run_seq(D, v, v2(D,40), 90);
    verifyEqual(tc, double(st.state), 0, 'REQ-DIAG-008 healed back to NO_FAULT');
    verifyEqual(tc, st.mil, 0, 'MIL cleared after heal');
    verifyEqual(tc, double(st.dtc), 0, 'DTC cleared after heal');
end

% --- REQ-DIAG-009 : disabled when cold ----------------------------------
function test_enable_gate_REQ009(tc)
    D = tc.TestData.D;
    st = run_seq(D, repmat(4.90, 1, 100), v2(D,40), 40);   % ect = 40 < warm_min
    verifyEqual(tc, double(st.state), 0, 'REQ-DIAG-009 no confirm when cold');
    verifyEqual(tc, st.failCnt, 0, 'fail counter frozen when disabled');
end

% =======================================================================
% Reference implementation (mirrors the Rationality block + supervisor).
function st = run_seq(D, v1seq, v2val, ect)
    st.state = 0; st.failCnt = 0; st.healCnt = 0; st.dtc = 0; st.mil = 0;
    st.milEver = 0; v1_prev = v1seq(1);
    for k = 1:numel(v1seq)
        vv = v1seq(k);
        rb = rangeBad(D, vv);
        ra = abs(vv - v1_prev) > D.dv_max;
        co = corrBad(D, vv, v2val);
        anyBad = rb || ra || co;
        bits = uint8(rb) + uint8(2)*uint8(ra) + uint8(4)*uint8(co);
        enable = ect >= D.warm_min;
        if enable
            if anyBad; st.failCnt = min(st.failCnt + 1, D.confirm_cnt);
            else;      st.failCnt = max(st.failCnt - 1, 0); end
        end
        switch st.state
            case 0; if st.failCnt > 0; st.state = 1; end
            case 1
                if st.failCnt >= D.confirm_cnt; st.state = 2; st.dtc = bits;
                elseif st.failCnt == 0; st.state = 0; end
            case 2; if enable && ~anyBad; st.state = 3; st.healCnt = 0; end
            case 3
                if anyBad; st.state = 2; st.healCnt = 0;
                else; st.healCnt = st.healCnt + 1;
                    if st.healCnt >= D.heal_cnt; st.state = 0; st.dtc = 0; st.failCnt = 0; end
                end
        end
        st.mil = (st.state == 2 || st.state == 3);
        st.milEver = st.milEver || st.mil;
        v1_prev = vv;
    end
end

function b = rangeBad(D, v); b = (v < D.v_oor_lo) || (v > D.v_oor_hi); end
function b = corrBad(D, va, vb)
    p1 = (va - D.v1_lo)/(D.v1_hi - D.v1_lo)*100;
    p2 = (vb - D.v2_lo)/(D.v2_hi - D.v2_lo)*100;
    b  = abs(p1 - p2) > D.corr_tol;
end
function val = v1(D, pct); val = D.v1_lo + pct/100*(D.v1_hi - D.v1_lo); end
function val = v2(D, pct); val = D.v2_lo + pct/100*(D.v2_hi - D.v2_lo); end
