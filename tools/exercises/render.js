// Ζωγραφική μιας άσκησης σε canvas 2D. Ίδιοι κανόνες με το lib/exercise/ex_painter.dart.
(function (root) {
  'use strict';
  const R = {
    torso: [['hipL', .085], ['hipR', .085], ['belly', .125], ['waist', .115], ['chest', .12], ['shL', .066], ['shR', .066]],
    limbs: [
      ['thigh', 'hip', 'knee', .078, .056], ['shank', 'knee', 'ank', .055, .04], ['foot', 'heel', 'toe', .036, .026],
      ['uarm', 'sh', 'elb', .05, .04], ['farm', 'elb', 'wri', .04, .03], ['hand', 'wri', 'grp', .03, .03],
    ],
  };
  const BODY = ['pelvis', 'hipL', 'hipR', 'waist', 'belly', 'chest', 'shC', 'shL', 'shR', 'neckTop', 'head', 'nose',
    'elbL', 'elbR', 'wriL', 'wriR', 'grpL', 'grpR', 'kneeL', 'kneeR', 'ankL', 'ankR', 'heelL', 'heelR', 'toeL', 'toeR'];
  const HEAD_R = 0.062 * 1.77;

  function points(A, p, n) {
    const t = p * (n - 1), i = Math.min(n - 2, Math.floor(t)), f = t - i;
    const a = A.f[i], b = A.f[i + 1];
    const P = new Array(A.ns + A.nd);
    for (let k = 0; k < A.ns; k++) P[k] = [A.stat[3 * k] / 1000, A.stat[3 * k + 1] / 1000, A.stat[3 * k + 2] / 1000];
    for (let k = 0; k < A.nd; k++) {
      const q = 3 * k;
      P[A.ns + k] = [(a[q] + (b[q] - a[q]) * f) / 1000, (a[q + 1] + (b[q + 1] - a[q + 1]) * f) / 1000, (a[q + 2] + (b[q + 2] - a[q + 2]) * f) / 1000];
    }
    return P;
  }
  function camera(yaw, elev) {
    const y = yaw * Math.PI / 180, e = elev * Math.PI / 180;
    const f = [Math.sin(y) * Math.cos(e), -Math.sin(e), -Math.cos(y) * Math.cos(e)];
    const r = [Math.cos(y), 0, Math.sin(y)];
    const u = [r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0]];
    return { f, r, u };
  }
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

  // Κλίμακα: όλα τα δείγματα χωράνε, ίδια σε όλη την κίνηση.
  function fit(A, n, cam, W, Hc) {
    let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
    const acc = P => { for (let k = 0; k < P.length; k++) { const x = dot(P[k], cam.r), y = dot(P[k], cam.u); if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; } };
    for (let i = 0; i < n; i++) {
      const P = points(A, i / (n - 1), n);
      acc(A.j.map(k => P[k]));
    }
    // ο εξοπλισμός μετράει, αλλά όχι ο τοίχος/το πάτωμα που βγαίνουν έξω
    const P = points(A, 0, n);
    for (const pr of A.prims) if (pr.k !== 'box' || pr.z < 0.4) for (const k of (pr.p || [pr.a, pr.b, pr.c].filter(x => typeof x === 'number'))) acc([P[k]]);
    const pad = 0.16;
    x0 -= pad; x1 += pad; y0 -= 0.05; y1 += pad;
    const s = Math.min(W / (x1 - x0), Hc / (y1 - y0));
    return { s, ox: W / 2 - s * (x0 + x1) / 2, oy: Hc / 2 + s * (y0 + y1) / 2 };
  }

  function draw(ctx, W, Hc, data, ex, p, o) {
    const A = ex.anim, n = data.n, cam = camera(o.yaw, o.elev === undefined ? 8 : o.elev);
    const fitk = o.yaw + ':' + o.elev + ':' + W + 'x' + Hc;
    if (!ex._fit || ex._fitk !== fitk) { ex._fit = fit(A, n, cam, W, Hc); ex._fitk = fitk; }
    const { s, ox, oy } = ex._fit, C = o.colors;
    const P = points(A, p, n);
    const J = {}; BODY.forEach((b, i) => J[b] = P[A.j[i]]);
    const pr = q => [ox + s * dot(q, cam.r), oy - s * dot(q, cam.u)];
    const dep = q => dot(q, cam.f);
    const col = c => C[c] || c;
    ctx.fillStyle = C.stage; ctx.fillRect(0, 0, W, Hc);
    // πάτωμα
    poly(ctx, [[-1.8, 0, -1.8], [1.8, 0, -1.8], [1.8, 0, 1.8], [-1.8, 0, 1.8]].map(pr), C.floor);
    const items = [];
    // σώμα: η μακρινή πλευρά πιο ανοιχτή
    const far = { L: false, R: false };
    const dL = dep(J.hipL) + dep(J.shL), dR = dep(J.hipR) + dep(J.shR);
    if (Math.abs(dL - dR) > 0.06) { if (dL > dR) far.L = true; else far.R = true; }
    const host = {};
    const torsoD = dep(J.chest) * 0.5 + dep(J.belly) * 0.5;
    host.torso = { d: torsoD, fn: () => { hull(ctx, R.torso.map(([k, r]) => [pr(J[k]), r * s]), C.fig, C.stage); } };
    for (const side of ['L', 'R']) {
      for (const [name, a, b, r1, r2] of R.limbs) {
        const pa = J[a + side], pb = J[b + side];
        host[name + side] = { d: (dep(pa) + dep(pb)) / 2, fn: () => capsule(ctx, pr(pa), pr(pb), r1 * s, r2 * s, far[side] ? C.far : C.fig, C.stage) };
      }
    }
    host.neck = { d: dep(J.neckTop), fn: () => capsule(ctx, pr(J.shC), pr(J.neckTop), .05 * s, .045 * s, C.fig) };
    host.head = { d: dep(J.head), fn: () => { circle(ctx, pr(J.head), HEAD_R * s, C.fig, C.stage); } };
    // μύες πάνω στο τμήμα τους
    const mus = {};
    if (o.muscles) for (const m of A.mus) {
      const tone = ex.primary.some(x => x[0] === m.m) ? 'm1' : ex.secondary.some(x => x[0] === m.m) ? 'm2' : null;
      if (!tone) continue;
      (mus[m.h] = mus[m.h] || []).push([m, tone]);
    }
    for (const [h, it] of Object.entries(host)) items.push({ d: it.d, fn: () => { it.fn(); for (const [m, tone] of (mus[h] || [])) muscle(ctx, P, m, pr, cam, s, C[tone], far[h.slice(-1)] && h !== 'torso'); } });
    const figD = dep(J.pelvis);
    for (const q of A.prims) if (!(q.wall && primDepth(q, P, dep) < figD)) items.push({ d: primDepth(q, P, dep) + (q.z || 0), fn: () => prim(ctx, q, P, pr, cam, s, col) });
    items.sort((a, b) => b.d - a.d);
    for (const it of items) it.fn();
    if (o.guides) for (const g of A.guides) guide(ctx, g, P, pr, s, col);
  }

  function primDepth(q, P, dep) {
    if (q.p) return q.p.reduce((a, k) => a + dep(P[k]), 0) / q.p.length;
    if (q.k === 'rod') return (dep(P[q.a]) + dep(P[q.b])) / 2;
    return dep(P[q.c]);
  }
  function prim(ctx, q, P, pr, cam, s, col) {
    if (q.k === 'box') return hull(ctx, q.p.map(k => [pr(P[k]), 0]), col(q.col), true);
    if (q.k === 'rod') return capsule(ctx, pr(P[q.a]), pr(P[q.b]), q.r * s, q.r * s, col(q.col));
    if (q.k === 'ball') return circle(ctx, pr(P[q.c]), q.r * s, col(q.col));
    if (q.k === 'poly') {
      ctx.strokeStyle = col(q.col); ctx.lineWidth = Math.max(1.5, q.w * s); ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      ctx.beginPath(); q.p.forEach((k, i) => { const a = pr(P[k]); i ? ctx.lineTo(a[0], a[1]) : ctx.moveTo(a[0], a[1]); }); ctx.stroke(); return;
    }
    if (q.k === 'disc') {
      const c = P[q.c], nn = norm(sub(P[q.n], c));
      const u = norm(cross(nn, Math.abs(nn[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0])), v = cross(nn, u);
      const pts = [];
      for (let i = 0; i < 24; i++) { const a = i / 24 * Math.PI * 2; pts.push(pr(add(c, add(mul(u, Math.cos(a) * q.r), mul(v, Math.sin(a) * q.r))))); }
      poly(ctx, pts, col(q.col));
      ctx.strokeStyle = col(q.rim); ctx.lineWidth = Math.max(1, 0.012 * s); ctx.stroke();
    }
  }
  function muscle(ctx, P, m, pr, cam, s, color, isFar) {
    const c = P[m.c], u = sub(P[m.u], c), v = sub(P[m.v], c);
    const nn = norm(cross(u, v));
    const facing = -dot(nn, cam.f);
    if (facing < -0.3) return;
    const a = Math.min(1, (facing + 0.3) / 0.4);
    const pts = [];
    for (let i = 0; i < 20; i++) { const t = i / 20 * Math.PI * 2; pts.push(pr(add(c, add(mul(u, Math.cos(t)), mul(v, Math.sin(t)))))); }
    ctx.globalAlpha = a * (isFar ? 0.7 : 1);
    poly(ctx, pts, color);
    ctx.strokeStyle = color; ctx.lineWidth = Math.max(2, 0.014 * s); ctx.lineJoin = 'round'; ctx.stroke();
    ctx.globalAlpha = 1;
  }
  function guide(ctx, g, P, pr, s, col) {
    const a = pr(P[g.a]), b = pr(P[g.b]);
    ctx.strokeStyle = col(g.col); ctx.lineWidth = Math.max(2, 0.008 * s); ctx.setLineDash(g.d ? [8, 7] : []);
    ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke(); ctx.setLineDash([]);
    if (g.l) {
      const at = pr(P[g.c]);
      ctx.font = '600 ' + Math.round(Math.max(13, ctx.canvas.width * 0.026)) + 'px Inter, system-ui, sans-serif';
      ctx.fillStyle = col(g.col); ctx.textAlign = 'left'; ctx.textBaseline = 'bottom';
      const tw = ctx.measureText(g.l).width;
      const fs = Math.round(Math.max(13, ctx.canvas.width * 0.026));
      let x = Math.min(Math.max(6, at[0] - tw / 2), ctx.canvas.width - tw - 6), y = Math.max(fs + 6, at[1]);
      ctx.fillStyle = col('labelbg') === 'labelbg' ? 'rgba(255,255,255,.82)' : col('labelbg'); ctx.fillRect(x - 4, y - fs - 3, tw + 8, fs + 6);
      ctx.fillStyle = col(g.col);
      ctx.fillText(g.l, x, y);
    }
  }

  // ---------------------------------------------------------------- σχήματα 2D
  function poly(ctx, pts, color) { ctx.fillStyle = color; ctx.beginPath(); pts.forEach((p, i) => i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])); ctx.closePath(); ctx.fill(); }
  function circle(ctx, c, r, color, line) { ctx.fillStyle = color; ctx.beginPath(); ctx.arc(c[0], c[1], r, 0, Math.PI * 2); ctx.fill(); if (line) { ctx.strokeStyle = line; ctx.lineWidth = 2.2; ctx.stroke(); } }
  function capsule(ctx, a, b, r1, r2, color, line) {
    const dx = b[0] - a[0], dy = b[1] - a[1], L = Math.hypot(dx, dy);
    ctx.fillStyle = color;
    if (L <= Math.abs(r1 - r2) + 0.5) { circle(ctx, r1 > r2 ? a : b, Math.max(r1, r2), color, line); return; }
    const th = Math.atan2(dy, dx), al = Math.acos((r1 - r2) / L);
    ctx.beginPath(); ctx.arc(a[0], a[1], r1, th + al, th + 2 * Math.PI - al); ctx.arc(b[0], b[1], r2, th - al, th + al); ctx.closePath(); ctx.fill();
    if (line) { ctx.strokeStyle = line; ctx.lineWidth = 2.2; ctx.stroke(); }
  }
  function hull(ctx, circles, color, edge) {
    const pts = [];
    for (const [c, r] of circles) {
      if (r <= 0) { pts.push(c); continue; }
      for (let i = 0; i < 16; i++) { const a = i / 16 * Math.PI * 2; pts.push([c[0] + r * Math.cos(a), c[1] + r * Math.sin(a)]); }
    }
    const h = convex(pts);
    poly(ctx, h, color);
    if (edge) { ctx.strokeStyle = edge === true ? 'rgba(0,0,0,.25)' : edge; ctx.lineWidth = edge === true ? 1 : 1.6; ctx.stroke(); }
  }
  function convex(p) {
    p = p.slice().sort((a, b) => a[0] - b[0] || a[1] - b[1]);
    const cr = (o, a, b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
    const lo = [], up = [];
    for (const q of p) { while (lo.length >= 2 && cr(lo[lo.length - 2], lo[lo.length - 1], q) <= 0) lo.pop(); lo.push(q); }
    for (let i = p.length - 1; i >= 0; i--) { const q = p[i]; while (up.length >= 2 && cr(up[up.length - 2], up[up.length - 1], q) <= 0) up.pop(); up.push(q); }
    up.pop(); lo.pop(); return lo.concat(up);
  }
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
  const mul = (a, k) => [a[0] * k, a[1] * k, a[2] * k];
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const norm = a => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };

  // Ρυθμός: τμήματα [από p, σε p, δευτερόλεπτα, όνομα]. Επιστρέφει p και τμήμα για χρόνο t.
  function phase(tempo, t) {
    const T = tempo.reduce((a, x) => a + x[2], 0); let s = ((t % T) + T) % T;
    for (let i = 0; i < tempo.length; i++) {
      const [a, b, d] = tempo[i];
      if (s < d || i === tempo.length - 1) { const k = Math.min(1, s / d); const e = 0.5 - 0.5 * Math.cos(Math.PI * k); return { p: a + (b - a) * e, i }; }
      s -= d;
    }
  }
  root.ExRender = { draw, phase };
})(typeof window !== 'undefined' ? window : globalThis);
