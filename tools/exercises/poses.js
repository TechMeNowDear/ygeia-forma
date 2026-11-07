'use strict';
// Κοινές στάσεις: ανάσκελα στον πάγκο, καθιστός σε κλίση, κάμψεις, γονατιστός.
const E = require('./engine');
const { add, sub, mul, norm, lerp, body, anchor, solve, footFlat, A, len, cross, dot } = E;
const ARM = A.uarm + A.farm + A.grip;

// Πέλματα στο πάτωμα δεξιά-αριστερά του πάγκου (z μπροστά), γόνατα προς τα έξω/πάνω.
function feetBeside(x, z, toe) {
  const fL = footFlat(x, z, toe || 15), fR = footFlat(-x, z, -(toe || 15));
  return {
    legL: { to: fL.an, pole: [0.7, 0.8, 0.3], heel: fL.heel, toe: fL.toe },
    legR: { to: fR.an, pole: [-0.7, 0.8, 0.3], heel: fR.heel, toe: fR.toe },
  };
}

// Ανάσκελα στον επίπεδο πάγκο (S.bench() πρώτα): κεφάλι προς -z, λεκάνη στο z = pz.
function supine(S, o) {
  const pz = o.pz === undefined ? 0.06 : o.pz;
  const base = { P: [0, S.padTop + 0.1, pz], pitch: -90, neck: o.neck || 0, lumb: o.lumb || 0, thor: o.thor || 0,
    ...(o.legs || feetBeside(0.34, pz + 0.42)) };
  const B0 = body(base);
  Object.assign(base, o.arms ? o.arms(B0.J, B0.F) : {});
  return body(base);
}

// Καθιστός με την πλάτη στην κλίση του πάγκου (S.bench({back}) πρώτα). lean = γωνία κορμού από την κατακόρυφη.
function inclined(S, o) {
  const back = o.back; // μοίρες από το οριζόντιο
  const pitch = -(90 - back);
  const P0 = add(add(S.backAt(0.12), mul(S.backN, 0.11)), mul(S.backDir, -0.16));
  const pel = [0, Math.max(S.padTop + 0.09, P0[1]), P0[2]];
  const base = { P: pel, pitch, neck: o.neck || 0, ...(o.legs || feetBeside(0.3, pel[2] + 0.55, 12)) };
  const B0 = body(base);
  // ο κορμός ακουμπά στην πλάτη: μετακίνηση κατά μήκος της καθέτου ώστε η πλάτη του θώρακα να αγγίζει
  const back3 = add(B0.J.chest, mul(B0.F.chest.z, -0.12));
  const d = dot(sub(S.backAt(0.3), back3), S.backN);
  base.P = add(base.P, mul(S.backN, d));
  const B1 = body(base);
  Object.assign(base, o.arms ? o.arms(B1.J, B1.F) : {});
  return body(base);
}

// Κάμψεις: μύτες στο πάτωμα στο z=0, χέρια σε ύψος hy. Επιστρέφει builder(p) με σώμα σε ευθεία.
// bottom: πόσο πάνω από τα χέρια σταματά το στήθος. Οι αγκώνες ~45° από τον κορμό.
function pushup(hy, hx, bottom, perp) {
  const build = (th, hand, arms) => {
    const base = { P: [0, 1, 0], pitch: th, neck: 0,
      legL: { hip: 0, knee: 0, ank: 4 }, legR: { hip: 0, knee: 0, ank: 4 } };
    const B0 = body(base);
    const toe = lerp(B0.J.toeL, B0.J.toeR, 0.5);
    anchor(B0, 'pelvis', add(B0.J.pelvis, sub([0, 0.02, 0], [0, toe[1], toe[2]])));
    if (!hand) return B0;
    base.P = B0.J.pelvis;
    base.armL = { to: [hx, hand[1], hand[2]], pole: [0.75, 0.15, -0.65], pr: 0 };
    base.armR = { to: [-hx, hand[1], hand[2]], pole: [-0.75, 0.15, -0.65], pr: 0 };
    return body(base);
  };
  // Θέση χεριών στην πάνω θέση: perp = χέρι κάθετο στον κορμό (κάμψεις σε ύψος), αλλιώς κάθετο στο πάτωμα.
  const top = ARM * 0.97;
  let hand;
  if (perp) {
    const Bt = build(70);
    const toe = lerp(Bt.J.toeL, Bt.J.toeR, 0.5);
    const Lts = len(sub(Bt.J.shC, toe));
    const dist = Math.sqrt(Lts * Lts + top * top);
    hand = [0, hy, toe[2] + Math.sqrt(dist * dist - (hy - toe[1]) ** 2)];
  } else {
    const th = solve(t => build(t).J.shC[1] - (hy + top), 10, 100);
    hand = [0, hy, build(th).J.shC[2] + 0.02];
  }
  const shTo = th => len(sub(build(th).J.shC, hand));
  const thTop = solve(th => shTo(th) - top, 10, 120);
  const thBot = solve(th => { const B = build(th); return (B.J.chest[1] - 0.11) - (hy + bottom); }, thTop, 120);
  return p => build(thTop + (thBot - thTop) * p, hand);
}

module.exports = { feetBeside, supine, inclined, pushup, ARM };
