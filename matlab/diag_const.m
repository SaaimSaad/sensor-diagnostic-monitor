function D = diag_const()
%#codegen
% diag_const.m  —  Compile-time constants for the deployed diagnostic monitor.
% Mirrors the tunable values in diag_params.m, but as a code-generation-friendly
% constant function (no base-workspace dependency). Keep the two in sync.
% Original work, MIT licence.

    D.Ts        = 0.01;

    D.v1_lo     = 0.5;   D.v1_hi = 4.5;
    D.v2_lo     = 0.25;  D.v2_hi = 2.25;

    D.v_oor_lo  = 0.20;
    D.v_oor_hi  = 4.80;
    D.dv_max    = 1.50;
    D.corr_tol  = 10.0;

    D.confirm_cnt = 20;
    D.heal_cnt    = 300;
    D.warm_min    = 60.0;
end
