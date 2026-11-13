'use strict';
// Μηχανή κίνησης για τις κινούμενες ασκήσεις.
// Υπολογίζει, για κάθε άσκηση, θέσεις 3D (σώμα, εξοπλισμός, μύες) σε 21 σημεία της κίνησης
// και τις γράφει στο assets/exercises/exercises.json. Η εφαρμογή μόνο τις προβάλλει και τις ζωγραφίζει.
//
// Μονάδες: μέτρα. Άξονες: y πάνω, z μπροστά (εκεί που κοιτάζει ο ασκούμενος όρθιος), x προς τα αριστερά του.
// Γωνίες σε μοίρες.

const H = 1.77; // ύψος της φιγούρας (ενήλικας, 1,77 m)· όλες οι αναλογίες βγαίνουν από αυτό
// Ανθρωπομετρία (Winter, Biomechanics and Motor Control of Human Movement, 4η έκδ., ως κλάσματα του ύψους).
const A = {
  ankleH: 0.039 * H, heelB: 0.040 * H, toeF: 0.112 * H,
  shank: 0.246 * H, thigh: 0.245 * H,
  pelvisUp: 0.100 * H, torsoUp: 0.188 * H,
  hipHalf: 0.050 * H, shHalf: 0.105 * H, shDown: 0.018 * H,
  uarm: 0.186 * H, farm: 0.146 * H, grip: 0.045 * H,
  neck: 0.055 * H, headUp: 0.112 * H, headR: 0.062 * H,
};
const MASS = 85; // kg, μόνο για την ισορροπία· η ακρίβεια εδώ δεν αλλάζει ουσιαστικά τη στάση
const SEG = { head: 0.081, trunk: 0.497, uarm: 0.028, farm: 0.016, hand: 0.006, thigh: 0.100, shank: 0.0465, foot: 0.0145 };

const D = Math.PI / 180;
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const len = a => Math.hypot(a[0], a[1], a[2]);
const norm = a => { const l = len(a) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };
const lerp = (a, b, t) => typeof a === 'number' ? a + (b - a) * t : [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const sum = (...vs) => vs.reduce((s, x) => add(s, x), [0, 0, 0]);
const ortho = (v, axis) => norm(sub(v, mul(axis, dot(v, axis)))); // v χωρίς τη συνιστώσα κατά axis

const rx = a => { const c = Math.cos(a * D), s = Math.sin(a * D); return [[1, 0, 0], [0, c, -s], [0, s, c]]; };
const ry = a => { const c = Math.cos(a * D), s = Math.sin(a * D); return [[c, 0, s], [0, 1, 0], [-s, 0, c]]; };
const rz = a => { const c = Math.cos(a * D), s = Math.sin(a * D); return [[c, -s, 0], [s, c, 0], [0, 0, 1]]; };
const mm = (P, Q) => P.map(r => [0, 1, 2].map(j => r[0] * Q[0][j] + r[1] * Q[1][j] + r[2] * Q[2][j]));
const mv = (M, v) => [dot(M[0], v), dot(M[1], v), dot(M[2], v)];
const chain = (...ms) => ms.reduce((acc, m) => mm(acc, m));

// Διχοτόμηση: βρίσκει x στο [lo, hi] με f(x) = 0 (η f αλλάζει πρόσημο στο διάστημα).
function solve(f, lo, hi, it = 50) {
  let flo = f(lo);
  for (let i = 0; i < it; i++) {
    const m = (lo + hi) / 2, fm = f(m);
    if ((fm > 0) === (flo > 0)) { lo = m; flo = fm; } else hi = m;
  }
  return (lo + hi) / 2;
}

// Ανάστροφη κινηματική δύο τμημάτων: από τη ρίζα S στον στόχο T, με το μεσαίο σημείο προς το pole.
function ik2(S, T, L1, L2, pole) {
  let d = sub(T, S); let dl = len(d);
  const maxd = (L1 + L2) * 0.9995, mind = Math.abs(L1 - L2) + 1e-4;
  const dir = norm(d);
  dl = Math.min(Math.max(dl, mind), maxd);
  const T2 = add(S, mul(dir, dl));
  const a = (L1 * L1 - L2 * L2 + dl * dl) / (2 * dl);
  const h = Math.sqrt(Math.max(0, L1 * L1 - a * a));
  const pp = ortho(pole, dir);
  const M = add(add(S, mul(dir, a)), mul(pp, h));
  return { mid: M, end: T2, bend: pp, reach: len(sub(T, S)) / (L1 + L2) };
}

// ------------------------------------------------------------------ σώμα
// o.P: θέση λεκάνης, o.pitch/yaw/roll: προσανατολισμός λεκάνης. Σπονδυλική: lumb, thor, tw, neck.
// Χέρια: o.armR/o.armL = {sf, sa, sr, el, pr} (FK) ή {to, pole, pr} (IK).
// Πόδια: o.legR/o.legL = {hip, abd, hr, knee, ank} (FK) ή {to (αστράγαλος), pole, heel, toe} (IK).
function body(o) {
  const J = {}, F = {};
  const Rp = chain(ry(o.yaw || 0), rx(o.pitch || 0), rz(o.roll || 0));
  const P = o.P || [0, 0, 0];
  const Rl = mm(Rp, rx(o.lumb || 0));
  const Rc = chain(Rl, rx(o.thor || 0), ry(o.tw || 0));
  const Rn = mm(Rc, rx(o.neck || 0));
  F.pelvis = frame(Rp); F.lumb = frame(Rl); F.chest = frame(Rc); F.neck = frame(Rn);
  J.pelvis = P;
  J.hipL = add(P, mul(F.pelvis.x, A.hipHalf));
  J.hipR = add(P, mul(F.pelvis.x, -A.hipHalf));
  J.waist = add(P, mv(Rl, [0, A.pelvisUp, 0]));
  J.belly = add(P, mv(Rl, [0, A.pelvisUp * 0.55, 0.012]));
  J.shC = add(J.waist, mv(Rc, [0, A.torsoUp, 0]));
  J.chest = add(J.waist, mv(Rc, [0, A.torsoUp * 0.5, 0.005]));
  J.shL = add(J.shC, mv(Rc, [A.shHalf, -A.shDown, 0]));
  J.shR = add(J.shC, mv(Rc, [-A.shHalf, -A.shDown, 0]));
  J.neckTop = add(J.shC, mv(Rn, [0, A.neck, 0.01]));
  J.head = add(J.shC, mv(Rn, [0, A.headUp, 0.018]));
  J.nose = add(J.head, mv(Rn, [0, -0.01, A.headR * 0.95])); // για την κατεύθυνση του προσώπου
  for (const [s, k] of [[1, 'L'], [-1, 'R']]) {
    arm(J, F, Rc, s, k, o['arm' + k] || { sf: 0, sa: 6, el: 8 });
    leg(J, F, Rp, s, k, o['leg' + k] || { hip: 0, knee: 2 });
  }
  return { J, F };
}
function frame(R) { return { x: mv(R, [1, 0, 0]), y: mv(R, [0, 1, 0]), z: mv(R, [0, 0, 1]) }; }

function arm(J, F, Rc, s, k, a) {
  const S = J['sh' + k];
  let E, G, ant;
  if (a.to) {
    const r = ik2(S, a.to, A.uarm, A.farm + A.grip, a.pole);
    E = r.mid; G = r.end; ant = mul(r.bend, -1);
  } else {
    const Ru = chain(Rc, rz(s * (a.sa || 0)), rx(-(a.sf || 0)), ry(s * (a.sr || 0)));
    E = add(S, mv(Ru, [0, -A.uarm, 0]));
    const Rf = mm(Ru, rx(-(a.el || 0)));
    G = add(E, mv(Rf, [0, -(A.farm + A.grip), 0]));
    ant = mv(Ru, [0, 0, 1]);
  }
  const fa = norm(sub(G, E));
  J['elb' + k] = E;
  J['wri' + k] = add(E, mul(fa, A.farm));
  J['grp' + k] = G;
  const ua = norm(sub(E, S));
  ant = ortho(ant, ua);
  const lat = norm(cross(ua, ant)); // κάθετα στο επίπεδο κάμψης
  // Λαβή: pr 0 = ουδέτερη (η λαβή του αλτήρα κατά μήκος της κάμψης), 90 = κάθετα (πρηνής/υπτία)
  const fant = ortho(ant, fa);
  const flat = norm(cross(fa, fant));
  const pr = (a.pr === undefined ? 90 : a.pr) * D;
  F['uarm' + k] = { ax: ua, ant, lat };
  F['farm' + k] = { ax: fa, ant: fant, lat: flat, handle: norm(add(mul(fant, Math.cos(pr)), mul(flat, Math.sin(pr)))) };
}

function leg(J, F, Rp, s, k, l) {
  const Hp = J['hip' + k];
  let K, An, ant, Rft = null;
  if (l.to) {
    const r = ik2(Hp, l.to, A.thigh, A.shank, l.pole || [0, 0, 1]);
    K = r.mid; An = r.end; ant = r.bend;
  } else {
    const Rt = chain(Rp, rz(s * (l.abd || 0)), rx(-(l.hip || 0)), ry(s * (l.hr || 0)));
    K = add(Hp, mv(Rt, [0, -A.thigh, 0]));
    const Rs = mm(Rt, rx(l.knee || 0));
    An = add(K, mv(Rs, [0, -A.shank, 0]));
    Rft = mm(Rs, rx(-(l.ank || 0)));
    ant = mv(Rt, [0, 0, 1]);
  }
  J['knee' + k] = K; J['ank' + k] = An;
  if (l.heel) { J['heel' + k] = l.heel; J['toe' + k] = l.toe; }
  else if (Rft) {
    J['heel' + k] = add(An, mv(Rft, [0, -A.ankleH * 0.85, -A.heelB]));
    J['toe' + k] = add(An, mv(Rft, [0, -A.ankleH * 0.55, A.toeF]));
  } else {
    // πέλμα κάθετα στην κνήμη, χωρίς πληροφορία στροφής: προς τα εμπρός της λεκάνης
    const sh = norm(sub(An, K)), f = ortho(F.pelvis ? Fdir(F) : [0, 0, 1], sh);
    J['heel' + k] = add(add(An, mul(sh, A.ankleH * 0.85)), mul(f, -A.heelB));
    J['toe' + k] = add(add(An, mul(sh, A.ankleH * 0.55)), mul(f, A.toeF));
  }
  const th = norm(sub(K, Hp));
  ant = ortho(ant, th);
  F['thigh' + k] = { ax: th, ant, lat: norm(cross(th, ant)) };
  const sh = norm(sub(An, K));
  F['shank' + k] = { ax: sh, ant: ortho(ant, sh) };
}
function Fdir(F) { return F.pelvis.z; }

// Πέλμα πατημένο στο πάτωμα: αστράγαλος, φτέρνα και μύτη για πέλμα με μύτη προς yaw (μοίρες, 0 = μπροστά).
function footFlat(x, z, yaw, side) {
  const d = mv(ry(yaw), [0, 0, 1]);
  const an = [x, A.ankleH, z];
  return { an, heel: add([x, 0.012, z], mul(d, -A.heelB)), toe: add([x, 0.012, z], mul(d, A.toeF)), dir: d, mid: add([x, 0, z], mul(d, 0.035 * H)) };
}
// Πέλμα στις μύτες (πίσω πόδι): η μύτη στο σημείο, η φτέρνα σηκωμένη κατά γωνία g από το πάτωμα.
function footToes(x, z, g) {
  const toe = [x, 0.012, z];
  const back = [0, Math.sin(g * D), -Math.cos(g * D)];
  const an = add(add(toe, mul(back, A.toeF)), mul([0, Math.cos(g * D), Math.sin(g * D)], A.ankleH * 0.6));
  return { an, toe, heel: add(an, add(mul(back, A.heelB), [0, -A.ankleH * 0.6, 0])) };
}

// Κέντρο μάζας σώματος (+ φορτία [θέση, kg]).
function com(J, loads = []) {
  const m = MASS; let s = [0, 0, 0], tm = 0;
  const put = (p, f) => { s = add(s, mul(p, f)); tm += f; };
  put(J.head, SEG.head * m);
  put(lerp(J.pelvis, J.shC, 0.45), SEG.trunk * m);
  for (const k of ['L', 'R']) {
    put(lerp(J['sh' + k], J['elb' + k], 0.44), SEG.uarm * m);
    put(lerp(J['elb' + k], J['wri' + k], 0.43), SEG.farm * m);
    put(J['grp' + k], SEG.hand * m);
    put(lerp(J['hip' + k], J['knee' + k], 0.43), SEG.thigh * m);
    put(lerp(J['knee' + k], J['ank' + k], 0.43), SEG.shank * m);
    put(lerp(J['heel' + k], J['toe' + k], 0.45), SEG.foot * m);
  }
  for (const [p, kg] of loads) put(p, kg);
  return mul(s, 1 / tm);
}

// Μετακινεί όλα τα σημεία του σώματος ώστε το σημείο name να πάει στη θέση to.
function anchor(B, name, to) {
  const d = sub(to, B.J[name]);
  for (const k of Object.keys(B.J)) B.J[k] = add(B.J[k], d);
  return d;
}
function shift(B, d) { for (const k of Object.keys(B.J)) B.J[k] = add(B.J[k], d); }

// Όρθια στάση με πατημένα πόδια. Η κλίση της κνήμης λύνεται ώστε το κέντρο μάζας να είναι πάνω από τη μέση του πέλματος.
// o: knee (κάμψη γονάτου), pitch (κλίση λεκάνης/κορμού μπροστά), lumb/thor/neck, w (απόσταση αστραγάλων), toe (μύτες έξω),
//    arms(J0) → {armL, armR}, loads(J) → [[θέση, kg]], comShift (πόσο μπροστά από τη μέση πέλματος)
function stand(o) {
  const w = o.w === undefined ? 0.22 : o.w, toe = o.toe || 0;
  const fL = footFlat(w / 2, 0, toe, 1), fR = footFlat(-w / 2, 0, -toe, -1);
  const mid = (fL.mid[2] + fR.mid[2]) / 2 + (o.comShift || 0);
  let B;
  const build = sig => {
    // Κνήμη: κλίση sig μπροστά, στο επίπεδο που δείχνουν οι μύτες· μηρός: γωνία γονάτου από την κνήμη.
    const legPlane = (f, s) => {
      const d = f.dir; // μπροστά στο επίπεδο του ποδιού
      const kneeP = add(f.an, add(mul([0, 1, 0], A.shank * Math.cos(sig * D)), mul(d, A.shank * Math.sin(sig * D))));
      const th = sig - o.knee; // κλίση μηρού (από την κατακόρυφη, + μπροστά)
      const hipP = add(kneeP, add(mul([0, 1, 0], A.thigh * Math.cos(th * D)), mul(d, A.thigh * Math.sin(th * D))));
      return { kneeP, hipP };
    };
    const L = legPlane(fL, 1), R = legPlane(fR, -1);
    const P = mul(add(L.hipP, R.hipP), 0.5);
    P[0] = 0;
    const arms = o.arms ? o.arms : () => ({});
    const base = { P, pitch: o.pitch || 0, lumb: o.lumb, thor: o.thor, neck: o.neck, yaw: 0,
      legL: { to: fL.an, pole: add(sub(L.kneeP, fL.an), mul(fL.dir, 0.3)), heel: fL.heel, toe: fL.toe },
      legR: { to: fR.an, pole: add(sub(R.kneeP, fR.an), mul(fR.dir, 0.3)), heel: fR.heel, toe: fR.toe } };
    // Χέρια: πρώτο πέρασμα για να ξέρουμε πού είναι οι ώμοι
    const B0 = body(base);
    Object.assign(base, arms(B0.J, B0.F));
    B = body(base);
    B.loads = o.loads ? o.loads(B.J, B.F) : [];
    return B;
  };
  const f = sig => { const b = build(sig); return com(b.J, b.loads)[2] - mid; };
  const sig = o.sig !== undefined ? o.sig : solve(f, -15, 60);
  build(sig);
  B.sig = sig; B.feet = { L: fL, R: fR };
  B.mid = mid;
  return B;
}

module.exports = { H, A, D, add, sub, mul, dot, cross, len, norm, lerp, sum, ortho, rx, ry, rz, mm, mv, chain,
  solve, ik2, body, footFlat, footToes, com, anchor, shift, stand };
