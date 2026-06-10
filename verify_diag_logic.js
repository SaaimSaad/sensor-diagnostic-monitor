// verify_diag_logic.js — headless check that the diagnostic monitor meets
// REQ-DIAG-001…010. Replicates the logic in sensor-diagnostics.html and
// matlab/DiagMonitor (Stateflow). Run:  node verify_diag_logic.js
//
// Monitored signal: a redundant analog position sensor pair (APP1 / APP2).
//   APP1 (primary)   : 0.5 … 4.5 V  over 0 … 100 %
//   APP2 (redundant) : 0.25 … 2.25 V over 0 … 100 % (half-scale)
// Three rationality tests feed an OBD-style confirmation / healing monitor:
//   range (electrical OOR) · rate (implausible step) · correlation (A vs B).
const P = {
  Ts:0.01,
  v_oor_lo:0.20, v_oor_hi:4.80,   // electrical out-of-range, primary sensor [V]
  dv_max:1.50,                    // max plausible step per sample [V]  (rate)
  corr_tol:10.0,                  // max |pct1 - pct2| mismatch [%]      (correlation)
  confirm_cnt:20,                 // sustained failing samples to CONFIRM (= 200 ms)
  heal_cnt:300,                   // clean samples to heal (stands in for 3 warm-up cycles)
  warm_min:60.0                   // coolant temp [°C] enabling diagnostics
};
const S = { NO_FAULT:0, PENDING:1, CONFIRMED:2, HEALING:3 };
const NAME = ['NO_FAULT','PENDING','CONFIRMED','HEALING'];

const v1_of   = pct => 0.5  + pct/100*4.0;     // APP1 volts for a pedal %
const v2_of   = pct => 0.25 + pct/100*2.0;     // APP2 volts for a pedal %
const pct1_of = v   => (v - 0.5 ) / 4.0 * 100;
const pct2_of = v   => (v - 0.25) / 2.0 * 100;

function makeState(){
  return { state:S.NO_FAULT, failCnt:0, healCnt:0, dtc:0, mil:0,
           freeze:null, history:[], v1_prev:0.5, t:0 };
}

// One discrete monitor step at Ts. Mirrors the Stateflow chart + rationality block.
function step(st, inp){
  const enable = inp.ect >= P.warm_min;                              // REQ-DIAG-009
  const v1 = inp.v1, v2 = inp.v2;
  const p1 = pct1_of(v1), p2 = pct2_of(v2);

  const range_bad = (v1 < P.v_oor_lo) || (v1 > P.v_oor_hi);          // REQ-DIAG-001
  const rate_bad  = Math.abs(v1 - st.v1_prev) > P.dv_max;            // REQ-DIAG-002
  const corr_bad  = Math.abs(p1 - p2) > P.corr_tol;                  // REQ-DIAG-003
  const any_bad   = range_bad || rate_bad || corr_bad;
  const testbits  = (range_bad?1:0) | (rate_bad?2:0) | (corr_bad?4:0);

  if(enable){
    if(any_bad){ st.failCnt = Math.min(st.failCnt + 1, P.confirm_cnt); st.healCnt = 0; }
    else       { st.failCnt = Math.max(st.failCnt - 1, 0); }
  }

  switch(st.state){
    case S.NO_FAULT:
      if(st.failCnt > 0) st.state = S.PENDING;                       // REQ-DIAG-005
      break;
    case S.PENDING:
      if(st.failCnt >= P.confirm_cnt){                               // REQ-DIAG-004
        st.state = S.CONFIRMED;
        st.dtc   = testbits || st.dtc;
        if(!st.freeze) st.freeze = { rpm:inp.rpm, load:inp.load, ect:inp.ect,
                                     v1, p1, p2, code:st.dtc, t:st.t }; // REQ-DIAG-006
      } else if(st.failCnt === 0){ st.state = S.NO_FAULT; }
      break;
    case S.CONFIRMED:
      if(enable && !any_bad){ st.state = S.HEALING; st.healCnt = 0; }
      else if(any_bad){ st.dtc |= testbits; }
      break;
    case S.HEALING:
      if(any_bad){ st.state = S.CONFIRMED; st.healCnt = 0; }         // re-fail → re-confirm
      else {
        st.healCnt++;
        if(st.healCnt >= P.heal_cnt){                                // REQ-DIAG-008
          st.history.push(st.dtc); st.dtc = 0; st.freeze = null;
          st.state = S.NO_FAULT; st.failCnt = 0;
        }
      }
      break;
  }
  st.mil = (st.state===S.CONFIRMED || st.state===S.HEALING) ? 1 : 0; // REQ-DIAG-007
  st.v1_prev = v1; st.t += P.Ts;
  return { range_bad, rate_bad, corr_bad, testbits, enable };
}

// Drive the monitor with a per-sample input factory; return {st, peakState, milEver, sawConfirm}.
function run(st, n, inFactory){
  let peakState = st.state, milEver = st.mil, sawConfirm = (st.state===S.CONFIRMED);
  for(let k=0;k<n;k++){
    step(st, inFactory(k));
    peakState  = Math.max(peakState, st.state===S.HEALING ? S.CONFIRMED : st.state);
    milEver    = milEver || st.mil;
    sawConfirm = sawConfirm || (st.state===S.CONFIRMED);
  }
  return { peakState, milEver, sawConfirm };
}

// nominal clean input: pedal 35 %, both sensors agree, warm engine
const clean = () => ({ v1:v1_of(35), v2:v2_of(35), rpm:1500, load:35, ect:90 });

let fails = 0;
const check = (name, cond, detail) => {
  console.log(`${cond?'[PASS]':'[FAIL]'}  ${name.padEnd(46)} ${detail}`); if(!cond) fails++;
};

console.log('\n=== Sensor-diagnostic-monitor logic verification ===');

// ---- REQ-DIAG-001/002/003 : each rationality test fires on its own fault ----
{
  let st = makeState();
  const r = step(st, { v1:4.90, v2:v2_of(35), rpm:1500, load:35, ect:90 }); // OOR high
  check('REQ-DIAG-001 range/OOR detected', r.range_bad && (r.testbits&1)!==0, `v1=4.90V testbits=${r.testbits}`);
}
{
  let st = makeState(); st.v1_prev = v1_of(20);
  const r = step(st, { v1:v1_of(20)+2.0, v2:v2_of(20), rpm:1500, load:20, ect:90 }); // 2.0V jump
  check('REQ-DIAG-002 rate/spike detected', r.rate_bad && (r.testbits&2)!==0, `Δv=2.0V > ${P.dv_max}V`);
}
{
  let st = makeState();
  const r = step(st, { v1:v1_of(40), v2:v2_of(70), rpm:1500, load:40, ect:90 }); // 30% mismatch
  check('REQ-DIAG-003 correlation fault detected', r.corr_bad && (r.testbits&4)!==0, `|p1-p2|=30% > ${P.corr_tol}%`);
}

// ---- REQ-DIAG-004 : confirmation requires sustained failures (debounce) ----
{
  let st = makeState();
  const bad = () => ({ v1:4.90, v2:v2_of(35), rpm:2500, load:55, ect:90 });
  // not yet confirmed after confirm_cnt-1 samples
  for(let k=0;k<P.confirm_cnt-1;k++) step(st, bad());
  const before = st.state;
  step(st, bad());                       // the confirming sample
  check('REQ-DIAG-004 confirms at threshold', before===S.PENDING && st.state===S.CONFIRMED,
        `pending→confirmed at ${P.confirm_cnt} samples (${(P.confirm_cnt*P.Ts*1000).toFixed(0)} ms)`);
}

// ---- REQ-DIAG-004/005/007 : single-sample glitch must NOT confirm (no false trip) ----
{
  let st = makeState();
  step(st, { v1:4.90, v2:v2_of(35), rpm:1500, load:35, ect:90 }); // 1 bad sample → PENDING
  const r = run(st, 50, clean);                                    // then all clean
  check('REQ-DIAG-004 no false trip on 1-sample glitch', !r.sawConfirm && !r.milEver && st.state===S.NO_FAULT,
        `peakState=${NAME[r.peakState]} milEver=${r.milEver}`);
}

// ---- REQ-DIAG-006 : freeze-frame captured at confirmation ----
{
  let st = makeState();
  run(st, P.confirm_cnt + 5, () => ({ v1:4.90, v2:v2_of(35), rpm:2500, load:55, ect:90 }));
  const f = st.freeze;
  check('REQ-DIAG-006 freeze-frame captured', !!f && (f.code&1)!==0 && f.rpm===2500 && f.load===55,
        f ? `code=${f.code} rpm=${f.rpm} load=${f.load}% ect=${f.ect}°C` : 'no freeze-frame');
}

// ---- REQ-DIAG-007 : MIL on iff a confirmed DTC is present ----
{
  let st = makeState();
  run(st, P.confirm_cnt + 5, () => ({ v1:4.90, v2:v2_of(35), rpm:2000, load:40, ect:90 }));
  check('REQ-DIAG-007 MIL on when confirmed', st.mil===1 && st.state===S.CONFIRMED, `mil=${st.mil}`);
}

// ---- REQ-DIAG-008 : heal only after sustained clean run; MIL clears, DTC archived ----
{
  let st = makeState();
  run(st, P.confirm_cnt + 5, () => ({ v1:4.90, v2:v2_of(35), rpm:2000, load:40, ect:90 })); // confirm
  const dtcWas = st.dtc;
  run(st, P.heal_cnt + 10, clean);                                 // clean → heal
  check('REQ-DIAG-008 heals & MIL clears', st.state===S.NO_FAULT && st.mil===0 && st.dtc===0 && st.history.length===1,
        `archived=0x${dtcWas.toString(16)} history=${st.history.length}`);
}

// ---- REQ-DIAG-009 : counters frozen when enable conditions are not met ----
{
  let st = makeState();
  const r = run(st, 100, () => ({ v1:4.90, v2:v2_of(35), rpm:600, load:5, ect:40 })); // cold (ect<60)
  check('REQ-DIAG-009 disabled: no confirm when cold', !r.sawConfirm && st.failCnt===0 && st.mil===0,
        `ect=40°C<${P.warm_min}°C failCnt=${st.failCnt}`);
}

// ---- REQ-DIAG-010 : outputs stay within declared ranges throughout a mixed run ----
{
  let st = makeState(), ok = true;
  const seq = [
    [40, clean],
    [60, () => ({ v1:4.90, v2:v2_of(35), rpm:2000, load:40, ect:90 })],
    [400, clean]
  ];
  for(const [n, f] of seq) for(let k=0;k<n;k++){ step(st, f());
    if(!(st.state>=0 && st.state<=3 && (st.mil===0||st.mil===1) && st.dtc>=0 && st.dtc<=255)) ok=false; }
  check('REQ-DIAG-010 outputs in declared range', ok, `state∈[0,3] mil∈{0,1} dtc∈[0,255]`);
}

console.log(`\n${fails===0?'ALL CHECKS PASSED':fails+' CHECK(S) FAILED'}\n`);
process.exit(fails===0?0:1);
