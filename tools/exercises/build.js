'use strict';
// node tools/exercises/build.js  → assets/exercises/exercises.json (+ tools/exercises/out/preview.html)
const fs = require('fs');
const path = require('path');
const { Scene } = require('./scene');
const EXS = require('./exercises');

const N = 21; // δείγματα της κίνησης (p = 0..1)
const BODY = ['pelvis', 'hipL', 'hipR', 'waist', 'belly', 'chest', 'shC', 'shL', 'shR', 'neckTop', 'head', 'nose',
  'elbL', 'elbR', 'wriL', 'wriR', 'grpL', 'grpR', 'kneeL', 'kneeR', 'ankL', 'ankR', 'heelL', 'heelR', 'toeL', 'toeR'];

function sample(ex) {
  const frames = [];
  for (let i = 0; i < N; i++) {
    const S = new Scene();
    ex.frame(S, i / (N - 1));
    frames.push(S.json());
  }
  // Ίδια δομή σε κάθε δείγμα (ίδια σειρά σχημάτων)
  const f0 = frames[0];
  const names = Object.keys(f0.pts);
  for (const f of frames) {
    const k = Object.keys(f.pts);
    if (k.length !== names.length || k.some((x, i) => x !== names[i])) throw new Error(ex.id + ': διαφορετικά σημεία ανά δείγμα');
    if (f.prims.length !== f0.prims.length || f.mus.length !== f0.mus.length) throw new Error(ex.id + ': διαφορετικά σχήματα ανά δείγμα');
  }
  for (const b of BODY) if (!(b in f0.pts)) throw new Error(ex.id + ': λείπει ' + b);
  const isStatic = n => frames.every(f => f.pts[n].every((v, j) => v === f0.pts[n][j]));
  const stat = names.filter(isStatic), dyn = names.filter(n => !isStatic(n));
  const order = [...stat, ...dyn];
  const idx = Object.fromEntries(order.map((n, i) => [n, i]));
  const mm = v => Math.round(v * 1000);
  const ref = o => {
    const r = {};
    for (const [k, v] of Object.entries(o)) {
      if (k === 'p') r.p = v.map(n => idx[n]);
      else if (['a', 'b', 'c', 'n', 'u', 'v'].includes(k) && typeof v === 'string' && v in idx) r[k] = idx[v];
      else r[k] = v;
    }
    return r;
  };
  // Η προεπιλεγμένη όψη και η κλίμακα υπολογίζονται στην εφαρμογή· εδώ μόνο τα δεδομένα.
  return {
    stat: stat.flatMap(n => f0.pts[n].map(mm)),
    ns: stat.length,
    nd: dyn.length,
    f: frames.map(f => dyn.flatMap(n => f.pts[n].map(mm))),
    j: BODY.map(b => idx[b]),
    prims: f0.prims.map(ref),
    mus: f0.mus.map(ref),
    guides: f0.guides.map(ref),
  };
}

const MNAME = {
  chest: 'Στήθος', frontdelt: 'Μπροστινός ώμος', sidedelt: 'Πλάγιος ώμος', reardelt: 'Πίσω ώμος',
  rotcuff: 'Στροφικό πέταλο', upperback: 'Πάνω πλάτη', lats: 'Πλατύς ραχιαίος', lowback: 'Χαμηλή πλάτη',
  abs: 'Κοιλιακοί', obliques: 'Πλάγιοι κοιλιακοί', biceps: 'Δικέφαλος', triceps: 'Τρικέφαλος',
  forearm: 'Πήχης', brachio: 'Βραχιόνιος και βραχιονοκερκιδικός', glutes: 'Γλουτοί', quads: 'Τετρακέφαλοι',
  hamstrings: 'Οπίσθιοι μηριαίοι', adductors: 'Προσαγωγοί', calves: 'Γάμπες',
};
const mlist = l => (l || []).map(x => { const [id, note] = Array.isArray(x) ? x : [x]; if (!MNAME[id]) throw new Error('μυς ' + id); return [id, MNAME[id], note || '']; });
const GROUPS = ['chest', 'arms', 'abs', 'back', 'shoulders', 'legs'];
// Έλεγχοι κειμένου (round1, S7-04/-06/-07/-17/-20/-23): ό,τι βλέπει ο χρήστης στην εφαρμογή.
function checkTexts(id, t) {
  // Η εφαρμογή διαβάζει ex.tempo.first: άδειος ρυθμός = σφάλμα στην οθόνη της άσκησης (S7-20).
  if (!Array.isArray(t.tempo) || t.tempo.length === 0) throw new Error(id + ': άδειος ρυθμός (tempo)');
  const all = [t.name, t.equip, t.feel, t.caution || '', ...(t.setup || []), ...(t.steps || []), ...(t.mistakes || []), ...(t.tips || []),
    ...(t.cues || []).map((c) => c[0]), ...t.tempo.map((p) => p[3])].join('\n');
  // Αναφορές σε φωτογραφίες/ενότητες που δεν υπάρχουν στην εφαρμογή (S7-07).
  if (/Φ\d\d|\(\d{1,2}(\.\d)?\)/.test(all)) throw new Error(id + ': αναφορά σε φωτογραφία ή ενότητα που δεν υπάρχει στην εφαρμογή');
  // Κανένα προσωπικό στοιχείο υγείας στο δημόσιο αρχείο (S7-04): γενική διατύπωση για όλους.
  if (/ιστορικ|τενοντίτιδ|ώμους σου|ώμων σου|για σένα/i.test(all)) throw new Error(id + ': προσωπική αναφορά στο κείμενο');
  // Η φάση της ανάσας δένεται με την κίνηση, ποτέ «ανάσα» μόνο στο διάλειμμα της επανάληψης (S7-06).
  if (t.tempo.some((p) => p[3] === 'Ανάσα')) throw new Error(id + ': φάση «Ανάσα» χωρίς κίνηση');
  if (!t.tempo.some((p) => /εισπνοή|εκπνοή/.test(p[3]))) throw new Error(id + ': καμία φάση δεν λέει πότε εισπνοή/εκπνοή');
  // Αλτήρες με βιδωτά «αστεράκια»: ο έλεγχος πριν από κάθε σετ (S7-17).
  if (/αλτήρ/i.test(t.equip) && !(t.setup || []).join(' ').includes('αστεράκια')) throw new Error(id + ': λείπει ο έλεγχος για τα αστεράκια');
  // Λάστιχο: ίδια απόσταση κάθε φορά, αλλιώς τα lb δεν συγκρίνονται (S7-23).
  if (t.equip.startsWith('Λάστιχ') && ![...(t.setup || []), ...(t.steps || [])].join(' ').includes('σημάδι')) throw new Error(id + ': λείπει το σημάδι απόστασης για το λάστιχο');
}
// h: το ύψος της φιγούρας σε cm (engine.js, H), όχι κάποιου ανθρώπου.
const out = { v: 1, h: 177, n: N, ex: [] };
const ids = new Set();
for (const ex of EXS) {
  const { frame, ...text } = ex;
  if (ids.has(ex.id)) throw new Error('διπλό ' + ex.id); ids.add(ex.id);
  if (!GROUPS.includes(ex.group)) throw new Error(ex.id + ': ομάδα ' + ex.group);
  if (!process.env.DRAFT) for (const k of ['name', 'equip', 'feel', 'setup', 'steps', 'cues', 'mistakes', 'tips', 'tempo']) if (!text[k]) throw new Error(ex.id + ': λείπει ' + k);
  // Έλεγχος 8/11 (ιατρικό συμβούλιο MED-09): κάθε άσκηση λέει πώς αναπνέεις (όχι κράτημα της ανάσας).
  if (!process.env.DRAFT && !/ανάσα|αναπνο|εκπνοή/i.test([...(text.tips || []), ...(text.cues || []).map((c) => (Array.isArray(c) ? c[0] : c))].join(' ')))
    throw new Error(ex.id + ': λείπει οδηγία για την αναπνοή');
  if (!process.env.DRAFT) checkTexts(ex.id, text);
  for (const c of text.cues || []) for (const i of c[1]) if (i < 0 || i >= text.tempo.length) throw new Error(ex.id + ': φάση ' + i);
  out.ex.push({ ...text, primary: mlist(text.primary), secondary: mlist(text.secondary), anim: sample(ex) });
}
for (const e of out.ex) for (const a of e.alt || []) if (!ids.has(a)) throw new Error(e.id + ': εναλλακτική ' + a);
const dest = path.join(__dirname, '..', '..', 'assets', 'exercises', 'exercises.json');
fs.mkdirSync(path.dirname(dest), { recursive: true });
fs.writeFileSync(dest, JSON.stringify(out));
const outDir = path.join(__dirname, 'out');
fs.mkdirSync(outDir, { recursive: true });
const html = fs.readFileSync(path.join(__dirname, 'preview.html'), 'utf8')
  .replace('/*RENDER*/', () => fs.readFileSync(path.join(__dirname, 'render.js'), 'utf8'))
  .replace('/*DATA*/', () => 'window.DATA=' + JSON.stringify(out) + ';');
fs.writeFileSync(path.join(outDir, 'preview.html'), html);
fs.writeFileSync(path.join(outDir, 'library.html'), fs.readFileSync(path.join(__dirname, 'library.html'), 'utf8')
  .replace('/*RENDER*/', () => fs.readFileSync(path.join(__dirname, 'render.js'), 'utf8'))
  .replace('/*DATA*/', () => 'window.DATA=' + JSON.stringify(out) + ';'));
console.log('ασκήσεις:', out.ex.length, 'μέγεθος:', (fs.statSync(dest).size / 1024).toFixed(0) + ' KB');
