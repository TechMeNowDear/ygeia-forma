'use strict';
// Σκηνή: σημεία με όνομα + σχήματα (εξοπλισμός) + μύες + οδηγοί. Ό,τι γράφεται εδώ το ζωγραφίζει
// ο ίδιος κώδικας στην εφαρμογή (lib/exercise/ex_painter.dart) και στην προεπισκόπηση (preview.html).
const E = require('./engine');
const { add, sub, mul, norm, cross, lerp, ortho, A, dot } = E;

// Χρώματα εξοπλισμού (σταθερά σε ανοιχτό και σκούρο θέμα, όπως είναι στην πραγματικότητα)
const COL = {
  red: '#B91C1C', black: '#1F2937', pad: '#27272A', chrome: '#9CA3AF', iron: '#111827', plate: '#18181B', plateRim: '#3F3F46',
  yellow: '#EAB308', mat: '#334155', wood: '#A16207',
  band: { yellow: '#FACC15', blue: '#0EA5E9', green: '#16A34A', black: '#111827', red: '#DC2626' },
  kb: { 4: '#FACC15', 6: '#DC2626', 8: '#2563EB', 10: '#6B7280', 12: '#111827', 16: '#111827' },
};
const PLATE_R = { 5: 0.115, 2.5: 0.095, 1.25: 0.08, 0.5: 0.062 };
const PLATE_T = { 5: 0.032, 2.5: 0.026, 1.25: 0.02, 0.5: 0.014 };

class Scene {
  constructor() { this.pts = {}; this.prims = []; this.mus = []; this.guides = []; this.n = 0; }
  pt(p, name) { const k = name || ('_' + (this.n++)); this.pts[k] = p.map(v => Math.round(v * 1000) / 1000); return k; }
  prim(o) { this.prims.push(o); return o; }

  body(B) { for (const [k, v] of Object.entries(B.J)) this.pt(v, k); this.B = B; return this; }

  // ---------------------------------------------------------------- βασικά σχήματα
  box(c, u, v, w, col, z) { // κέντρο και τρία μισά διανύσματα
    const p = [];
    for (const a of [-1, 1]) for (const b of [-1, 1]) for (const d of [-1, 1]) p.push(this.pt(add(add(add(c, mul(u, a)), mul(v, b)), mul(w, d))));
    return this.prim({ k: 'box', p, col, z: z || 0 });
  }
  rod(a, b, r, col, z) { return this.prim({ k: 'rod', a: this.pt(a), b: this.pt(b), r, col, z: z || 0 }); }
  disc(c, n, r, col, rim, z) { return this.prim({ k: 'disc', c: this.pt(c), n: this.pt(add(c, mul(norm(n), 0.1))), r, col, rim: rim || col, z: z || 0 }); }
  ball(c, r, col, z) { return this.prim({ k: 'ball', c: this.pt(c), r, col, z: z || 0 }); }
  poly(ps, w, col, z) { return this.prim({ k: 'poly', p: ps.map(p => this.pt(p)), w, col, z: z || 0 }); }

  // ---------------------------------------------------------------- εξοπλισμός
  // Πάγκος XFIT κατά μήκος του z. Η πλάτη από z=-0.85 ως -0.04 (πλευρά κεφαλιού), το κάθισμα ως 0.32,
  // η μονάδα ποδιών στο άκρο του καθίσματος. back: κλίση πλάτης (0 επίπεδη), seat: κλίση καθίσματος.
  bench(o = {}) {
    const top = 0.44, t = 0.065, hw = 0.14, back = o.back || 0, seat = o.seat || 0, sl = o.seatLen || 0.32;
    const Rb = E.ry(o.rot || 0), at = o.at || [0, 0, 0];
    const tp = p => add(at, E.mv(Rb, p)), td = d => E.mv(Rb, d);
    const X = td([1, 0, 0]);
    const rod = (a, b, r, c) => this.rod(tp(a), tp(b), r, c, 0.05);
    // σκελετός
    rod([0, 0.30, -0.80], [0, 0.30, 0.50], 0.03, COL.red);
    rod([0, 0.02, -0.86], [0, 0.30, -0.80], 0.025, COL.black);
    rod([-0.26, 0.02, -0.86], [0.26, 0.02, -0.86], 0.025, COL.black);
    rod([0, 0.02, 0.48], [0, 0.30, 0.46], 0.028, COL.black);
    rod([-0.24, 0.02, 0.50], [0.24, 0.02, 0.50], 0.025, COL.black);
    // πλάτη: από τον μεντεσέ (z=-0.04) προς το κεφάλι, ανεβαίνει με την κλίση
    const hinge = tp([0, top - t / 2, -0.04]);
    const bd = td([0, Math.sin(back * E.D), -Math.cos(back * E.D)]);
    const bn = norm(cross(X, bd));
    this.box(add(hinge, mul(bd, 0.41)), mul(X, hw), mul(bd, 0.41), mul(bn, t / 2), COL.pad, 0.04);
    if (back > 5) this.rod(add(hinge, mul(bd, 0.35)), tp([0, 0.30, -0.45]), 0.022, COL.red, 0.06);
    // κάθισμα
    const sd = td([0, Math.sin(seat * E.D), Math.cos(seat * E.D)]);
    const sn = norm(cross(sd, X));
    const sc = add(tp([0, top - t / 2, 0.0]), mul(sd, sl / 2));
    this.box(sc, mul(X, hw * 0.95), mul(sd, sl / 2), mul(sn, t / 2), COL.pad, 0.04);
    this.seatAt = s => add(add(tp([0, top - t / 2, 0]), mul(sd, s)), mul(sn, t / 2)); // επιφάνεια καθίσματος
    this.backAt = s => add(add(hinge, mul(bd, s)), mul(bn, t / 2)); // επιφάνεια πλάτης, s μέτρα από τον μεντεσέ
    this.backDir = bd; this.backN = bn; this.benchTop = top + t / 2 - 0.0325 + 0.0325;
    this.padTop = top + t / 2;
    if (o.unit !== false) rod([0, 0.30, 0.46], [0, 0.56, 0.42], 0.025, COL.black);
    return this;
  }
  // Μοχλός μονάδας ποδιών: άξονας pivot, ρολό στο end. Δίσκοι στο κέρατο.
  lever(pivot, end, plates, z) {
    this.rod(pivot, end, 0.022, COL.red, z || 0);
    this.rod(add(end, [-0.13, 0, 0]), add(end, [0.13, 0, 0]), 0.042, COL.pad, z || 0);
    this.ball(pivot, 0.03, COL.black, z || 0);
    if (plates && plates.length) {
      const d = norm(sub(end, pivot));
      const horn = add(pivot, mul(d, -0.16));
      this.rod(pivot, horn, 0.018, COL.red, z || 0);
      let x = 0.05;
      for (const kg of plates) { this.disc(add(horn, [x, 0, 0]), [1, 0, 0], PLATE_R[kg], COL.plate, COL.plateRim, 0); x += PLATE_T[kg]; }
    }
  }
  stand(x, z, top) { // βάση καθισμάτων XFIT (χωρίς βραχίονες ασφαλείας)
    this.rod([x, 0.02, z - 0.28], [x, 0.02, z + 0.28], 0.025, COL.red, 0.05);
    this.rod([x - 0.25, 0.02, z], [x + 0.25, 0.02, z], 0.025, COL.red, 0.05);
    this.rod([x, 0.02, z], [x, top, z], 0.03, COL.black, 0.05);
    this.rod([x, top, z - 0.04], [x, top + 0.07, z - 0.05], 0.012, COL.black, 0.05);
    this.rod([x, top, z + 0.04], [x, top + 0.07, z + 0.05], 0.012, COL.black, 0.05);
    return [x, top - 0.12, z];
  }
  dips(z, gap, h) { // δύο κίτρινα πλαίσια «Π», οι λαβές κατά μήκος του z
    for (const x of [-gap / 2, gap / 2]) {
      const xo = x + Math.sign(x) * 0.04;
      this.rod([xo, 0.02, z - 0.3], [xo, h, z - 0.3], 0.022, COL.yellow, 0.05);
      this.rod([xo, 0.02, z + 0.3], [xo, h, z + 0.3], 0.022, COL.yellow, 0.05);
      this.rod([xo, 0.02, z - 0.34], [xo, 0.02, z + 0.34], 0.022, COL.yellow, 0.05);
      this.rod([xo, h, z - 0.3], [xo, h, z + 0.3], 0.022, COL.yellow, 0.05);
      this.rod([x, h + 0.015, z - 0.12], [x, h + 0.015, z + 0.12], 0.026, COL.pad, 0.0);
    }
  }
  pullup(y, wz) { // επιτοίχιο μονόζυγο: ο τοίχος στο z = wz, η μπάρα 0.5 m μπροστά του
    const bz = wz - 0.5;
    this.rod([-0.32, y, bz], [0.32, y, bz], 0.016, COL.chrome, 0.02);
    for (const s of [-1, 1]) {
      this.rod([s * 0.32, y, bz], [s * 0.58, y - 0.12, bz + 0.04], 0.016, COL.chrome, 0.02);
      this.rod([s * 0.42, y + 0.02, bz - 0.02], [s * 0.42, y + 0.02, bz + 0.16], 0.016, COL.chrome, 0.02);
      this.rod([s * 0.32, y, bz], [s * 0.32, y + 0.12, wz], 0.022, COL.black, 0.03);
      this.box([s * 0.32, y + 0.12, wz], [0.06, 0, 0], [0, 0.10, 0], [0, 0, 0.01], COL.black, 0.04);
    }
    this.box([0, y - 0.3, wz + 0.02], [1.2, 0, 0], [0, 0.9, 0], [0, 0, 0.005], '#D5DCE6', 0.5).wall = 1;
    return { bar: [0, y, bz], neutral: s => [s * 0.42, y + 0.02, bz + 0.07] };
  }
  mat(z0, z1, w) { this.box([0, 0.006, (z0 + z1) / 2], [(w || 0.6) / 2, 0, 0], [0, 0.006, 0], [0, 0, (z1 - z0) / 2], COL.mat, 0.3); }

  // Λάστιχο από σημείο αγκύρωσης σε σημείο (λαβή): λίγο καμπυλωμένο όταν είναι χαλαρό.
  band(a, b, color, z) {
    this.poly([a, lerp(a, b, 0.5), b], 0.012, COL.band[color], z === undefined ? -0.01 : z);
  }
  handle(g, axis) { this.rod(add(g, mul(axis, -0.06)), add(g, mul(axis, 0.06)), 0.02, COL.pad, -0.02); }

  barbell(gL, gR, plates) {
    const c = lerp(gL, gR, 0.5), ax = norm(sub(gL, gR));
    this.rod(add(c, mul(ax, -0.915)), add(c, mul(ax, 0.915)), 0.014, COL.chrome, 0);
    for (const s of [-1, 1]) {
      let x = 0.47;
      for (const kg of plates) {
        const t = PLATE_T[kg];
        this.disc(add(c, mul(ax, s * (x + t / 2))), ax, PLATE_R[kg], COL.plate, COL.plateRim, 0);
        x += t;
      }
      this.disc(add(c, mul(ax, s * (x + 0.012))), ax, 0.035, COL.chrome, COL.chrome, 0);
    }
    return c;
  }
  dumbbell(g, axis, plates) {
    const ax = norm(axis);
    this.rod(add(g, mul(ax, -0.2)), add(g, mul(ax, 0.2)), 0.013, COL.chrome, -0.005);
    for (const s of [-1, 1]) {
      let x = 0.075;
      for (const kg of plates) {
        const t = PLATE_T[kg];
        this.disc(add(g, mul(ax, s * (x + t / 2))), ax, PLATE_R[kg], COL.plate, COL.plateRim, -0.005);
        x += t;
      }
      this.disc(add(g, mul(ax, s * (x + 0.01))), ax, 0.03, COL.chrome, COL.chrome, -0.005);
    }
  }
  // Kettlebell: c = κέντρο σώματος, up = προς τη λαβή, side = κατά μήκος της λαβής.
  kettlebell(c, up, side, kg) {
    const r = { 4: 0.08, 6: 0.085, 8: 0.09, 10: 0.095, 12: 0.1, 16: 0.105 }[kg] || 0.1;
    const u = norm(up), s = ortho(side, u);
    this.ball(c, r, COL.kb[kg], -0.01);
    const pts = [];
    for (let i = 0; i <= 10; i++) {
      const a = Math.PI * i / 10;
      pts.push(add(add(c, mul(u, r * 0.75 + Math.sin(a) * r * 0.85)), mul(s, Math.cos(a) * r * 0.62)));
    }
    this.poly(pts, 0.02, COL.kb[kg], -0.012);
    return add(c, mul(u, r * 1.6));
  }
  wheel(c) {
    this.rod(add(c, [-0.13, 0, 0]), add(c, [0.13, 0, 0]), 0.012, COL.chrome, 0);
    for (const x of [-0.045, 0.045]) this.disc(add(c, [x, 0, 0]), [1, 0, 0], 0.09, '#DC2626', '#111827', 0);
    for (const x of [-0.12, 0.12]) this.rod(add(c, [x - 0.025, 0, 0]), add(c, [x + 0.025, 0, 0]), 0.02, COL.pad, -0.01);
  }

  // ---------------------------------------------------------------- οδηγοί (μόνο στην προεπιλεγμένη όψη)
  // Γραμμή-οδηγός από a σε b· η ετικέτα στο σημείο lp (3D).
  guide(a, b, color, label, lp, dash) {
    this.guides.push({ a: this.pt(a), b: this.pt(b), col: color, l: label || null, c: this.pt(lp || b), d: !!dash });
  }

  // ---------------------------------------------------------------- μύες
  // Έλλειψη πάνω στην επιφάνεια: κέντρο c, μισοί άξονες u, v, η κάθετος προς τα έξω out.
  ell(id, host, c, u, v, out) {
    if (dot(cross(u, v), out) < 0) v = mul(v, -1);
    this.mus.push({ m: id, h: host, c: this.pt(c), u: this.pt(add(c, u)), v: this.pt(add(c, v)) });
  }
  muscles(ids) {
    const { J, F } = this.B;
    const set = new Set(ids);
    const C = F.chest, Lm = F.lumb, P = F.pelvis;
    for (const [s, k] of [[1, 'L'], [-1, 'R']]) {
      const lat = mul(C.x, s), latL = mul(Lm.x, s), latP = mul(P.x, s);
      const sh = J['sh' + k], el = J['elb' + k], wr = J['wri' + k];
      const U = F['uarm' + k], Fa = F['farm' + k], T = F['thigh' + k], Sh = F['shank' + k];
      const hip = J['hip' + k], kn = J['knee' + k], an = J['ank' + k];
      const ul = len(sub(el, sh)), tl = len(sub(kn, hip));
      if (set.has('chest')) this.ell('chest', 'torso', sum(J.chest, mul(C.z, 0.112), mul(lat, 0.085), mul(C.y, 0.06)), mul(lat, 0.078), mul(C.y, 0.062), C.z);
      if (set.has('frontdelt')) this.ell('frontdelt', 'uarm' + k, sum(sh, mul(C.z, 0.045), mul(U.ax, 0.035)), mul(U.ax, 0.06), mul(lat, 0.03), C.z);
      if (set.has('sidedelt')) this.ell('sidedelt', 'uarm' + k, sum(sh, mul(lat, 0.05), mul(U.ax, 0.035)), mul(U.ax, 0.065), mul(C.z, 0.032), lat);
      if (set.has('reardelt')) this.ell('reardelt', 'uarm' + k, sum(sh, mul(C.z, -0.045), mul(U.ax, 0.035)), mul(U.ax, 0.06), mul(lat, 0.03), mul(C.z, -1));
      if (set.has('rotcuff')) this.ell('rotcuff', 'torso', sum(J.chest, mul(C.y, 0.11), mul(C.z, -0.112), mul(lat, 0.10)), mul(lat, 0.05), mul(C.y, 0.04), mul(C.z, -1));
      if (set.has('upperback')) this.ell('upperback', 'torso', sum(J.chest, mul(C.y, 0.09), mul(C.z, -0.118), mul(lat, 0.04)), mul(lat, 0.04), mul(C.y, 0.075), mul(C.z, -1));
      if (set.has('lats')) {
        const n = norm(add(mul(lat, 0.75), mul(C.z, -0.66)));
        this.ell('lats', 'torso', sum(J.chest, mul(C.y, -0.03), mul(C.z, -0.07), mul(lat, 0.105)), mul(C.y, 0.11), mul(ortho(cross(C.y, n), C.y), 0.04), n);
      }
      if (set.has('lowback')) this.ell('lowback', 'torso', sum(J.belly, mul(Lm.z, -0.105), mul(latL, 0.035)), mul(Lm.y, 0.09), mul(latL, 0.028), mul(Lm.z, -1));
      if (set.has('abs')) {
        this.ell('abs', 'torso', sum(J.belly, mul(Lm.z, 0.118), mul(latL, 0.032), mul(Lm.y, -0.01)), mul(Lm.y, 0.075), mul(latL, 0.03), Lm.z);
        this.ell('abs', 'torso', sum(J.chest, mul(C.z, 0.108), mul(lat, 0.03), mul(C.y, -0.085)), mul(C.y, 0.06), mul(lat, 0.03), C.z);
      }
      if (set.has('obliques')) this.ell('obliques', 'torso', sum(J.waist, mul(latL, 0.118), mul(Lm.z, 0.02), mul(Lm.y, -0.02)), mul(Lm.y, 0.085), mul(Lm.z, 0.05), latL);
      if (set.has('biceps')) this.ell('biceps', 'uarm' + k, sum(lerp(sh, el, 0.58), mul(U.ant, 0.036)), mul(U.ax, ul * 0.3), mul(U.lat, 0.026), U.ant);
      if (set.has('triceps')) this.ell('triceps', 'uarm' + k, sum(lerp(sh, el, 0.52), mul(U.ant, -0.038)), mul(U.ax, ul * 0.36), mul(U.lat, 0.028), mul(U.ant, -1));
      if (set.has('forearm')) this.ell('forearm', 'farm' + k, sum(lerp(el, wr, 0.32), mul(Fa.lat, 0.0), mul(Fa.ant, 0.029)), mul(Fa.ax, A.farm * 0.3), mul(Fa.lat, 0.022), Fa.ant);
      if (set.has('brachio')) { // βραχιονοκερκιδικός: πάνω πλευρά του πήχη (στην ουδέτερη λαβή)
        const n = Fa.handle && norm(cross(Fa.ax, Fa.handle));
        const o = dot(n, U.ant) < 0 ? mul(n, -1) : n;
        this.ell('brachio', 'farm' + k, sum(lerp(el, wr, 0.3), mul(o, 0.029)), mul(Fa.ax, A.farm * 0.3), mul(Fa.handle, 0.02), o);
      }
      if (set.has('glutes')) this.ell('glutes', 'torso', sum(hip, mul(P.z, -0.085), mul(P.y, 0.02), mul(latP, 0.01)), mul(P.y, 0.075), mul(latP, 0.06), norm(add(mul(P.z, -1), mul(latP, 0.25))));
      if (set.has('quads')) this.ell('quads', 'thigh' + k, sum(lerp(hip, kn, 0.52), mul(T.ant, 0.062)), mul(T.ax, tl * 0.34), mul(T.lat, 0.045), T.ant);
      if (set.has('hamstrings')) this.ell('hamstrings', 'thigh' + k, sum(lerp(hip, kn, 0.55), mul(T.ant, -0.062)), mul(T.ax, tl * 0.33), mul(T.lat, 0.04), mul(T.ant, -1));
      if (set.has('adductors')) {
        const med = mul(T.lat, s * Math.sign(dot(T.lat, P.x)) * -1);
        this.ell('adductors', 'thigh' + k, sum(lerp(hip, kn, 0.38), mul(med, 0.055)), mul(T.ax, tl * 0.25), mul(T.ant, 0.035), med);
      }
      if (set.has('calves')) this.ell('calves', 'shank' + k, sum(lerp(kn, an, 0.3), mul(Sh.ant, -0.045)), mul(Sh.ax, A.shank * 0.22), mul(norm(cross(Sh.ax, Sh.ant)), 0.03), mul(Sh.ant, -1));
    }
    return this;
  }

  json() {
    return { pts: this.pts, prims: this.prims, mus: this.mus, guides: this.guides };
  }
}
function sum(...v) { return v.reduce((s, x) => add(s, x), [0, 0, 0]); }
function len(a) { return Math.hypot(a[0], a[1], a[2]); }

module.exports = { Scene, COL, PLATE_R };
