'use strict';
const E = require('./engine');
const { add, sub, mul, norm, lerp, stand, body, anchor, A } = E;
const ARM = A.uarm + A.farm + A.grip;

// Τα χέρια κρέμονται κάθετα από τους ώμους (κρατούν μπάρα ή αλτήρες), στο πλάτος x από το κέντρο.
const hang = (x, pr, pole) => J => {
  const f = (sh, xx) => { const dx = xx - sh[0]; return [xx, sh[1] - Math.sqrt(ARM * ARM - dx * dx) * 0.999, sh[2]]; };
  return { armL: { to: f(J.shL, x), pole: pole || [0, 0, -1], pr }, armR: { to: f(J.shR, -x), pole: pole || [0, 0, -1], pr } };
};

// Μπάρα με τεντωμένα χέρια, που «γλιστράει» πάνω στους μηρούς/τις κνήμες (οι πλάτες τη σπρώχνουν πίσω).
const barOnLegs = x => J => {
  const front = y => { // μπροστινή επιφάνεια του ποδιού στο ύψος y
    const pts = [[J.hipL, 0.075], [J.kneeL, 0.055], [J.ankL, 0.045]];
    for (let i = 0; i < 2; i++) {
      const [a, ra] = pts[i], [b, rb] = pts[i + 1];
      if ((y <= a[1] && y >= b[1]) || i === 1) { const t = Math.min(1, Math.max(0, (a[1] - y) / (a[1] - b[1]))); return lerp(a, b, t)[2] + ra + (rb - ra) * t; }
    }
  };
  const sh = J.shL;
  const at = phi => { const dx = x - sh[0], r = Math.sqrt(ARM * ARM - dx * dx) * 0.999; return [x, sh[1] - r * Math.cos(phi * E.D), sh[2] - r * Math.sin(phi * E.D)]; };
  let phi = E.solve(f => at(f)[2] - (front(at(f)[1]) + 0.016), -25, 40);
  if (at(phi)[2] < front(at(phi)[1])) phi = 0;
  const tL = at(phi), tR = [-tL[0], tL[1], tL[2]];
  return { armL: { to: tL, pole: [0, 0, -1], pr: 90 }, armR: { to: tR, pole: [0, 0, -1], pr: 90 } };
};

const rdl = {
  id: 'rdl', name: 'Romanian deadlift', en: 'romanian deadlift rdl', group: 'legs', equip: 'Μπάρα', yaw: 90,
  tempo: [[0, 1, 2.6, 'Κάτω, εισπνοή'], [1, 1, 0.4, 'Κάτω'], [1, 0, 1.4, 'Πάνω, εκπνοή'], [0, 0, 0.8, 'Πάνω']],
  primary: [['hamstrings'], ['glutes']], secondary: [['lowback'], ['forearm'], ['adductors']],
  frame(S, p) {
    const B = stand({
      knee: 14 + 8 * p, pitch: 3 + 66 * p, w: 0.24, toe: 6,
      arms: barOnLegs(0.215),
      loads: J => [[lerp(J.grpL, J.grpR, 0.5), 20]],
    });
    S.body(B);
    S.barbell(B.J.grpL, B.J.grpR, [5]);
    S.muscles(['hamstrings', 'glutes', 'lowback', 'forearm', 'adductors']);
    const mid = B.feet.R.mid;
    S.guide([mid[0], 0, mid[2]], [mid[0], 1.45, mid[2]], 'acc', 'μπάρα πάνω από τη μέση του πέλματος', [mid[0], 1.62, mid[2] + 0.15], true);
    const bz = mul(B.F.chest.z, -0.16);
    S.guide(add(B.J.pelvis, bz), add(B.J.shC, bz), 'good', 'πλάτη ίσια', add(lerp(B.J.pelvis, B.J.shC, 0.5), mul(B.F.chest.z, -0.32)));
  },
};

const goblet = {
  id: 'goblet', name: 'Goblet squat', en: 'goblet squat kettlebell squat', group: 'legs', equip: 'Kettlebell', yaw: 90,
  tempo: [[0, 1, 2.4, 'Κάτω, εισπνοή'], [1, 1, 0.5, 'Κάτω'], [1, 0, 1.5, 'Πάνω, εκπνοή'], [0, 0, 0.8, 'Πάνω']],
  primary: [['quads'], ['glutes']], secondary: [['adductors'], ['abs'], ['upperback']],
  frame(S, p) {
    const B = stand({
      knee: 6 + 112 * p, pitch: 5 + 32 * p, w: 0.38, toe: 18, neck: -6 * p,
      arms: (J, F) => {
        const g = add(add(J.chest, mul(F.chest.z, 0.2)), mul(F.chest.y, -0.02));
        return {
          armL: { to: add(g, [0.055, 0, 0]), pole: [0.25, -1, -0.1], pr: 0 },
          armR: { to: add(g, [-0.055, 0, 0]), pole: [-0.25, -1, -0.1], pr: 0 },
        };
      },
      loads: J => [[add(lerp(J.grpL, J.grpR, 0.5), [0, -0.1, 0.01]), 12]],
    });
    S.body(B);
    const g = lerp(B.J.grpL, B.J.grpR, 0.5);
    S.kettlebell(add(g, [0, -0.11, 0.01]), [0, 1, 0], [1, 0, 0], 12);
    S.muscles(['quads', 'glutes', 'adductors', 'abs', 'upperback']);
    const bz = mul(B.F.chest.z, -0.17);
    S.guide(add(B.J.pelvis, bz), add(B.J.shC, bz), 'good', 'στήθος ψηλά, πλάτη ίσια', add(B.J.shC, add(mul(B.F.chest.z, -0.3), [0, 0.25, 0])));
  },
};

module.exports = [goblet, rdl];
module.exports.hang = hang;

// ---------------------------------------------------------------- υπόλοιπα πόδια
const { feetBeside, ARM: ARM2 } = require('./poses');
const solve = E.solve;

const splitSquat = {
  id: 'split_squat', name: 'Split squat με αλτήρες', en: 'split squat lunge dumbbells', group: 'legs', equip: 'Αλτήρες', yaw: -90, yaw2: -25,
  tempo: [[0, 1, 2.2, 'Κάτω, εισπνοή'], [1, 1, 0.3, 'Κάτω'], [1, 0, 1.4, 'Πάνω, εκπνοή'], [0, 0, 0.7, 'Πάνω']],
  frame(S, p) {
    const fF = E.footFlat(0.11, 0.42, 4);
    const toeR = [-0.11, 0.012, -0.5];
    const make = y => {
      const P = [0, y, -0.03];
      const base = { P, pitch: 6, neck: 0 };
      const B0 = body(base);
      const hipR = B0.J.hipR;
      const g = 50 + 22 * p;
      const fr = E.footToes(toeR[0], toeR[2], g);
      base.legL = { to: fF.an, pole: [0, 0.2, 1], heel: fF.heel, toe: fF.toe };
      base.legR = { to: fr.an, pole: [0, -0.6, 1], heel: fr.heel, toe: fr.toe };
      Object.assign(base, hang(0.215, 0)(B0.J));
      return body(base);
    };
    const yTop = 0.9, yBot = solve(y => make(y).J.kneeR[1] - 0.09, 0.45, 0.95);
    const B = make(yTop + (yBot - yTop) * p);
    S.body(B);
    S.dumbbell(B.J.grpL, B.F.farmL.ant, [2.5]); S.dumbbell(B.J.grpR, B.F.farmR.ant, [2.5]);
    S.muscles(['quads', 'glutes', 'adductors']);
    S.guide(add(B.J.pelvis, [0, -0.1, -0.25]), add(B.J.pelvis, [0, 0.35, -0.25]), 'acc', 'κάτω κάθετα', add(B.J.pelvis, [0, -0.25, -0.3]), true);
  },
};

const legCurl = {
  id: 'leg_curl', name: 'Leg curl στον πάγκο', en: 'lying leg curl hamstring curl machine', group: 'legs', equip: 'Πάγκος, μονάδα ποδιών', yaw: 90, yaw2: 150, elev2: 20,
  tempo: [[0, 1, 1.2, 'Λύγισε'], [1, 1, 0.5, 'Σφίξε'], [1, 0, 2.4, 'Κάτω, εισπνοή'], [0, 0, 0.4, 'Κάτω']],
  frame(S, p) {
    S.bench();
    const knee = 4 + 108 * p;
    const base = { P: [0, S.padTop + 0.095, -0.08], yaw: 180, pitch: 90, neck: -18,
      legL: { hip: -4, knee, ank: 8 }, legR: { hip: -4, knee, ank: 8 } };
    let B = body(base);
    const sh = B.J.shC;
    base.armL = { to: [-0.17, S.padTop - 0.06, sh[2] - 0.2], pole: [-1, 0.3, 0] };
    base.armR = { to: [0.17, S.padTop - 0.06, sh[2] - 0.2], pole: [1, 0.3, 0] };
    B = body(base);
    S.body(B);
    const k0 = body({ ...base, legL: { hip: -4, knee: 4, ank: 8 }, legR: { hip: -4, knee: 4, ank: 8 } }).J;
    const pivot = [0, (k0.kneeL[1] + k0.kneeR[1]) / 2, k0.kneeL[2]];
    const an = lerp(B.J.ankL, B.J.ankR, 0.5);
    const post = mul(B.F.shankL.ant, -1);
    S.lever(pivot, add([0, an[1], an[2]], mul(post, 0.07)), [2.5, 2.5]);
    S.muscles(['hamstrings', 'calves']);
  },
};

const legExt = {
  id: 'leg_ext', name: 'Leg extension', en: 'leg extension quad machine', group: 'legs', equip: 'Πάγκος, μονάδα ποδιών', yaw: 90, yaw2: 30,
  tempo: [[0, 1, 1.2, 'Τέντωσε'], [1, 1, 0.6, 'Σφίξε'], [1, 0, 2.4, 'Κάτω, εισπνοή'], [0, 0, 0.4, 'Κάτω']],
  frame(S, p) {
    S.bench({ back: 80, seat: 0, seatLen: 0.4 });
    const knee = 92 - 88 * p;
    const base = { P: [0, S.padTop + 0.09, -0.02], pitch: -12, neck: 4,
      // round1, S7-16: μηροί οριζόντιοι πάνω στο κάθισμα (πριν 92°: ανέβαιναν 14° και το γόνατο «αιωρούνταν»).
      legL: { hip: 78, knee, ank: 4 }, legR: { hip: 78, knee, ank: 4 } };
    let B = body(base);
    // ο κορμός ακουμπά στην πλάτη του πάγκου
    const back3 = add(B.J.chest, mul(B.F.chest.z, -0.12));
    const d = E.dot(sub(S.backAt(0.3), back3), S.backN);
    base.P = add(base.P, [0, 0, S.backN[2] * d]);
    B = body(base);
    base.armL = { to: [0.2, S.padTop + 0.0, B.J.pelvis[2] + 0.12], pole: [1, 0, -0.3] };
    base.armR = { to: [-0.2, S.padTop + 0.0, B.J.pelvis[2] + 0.12], pole: [-1, 0, -0.3] };
    B = body(base);
    S.body(B);
    const k0 = body({ ...base, legL: { hip: 78, knee: 92, ank: 4 }, legR: { hip: 78, knee: 92, ank: 4 } }).J;
    const pivot = [0, k0.kneeL[1], k0.kneeL[2]];
    const an = lerp(B.J.ankL, B.J.ankR, 0.5);
    const front = B.F.shankL.ant;
    S.lever(pivot, add([0, an[1], an[2]], add(mul(front, 0.065), mul(norm(sub(B.J.kneeL, B.J.ankL)), 0.06))), [2.5, 2.5]);
    S.muscles(['quads']);
  },
};

const hipThrust = {
  id: 'hip_thrust', name: 'Hip thrust στον πάγκο', en: 'hip thrust glute bridge bench', group: 'legs', equip: 'Πάγκος, αλτήρας', yaw: 90, yaw2: 30, elev2: 18,
  tempo: [[0, 1, 1.2, 'Πάνω'], [1, 1, 1.0, 'Σφίξε'], [1, 0, 2.0, 'Κάτω, εισπνοή'], [0, 0, 0.4, 'Κάτω']],
  frame(S, p) {
    S.bench({ rot: 90, at: [0.27, 0, -0.62], unit: false });
    const edge = [0, S.padTop - 0.015, -0.62 + 0.14];
    const pose = (g, neck) => ({ P: [0, 1, 0], pitch: -90 + g, neck });
    const contact = B => add(add(B.J.shC, mul(B.F.chest.z, -0.115)), mul(B.F.chest.y, -0.07));
    const topB = body(pose(0, 22));
    E.shift(topB, sub(edge, contact(topB)));
    // πέλματα: στην πάνω θέση κνήμη κάθετη, γόνατο ~90°
    const kz = topB.J.hipL[2] + A.thigh * 0.97;
    const fL = E.footFlat(0.17, kz + 0.02, 10), fR = E.footFlat(-0.17, kz + 0.02, -10);
    const g = 38 * (1 - p);
    const base = pose(g, 22 * p);
    let B = body(base);
    E.shift(B, sub(edge, contact(B)));
    base.P = B.J.pelvis;
    base.legL = { to: fL.an, pole: [0.2, 1, 0.3], heel: fL.heel, toe: fL.toe };
    base.legR = { to: fR.an, pole: [-0.2, 1, 0.3], heel: fR.heel, toe: fR.toe };
    B = body(base);
    const db = add(B.J.pelvis, mul(B.F.pelvis.z, 0.15));
    base.armL = { to: add(db, [0.11, 0, 0]), pole: [1, 0.3, -0.5] };
    base.armR = { to: add(db, [-0.11, 0, 0]), pole: [-1, 0.3, -0.5] };
    B = body(base);
    S.body(B);
    S.dumbbell(db, [1, 0, 0], [5, 2.5]);
    S.muscles(['glutes', 'hamstrings', 'quads']);
    const hz = B.J.pelvis[1];
    S.guide(add(B.J.shC, [0.0, 0.22, -0.05]), add(B.J.kneeR, [0, 0.22, 0]), 'good', 'πάνω: ώμοι-λεκάνη-γόνατα σε ευθεία', add(B.J.pelvis, [0, 0.45, 0]));
  },
};

module.exports.push(splitSquat, legCurl, legExt, hipThrust);

const BREATH = 'Ανάσα σε κάθε επανάληψη: εκπνοή στην άνοδο, εισπνοή στο κατέβασμα. Μην κρατάς καθόλου την αναπνοή· ανεβάζει απότομα την πίεση.';
Object.assign(goblet, {
  primary: ['quads', 'glutes'], secondary: ['adductors', ['abs', 'κρατούν τον κορμό όρθιο'], ['upperback', 'κρατά το στήθος ψηλά']],
  feel: 'Μπροστά στους μηρούς και στους γλουτούς, κυρίως στην άνοδο. Πόνος στο γόνατο σημαίνει λιγότερο βάθος.',
  setup: [
    'Kettlebell από τα «κέρατα» της λαβής, κολλητά στο στήθος.',
    'Πόδια λίγο πιο ανοιχτά από τους ώμους, μύτες λίγο προς τα έξω.',
  ],
  steps: [
    'Στήθος ψηλά, αγκώνες κάτω.',
    'Κάθισε ανάμεσα στα πόδια: η λεκάνη πάει κάτω και πίσω μαζί, τα γόνατα προς τη μεριά των μυτών.',
    'Κατέβα όσο οι φτέρνες μένουν κάτω και η πλάτη ίσια. Ανέβα σπρώχνοντας με όλο το πέλμα.',
  ],
  cues: [
    ['Kettlebell κολλητά στο στήθος, αγκώνες κάτω.', [0, 1, 2, 3]],
    ['Γόνατα προς τη μεριά των μυτών. Μπορούν να περάσουν τις μύτες.', [0, 1]],
    ['Φτέρνες κάτω, στήθος ψηλά.', [1]],
    ['Ανέβα σπρώχνοντας όλο το πέλμα.', [2]],
  ],
  mistakes: [
    'Γόνατα που «κλείνουν» προς τα μέσα, κυρίως στην άνοδο.',
    'Φτέρνες που σηκώνονται από το πάτωμα.',
    'Στήθος που πέφτει μπροστά και καμπούρα στη μέση.',
    'Το kettlebell απομακρύνεται από το στήθος.',
  ],
  tips: [
    'Είναι φυσιολογικό τα γόνατα να περνούν τις μύτες. Αν τα κρατάς επίτηδες πίσω, φορτώνεται περισσότερο η μέση (Fry 2003).',
    'Βάθος: όσο μένει ίσια η πλάτη. Για τους περισσότερους, οι μηροί φτάνουν λίγο κάτω από το παράλληλο.',
    'Μετά τα 12 kg το επόμενο kettlebell είναι 16 kg. Ως τότε ανεβαίνουν οι επαναλήψεις ή γίνεται πιο αργό το κατέβασμα.',
    BREATH,
  ],
  alt: ['split_squat', 'leg_ext'],
});
Object.assign(rdl, {
  primary: ['hamstrings', 'glutes'], secondary: [['lowback', 'κρατά την πλάτη ίσια· δεν πρέπει να πονά'], ['forearm', 'κράτημα της μπάρας'], 'adductors'],
  feel: 'Στο κάτω σημείο νιώθεις τέντωμα πίσω στους μηρούς. Αν το νιώθεις κυρίως στη μέση, μικραίνει το βάθος.',
  setup: [
    'Ξεκίνα με σκέτη τη μπάρα (10 kg)· δίσκοι μπαίνουν αργότερα, όπως προτείνει η εφαρμογή. Με δίσκους, σφιχτά αστεράκια.',
    'Οι βάσεις καθισμάτων στο ύψος των μηρών: παίρνεις τη μπάρα από εκεί, όχι από το πάτωμα.',
    'Ιμάντες ανύψωσης αν γλιστράει η λαβή.',
  ],
  steps: [
    'Όρθιος, πόδια στο πλάτος της λεκάνης, λαβή λίγο έξω από τους μηρούς, γόνατα ελαφρά λυγισμένα.',
    'Σπρώξε τη λεκάνη πίσω. Η μπάρα γλιστράει κολλητά στους μηρούς ως λίγο κάτω από τα γόνατα.',
    'Ανέβα σπρώχνοντας τη λεκάνη μπροστά και σφίγγοντας τους γλουτούς.',
  ],
  cues: [
    ['Γόνατα λίγο λυγισμένα και σταθερά.', [0, 1, 2, 3]],
    ['Λεκάνη πίσω, πλάτη ίσια.', [0]],
    ['Η μπάρα κολλητά στα πόδια, πάνω από τη μέση του πέλματος.', [0, 2]],
    ['Σταμάτα λίγο κάτω από τα γόνατα, όσο η πλάτη μένει ίσια.', [1]],
    ['Πάνω: σφίξε γλουτούς, χωρίς να γέρνεις πίσω.', [3]],
  ],
  mistakes: [
    'Καμπούρα στη μέση. Είναι το σημαντικότερο λάθος.',
    'Τα γόνατα λυγίζουν πολύ και η κίνηση γίνεται κάθισμα.',
    'Η μπάρα φεύγει μπροστά, μακριά από τα πόδια.',
    'Κλίση προς τα πίσω στο πάνω σημείο.',
  ],
  tips: [
    'Το βάθος το ορίζουν η ίσια πλάτη και το τέντωμα πίσω στους μηρούς, όχι το πάτωμα.',
    'Οι βάσεις δεν έχουν βραχίονες ασφαλείας: κράτα 2–3 επαναλήψεις ρεζέρβα.',
    'Στο τέλος του σετ άφησε τη μπάρα στις βάσεις, όχι στο πάτωμα από ψηλά.',
    BREATH,
  ],
  alt: ['hip_thrust', 'leg_curl'],
});
Object.assign(splitSquat, {
  primary: ['quads', 'glutes'], secondary: ['adductors'],
  feel: 'Μπροστά στον μηρό και στον γλουτό του μπροστινού ποδιού. Τέντωμα μπροστά στο ισχίο του πίσω ποδιού.',
  setup: [
    'Δύο αλτήρες, ή χωρίς βάρος τις πρώτες φορές.',
    'Μεγάλο βήμα: το μπροστινό πέλμα ολόκληρο κάτω, το πίσω στις μύτες.',
    'Τα πόδια σαν σε δύο ράγες, όχι σε σκοινί. Χοντρό πατάκι κάτω από το πίσω γόνατο.',
    'Σφίξε τα αστεράκια των αλτήρων πριν από κάθε σετ.',
  ],
  steps: [
    'Κορμός όρθιος, αλτήρες στο πλάι.',
    'Κατέβα κάθετα ώσπου το πίσω γόνατο να φτάσει λίγο πάνω από το πάτωμα.',
    'Ανέβα σπρώχνοντας με το μπροστινό πόδι. Μετά το σετ, άλλαξε πόδι.',
  ],
  cues: [
    ['Κάτω κάθετα, σαν ασανσέρ.', [0]],
    ['Το βάρος στο μπροστινό πέλμα, ολόκληρο κάτω.', [0, 1, 2]],
    ['Το πίσω γόνατο σταματά λίγο πάνω από το πάτωμα.', [1]],
  ],
  mistakes: [
    'Πόδια στην ίδια γραμμή: χάνεται η ισορροπία.',
    'Το μπροστινό γόνατο γέρνει προς τα μέσα.',
    'Σπρώξιμο με το πίσω πόδι αντί για το μπροστινό.',
    'Χτύπημα του γονάτου στο πάτωμα.',
  ],
  tips: [
    'Κάθε πόδι δουλεύει μόνο του, οπότε φαίνονται και διορθώνονται οι διαφορές ανάμεσα στα δύο.',
    'Για ισορροπία στην αρχή, κράτα με το ένα χέρι μια σταθερή βάση.',
    BREATH,
  ],
  alt: ['goblet'],
});
Object.assign(legCurl, {
  primary: ['hamstrings'], secondary: [['calves', 'γαστροκνήμιος']],
  feel: 'Πίσω στους μηρούς, λίγο και στις γάμπες.',
  setup: [
    'Φόρτωσε το κέρατο: δίσκοι ως τον κόκκινο δίσκο-στοπ και το μικρό κλιπ.',
    'Πλάτη και κάθισμα επίπεδα. Ξάπλωσε μπρούμυτα, με το κεφάλι προς την πλάτη του πάγκου και τα γόνατα λίγο έξω από το κάθισμα.',
    'Ποιο ζευγάρι ρολά βολεύει θα το δοκιμάσεις πρώτα χωρίς βάρος.',
  ],
  steps: [
    'Φτέρνες κάτω από τα ρολά, χέρια στον πάγκο μπροστά.',
    'Λύγισε τα γόνατα και φέρε τις φτέρνες προς τους γλουτούς.',
    'Κατέβασε αργά ώσπου τα πόδια να τεντώσουν σχεδόν.',
  ],
  cues: [
    ['Η λεκάνη μένει κολλητά στον πάγκο.', [0, 1]],
    ['Σφίξε 1 δευτερόλεπτο στο πάνω σημείο.', [1]],
    ['Κατέβασμα σε 2–3 δευτερόλεπτα.', [2]],
  ],
  mistakes: [
    'Η λεκάνη σηκώνεται για να βοηθήσει.',
    'Τίναγμα του βάρους.',
    'Μισό κατέβασμα.',
  ],
  tips: [
    BREATH,
    'Σε μηχάνημα δεν σε πλακώνει το βάρος, αλλά κράτα κι εδώ 2 επαναλήψεις ρεζέρβα: η αποτυχία ανεβάζει απότομα την πίεση.',
    'Συμπληρώνει το Romanian deadlift: εκεί οι οπίσθιοι δουλεύουν από το ισχίο, εδώ από το γόνατο.',
  ],
  alt: ['rdl'],
});
Object.assign(legExt, {
  primary: ['quads'], secondary: [],
  feel: 'Μπροστά στους μηρούς, πάνω από το γόνατο.',
  setup: [
    'Φόρτωσε το κέρατο. Πλάτη του πάγκου όρθια ή σε ψηλή κλίση.',
    'Κάθισε με τα γόνατα στην άκρη του καθίσματος, ώστε ο άξονας του μοχλού να είναι στο ύψος των γονάτων.',
    'Κνήμες πίσω από τα κάτω ρολά, λίγο πάνω από τους αστραγάλους.',
  ],
  steps: [
    'Κράτα το κάθισμα στο πλάι.',
    'Τέντωσε τα πόδια ως σχεδόν ίσια.',
    'Κατέβασε αργά.',
  ],
  cues: [
    ['Η πλάτη μένει στο μαξιλάρι.', [0, 1, 2]],
    ['Σφίξε 1 δευτερόλεπτο πάνω.', [1]],
    ['Κατέβασε αργά, χωρίς να «πέσουν» οι δίσκοι.', [2]],
  ],
  mistakes: [
    'Τίναγμα στην αρχή της κίνησης.',
    'Γλουτοί που σηκώνονται από το κάθισμα.',
    'Ο άξονας του μοχλού μακριά από το γόνατο: πιέζει την άρθρωση.',
  ],
  tips: [
    BREATH,
    'Δουλεύει τον τετρακέφαλο μόνο του, χωρίς φορτίο στη μέση. Κράτα κι εδώ 2 επαναλήψεις ρεζέρβα, όχι ως την αποτυχία.',
    'Αν πονάει μπροστά στο γόνατο: μικρότερο εύρος και λιγότερο βάρος.',
  ],
  alt: ['goblet'],
});
Object.assign(hipThrust, {
  primary: ['glutes'], secondary: ['hamstrings', 'quads'],
  feel: 'Στους γλουτούς, κυρίως στο πάνω σημείο. Όχι στη μέση.',
  setup: [
    'Πάγκος επίπεδος, κάθετα πίσω σου, κόντρα σε κάτι για να μη γλιστράει.',
    'Κάθισε στο πάτωμα με την πλάτη στο πλάι του πάγκου, με την άκρη του μαξιλαριού κάτω από τις ωμοπλάτες.',
    'Ένας αλτήρας οριζόντια πάνω στους γοφούς, κρατημένος με τα δύο χέρια, με σφιχτά αστεράκια. Αργότερα, μπάρα με το μαξιλάρι αυχένα.',
  ],
  steps: [
    'Πέλματα στο πάτωμα, στο πλάτος της λεκάνης.',
    'Σπρώξε με τις φτέρνες και σήκωσε τη λεκάνη ώσπου ώμοι, λεκάνη και γόνατα να γίνουν ευθεία.',
    'Κατέβα αργά.',
  ],
  cues: [
    ['Σπρώξε με τις φτέρνες.', [0]],
    ['Πάνω: κνήμες κάθετες, πηγούνι μέσα, σφίξε γλουτούς 1 δευτερόλεπτο.', [1]],
    ['Η μέση δεν καμπυλώνει στο πάνω σημείο.', [1]],
  ],
  mistakes: [
    'Η μέση καμπυλώνει πάνω και η κοιλιά «φουσκώνει» προς το ταβάνι.',
    'Πέλματα πολύ μακριά (δουλεύουν οι οπίσθιοι) ή πολύ κοντά (δουλεύουν οι τετρακέφαλοι).',
    'Κεφάλι γερμένο πίσω.',
  ],
  tips: [
    'Από τις καλύτερες ασκήσεις για γλουτούς, χωρίς φορτίο στη μέση.',
    BREATH,
  ],
  alt: ['rdl'],
});
