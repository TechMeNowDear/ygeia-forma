/// Κατάλογος εξετάσεων (απαίτηση χρήστη 12/11): κάθε εργαστήριο γράφει άλλα ονόματα, άλλες μονάδες και άλλα όρια. Εδώ
/// κάθε εξέταση έχει ένα σταθερό id, ελληνικό όνομα, μία βασική μονάδα, τις μονάδες που δέχεται και όσα ονόματα
/// γράφουν τα εργαστήρια. Η σύγκριση γίνεται ΜΟΝΟ στη βασική μονάδα.
///
/// Μετατροπές: από τα μοριακά βάρη (π.χ. χοληστερόλη 386,65 g/mol → 1 mmol/L = 38,67 mg/dL). Όπου η μετατροπή δεν
/// είναι ασφαλής (Lp(a) mg/dL ↔ nmol/L, ινσουλίνη), δεν γίνεται: μόνο ίδια μονάδα συγκρίνεται.
/// Κωδικοί LOINC και βιολογική διακύμανση (EFLM): μπαίνουν μόνο επαληθευμένοι από την πηγή τους· ως τότε κενοί.
library;

/// Μία μονάδα και πώς γίνεται βασική: βασική = τιμή × [factor] + [offset].
class UnitConv {
  const UnitConv(this.factor, [this.offset = 0]);
  final double factor;
  final double offset;
  double toBase(double v) => v * factor + offset;
  double fromBase(double v) => (v - offset) / factor;
}

enum LabCat { lipids, sugar, kidney, liver, blood, iron, thyroid, vitamins, electrolytes, inflammation, other }

const labCatNames = {
  LabCat.lipids: 'Λιπίδια',
  LabCat.sugar: 'Σάκχαρο',
  LabCat.kidney: 'Νεφροί',
  LabCat.liver: 'Ήπαρ',
  LabCat.blood: 'Γενική αίματος',
  LabCat.iron: 'Σίδηρος',
  LabCat.thyroid: 'Θυρεοειδής',
  LabCat.vitamins: 'Βιταμίνες',
  LabCat.electrolytes: 'Ηλεκτρολύτες',
  LabCat.inflammation: 'Φλεγμονή',
  LabCat.other: 'Άλλες',
};

class LabTest {
  const LabTest({
    required this.id,
    required this.name,
    required this.cat,
    required this.unit,
    this.units = const {},
    this.aliases = const [],
    this.decimals = 0,
    this.loinc,
  });

  final String id;

  /// Ελληνικό όνομα όπως το δείχνει η εφαρμογή.
  final String name;
  final LabCat cat;

  /// Βασική μονάδα (σε αυτήν γίνονται οι συγκρίσεις).
  final String unit;

  /// Άλλες μονάδες που δέχεται (κλειδί όπως το γράφουν τα εργαστήρια, κανονικοποιημένο με [unitKey]).
  final Map<String, UnitConv> units;
  final List<String> aliases;
  final int decimals;

  /// Επαληθευμένος κωδικός LOINC (κενό ως την επαλήθευση).
  final String? loinc;
}

const _chol = {'mmol/l': UnitConv(38.67)};

/// Οι εξετάσεις. Προσθήκη: νέα εγγραφή εδώ + test. Τα ονόματα συγκρίνονται «διπλωμένα» ([foldName]).
const labCatalog = <LabTest>[
  // Λιπίδια
  LabTest(id: 'chol', name: 'Ολική χοληστερίνη', cat: LabCat.lipids, unit: 'mg/dL', units: _chol, aliases: [
    'Χοληστερίνη', 'Χοληστερίνη ολική', 'Ολική χοληστερόλη', 'Χοληστερόλη', 'Χοληστερόλη ολική', 'Cholesterol', 'Total cholesterol',
    'Cholesterol total', 'CHOL', 'TC',
  ]),
  LabTest(id: 'ldl', name: 'LDL χοληστερίνη', cat: LabCat.lipids, unit: 'mg/dL', units: _chol, aliases: [
    'LDL', 'LDL-C', 'LDL χοληστερόλη', 'Χοληστερίνη LDL', 'Χοληστερόλη LDL', 'LDL cholesterol', 'Cholesterol LDL',
    'LDL υπολογιζόμενη', 'LDL (υπολογιζόμενη)', 'LDL calculated', 'LDL direct', 'LDL άμεση', 'Low density lipoprotein',
    'Λιποπρωτεΐνη χαμηλής πυκνότητας', 'Χοληστερόλη χαμηλής πυκνότητας λιποπρωτεϊνών',
  ]),
  LabTest(id: 'hdl', name: 'HDL χοληστερίνη', cat: LabCat.lipids, unit: 'mg/dL', units: _chol, aliases: [
    'HDL', 'HDL-C', 'HDL χοληστερόλη', 'Χοληστερίνη HDL', 'Χοληστερόλη HDL', 'HDL cholesterol', 'Cholesterol HDL',
    'High density lipoprotein', 'Λιποπρωτεΐνη υψηλής πυκνότητας', 'Χοληστερόλη υψηλής πυκνότητας λιποπρωτεϊνών',
  ]),
  LabTest(id: 'nonhdl', name: 'Non-HDL χοληστερίνη', cat: LabCat.lipids, unit: 'mg/dL', units: _chol, aliases: [
    'Non-HDL', 'Non HDL', 'Non-HDL-C', 'Non-HDL cholesterol', 'Μη HDL χοληστερίνη',
  ]),
  LabTest(id: 'tg', name: 'Τριγλυκερίδια', cat: LabCat.lipids, unit: 'mg/dL', units: {'mmol/l': UnitConv(88.57)}, aliases: [
    'Τριγλυκερίδια', 'Triglycerides', 'TRIG', 'TG', 'TRG',
  ]),
  LabTest(id: 'lpa', name: 'Λιποπρωτεΐνη(a)', cat: LabCat.lipids, unit: 'mg/dL', aliases: [
    'Lp(a)', 'Lpa', 'Lipoprotein(a)', 'Lipoprotein a', 'Λιποπρωτεΐνη α', 'Λιποπρωτεΐνη (a)',
  ]),
  LabTest(id: 'apob', name: 'Απολιποπρωτεΐνη B', cat: LabCat.lipids, unit: 'mg/dL', units: {'g/l': UnitConv(100)}, aliases: [
    'ApoB', 'Apo B', 'Apo-B', 'Apolipoprotein B', 'Απολιποπρωτεΐνη Β', 'Απολιποπρωτεΐνη B',
  ]),
  // Σάκχαρο
  LabTest(id: 'glu', name: 'Σάκχαρο (γλυκόζη)', cat: LabCat.sugar, unit: 'mg/dL', units: {'mmol/l': UnitConv(18.016)}, aliases: [
    'Σάκχαρο', 'Γλυκόζη', 'Γλυκόζη νηστείας', 'Σάκχαρο νηστείας', 'Glucose', 'Fasting glucose', 'GLU', 'GLUC',
  ]),
  LabTest(id: 'hba1c', name: 'Γλυκοζυλιωμένη αιμοσφαιρίνη (HbA1c)', cat: LabCat.sugar, unit: '%', decimals: 1, units: {
    // IFCC mmol/mol → NGSP %: % = 0,09148 × mmol/mol + 2,152 (Hoelzel 2004, IFCC-NGSP master equation)
    'mmol/mol': UnitConv(0.09148, 2.152),
  }, aliases: [
    'HbA1c', 'Hb A1c', 'A1c', 'Γλυκοζυλιωμένη αιμοσφαιρίνη', 'Γλυκοζυλιωμένη', 'Glycated hemoglobin', 'Hemoglobin A1c',
  ]),
  LabTest(id: 'insulin', name: 'Ινσουλίνη', cat: LabCat.sugar, unit: 'µIU/mL', decimals: 1, units: {'mu/l': UnitConv(1), 'miu/l': UnitConv(1)},
      aliases: ['Ινσουλίνη', 'Insulin', 'INS']),
  // Νεφροί
  LabTest(id: 'crea', name: 'Κρεατινίνη', cat: LabCat.kidney, unit: 'mg/dL', decimals: 2, units: {'µmol/l': UnitConv(1 / 88.42)},
      aliases: ['Κρεατινίνη', 'Creatinine', 'CREA', 'CREAT', 'CR']),
  LabTest(id: 'egfr', name: 'eGFR (σπειραματική διήθηση)', cat: LabCat.kidney, unit: 'mL/min/1,73m²', units: {
    'ml/min': UnitConv(1),
  }, aliases: [
    'eGFR', 'GFR', 'Ρυθμός σπειραματικής διήθησης', 'Σπειραματική διήθηση', 'eGFR CKD-EPI',
    // Τελικός έλεγχος (Συμβούλιο 3, Λ2): η Βιοϊατρική το γράφει στις «Παρατηρήσεις» της κρεατινίνης, ως «Estimated GFR
    // 2021 CKD-EPI Creatinine». Ολόκληρο το όνομα είναι ΑΛΛΗ εξέταση από την «Creatinine»: ταιριάζει μόνο ολόκληρο.
    'Estimated GFR', 'Estimated GFR CKD-EPI', 'Estimated GFR 2021 CKD-EPI', 'Estimated GFR 2021 CKD-EPI Creatinine',
    'eGFR 2021 CKD-EPI', 'eGFR CKD-EPI 2021', 'eGFR CKD-EPI Creatinine', 'Εκτιμώμενος ρυθμός σπειραματικής διήθησης',
    'Εκτιμώμενη σπειραματική διήθηση',
  ]),
  LabTest(id: 'urea', name: 'Ουρία', cat: LabCat.kidney, unit: 'mg/dL', units: {'mmol/l': UnitConv(6.006)}, aliases: ['Ουρία', 'Urea', 'UREA']),
  LabTest(id: 'uric', name: 'Ουρικό οξύ', cat: LabCat.kidney, unit: 'mg/dL', decimals: 1, units: {'µmol/l': UnitConv(1 / 59.48)},
      aliases: ['Ουρικό οξύ', 'Ουρικό', 'Uric acid', 'UA', 'URIC']),
  // Ήπαρ
  LabTest(id: 'ast', name: 'SGOT (AST)', cat: LabCat.liver, unit: 'U/L', units: {'iu/l': UnitConv(1)}, aliases: [
    'SGOT', 'AST', 'SGOT/AST', 'AST/SGOT', 'Ασπαρτική αμινοτρανσφεράση', 'Aspartate aminotransferase',
  ]),
  LabTest(id: 'alt', name: 'SGPT (ALT)', cat: LabCat.liver, unit: 'U/L', units: {'iu/l': UnitConv(1)}, aliases: [
    'SGPT', 'ALT', 'SGPT/ALT', 'ALT/SGPT', 'Αλανινική αμινοτρανσφεράση', 'Alanine aminotransferase',
  ]),
  LabTest(id: 'ggt', name: 'γ-GT', cat: LabCat.liver, unit: 'U/L', units: {'iu/l': UnitConv(1)}, aliases: [
    'γ-GT', 'γGT', 'GGT', 'Gamma GT', 'γ-γλουταμυλοτρανσφεράση', 'Gamma-glutamyl transferase',
  ]),
  LabTest(id: 'alp', name: 'Αλκαλική φωσφατάση', cat: LabCat.liver, unit: 'U/L', units: {'iu/l': UnitConv(1)},
      aliases: ['Αλκαλική φωσφατάση', 'ALP', 'Alkaline phosphatase']),
  LabTest(id: 'bili', name: 'Χολερυθρίνη ολική', cat: LabCat.liver, unit: 'mg/dL', decimals: 2, units: {'µmol/l': UnitConv(1 / 17.1)},
      aliases: ['Χολερυθρίνη', 'Χολερυθρίνη ολική', 'Ολική χολερυθρίνη', 'Bilirubin', 'Total bilirubin', 'TBIL']),
  LabTest(id: 'alb', name: 'Λευκωματίνη', cat: LabCat.liver, unit: 'g/dL', decimals: 1, units: {'g/l': UnitConv(0.1)},
      aliases: ['Λευκωματίνη', 'Αλβουμίνη', 'Albumin', 'ALB']),
  // Γενική αίματος
  LabTest(id: 'hgb', name: 'Αιμοσφαιρίνη', cat: LabCat.blood, unit: 'g/dL', decimals: 1, units: {'g/l': UnitConv(0.1)},
      aliases: ['Αιμοσφαιρίνη', 'Hemoglobin', 'Haemoglobin', 'HGB', 'Hb']),
  LabTest(id: 'hct', name: 'Αιματοκρίτης', cat: LabCat.blood, unit: '%', decimals: 1, units: {'l/l': UnitConv(100)},
      aliases: ['Αιματοκρίτης', 'Hematocrit', 'Haematocrit', 'HCT', 'Ht']),
  LabTest(id: 'wbc', name: 'Λευκά αιμοσφαίρια', cat: LabCat.blood, unit: '×10³/µL', decimals: 1, units: {
    '10^9/l': UnitConv(1), 'k/µl': UnitConv(1), '10^3/µl': UnitConv(1), '/µl': UnitConv(0.001), '/mm3': UnitConv(0.001),
  }, aliases: ['Λευκά αιμοσφαίρια', 'Λευκά', 'WBC', 'White blood cells', 'Leukocytes']),
  LabTest(id: 'rbc', name: 'Ερυθρά αιμοσφαίρια', cat: LabCat.blood, unit: '×10⁶/µL', decimals: 2, units: {
    '10^12/l': UnitConv(1), 'm/µl': UnitConv(1), '10^6/µl': UnitConv(1),
  }, aliases: ['Ερυθρά αιμοσφαίρια', 'Ερυθρά', 'RBC', 'Red blood cells', 'Erythrocytes']),
  LabTest(id: 'plt', name: 'Αιμοπετάλια', cat: LabCat.blood, unit: '×10³/µL', units: {
    '10^9/l': UnitConv(1), 'k/µl': UnitConv(1), '10^3/µl': UnitConv(1), '/µl': UnitConv(0.001), '/mm3': UnitConv(0.001),
  }, aliases: ['Αιμοπετάλια', 'PLT', 'Platelets', 'Thrombocytes']),
  LabTest(id: 'mcv', name: 'MCV (μέσος όγκος ερυθρών)', cat: LabCat.blood, unit: 'fL', decimals: 1, aliases: ['MCV', 'Μέσος όγκος ερυθρών']),
  // Σίδηρος
  LabTest(id: 'ferritin', name: 'Φερριτίνη', cat: LabCat.iron, unit: 'ng/mL', units: {'µg/l': UnitConv(1)},
      aliases: ['Φερριτίνη', 'Ferritin', 'FERR']),
  LabTest(id: 'iron', name: 'Σίδηρος', cat: LabCat.iron, unit: 'µg/dL', units: {'µmol/l': UnitConv(1 / 0.1791)},
      aliases: ['Σίδηρος', 'Σίδηρος ορού', 'Iron', 'Serum iron', 'Fe']),
  // Θυρεοειδής
  LabTest(id: 'tsh', name: 'TSH', cat: LabCat.thyroid, unit: 'µIU/mL', decimals: 2, units: {'miu/l': UnitConv(1), 'mu/l': UnitConv(1)},
      aliases: ['TSH', 'Θυρεοειδοτρόπος ορμόνη', 'Θυρεοτρόπος ορμόνη', 'Θυρεοτροπίνη', 'Thyroid stimulating hormone']),
  LabTest(id: 'ft4', name: 'FT4 (ελεύθερη θυροξίνη)', cat: LabCat.thyroid, unit: 'ng/dL', decimals: 2, units: {'pmol/l': UnitConv(1 / 12.87)},
      aliases: ['FT4', 'Free T4', 'Ελεύθερη θυροξίνη', 'Ελεύθερη T4']),
  // Βιταμίνες
  LabTest(id: 'vitd', name: 'Βιταμίνη D (25-OH)', cat: LabCat.vitamins, unit: 'ng/mL', decimals: 1, units: {'nmol/l': UnitConv(1 / 2.496)},
      aliases: ['Βιταμίνη D', '25-OH βιταμίνη D', '25(OH)D', '25-OH Vitamin D', 'Vitamin D', 'Vit D', '25-υδροξυβιταμίνη D']),
  LabTest(id: 'b12', name: 'Βιταμίνη B12', cat: LabCat.vitamins, unit: 'pg/mL', units: {'pmol/l': UnitConv(1 / 0.7378)},
      aliases: ['B12', 'Βιταμίνη B12', 'Βιταμίνη Β12', 'Vitamin B12', 'Κοβαλαμίνη', 'Cobalamin']),
  LabTest(id: 'folate', name: 'Φυλλικό οξύ', cat: LabCat.vitamins, unit: 'ng/mL', decimals: 1, units: {'nmol/l': UnitConv(1 / 2.266)},
      aliases: ['Φυλλικό οξύ', 'Φυλλικό', 'Folate', 'Folic acid', 'Serum folate']),
  // Ηλεκτρολύτες
  LabTest(id: 'na', name: 'Νάτριο', cat: LabCat.electrolytes, unit: 'mmol/L', units: {'meq/l': UnitConv(1)}, aliases: ['Νάτριο', 'Sodium', 'Na', 'Na+']),
  LabTest(id: 'k', name: 'Κάλιο', cat: LabCat.electrolytes, unit: 'mmol/L', decimals: 1, units: {'meq/l': UnitConv(1)},
      aliases: ['Κάλιο', 'Potassium', 'K', 'K+']),
  LabTest(id: 'ca', name: 'Ασβέστιο', cat: LabCat.electrolytes, unit: 'mg/dL', decimals: 1, units: {'mmol/l': UnitConv(4.008)},
      aliases: ['Ασβέστιο', 'Calcium', 'Ca', 'Ca ολικό']),
  // Φλεγμονή
  LabTest(id: 'crp', name: 'CRP (C-αντιδρώσα πρωτεΐνη)', cat: LabCat.inflammation, unit: 'mg/L', decimals: 1, units: {'mg/dl': UnitConv(10)},
      aliases: ['CRP', 'C-αντιδρώσα πρωτεΐνη', 'C αντιδρώσα πρωτεΐνη', 'C-reactive protein']),
  LabTest(id: 'hscrp', name: 'hs-CRP', cat: LabCat.inflammation, unit: 'mg/L', decimals: 2, units: {'mg/dl': UnitConv(10)},
      aliases: ['hs-CRP', 'hsCRP', 'CRP υψηλής ευαισθησίας', 'High sensitivity CRP']),
  // Άλλες
  LabTest(id: 'psa', name: 'PSA', cat: LabCat.other, unit: 'ng/mL', decimals: 2, units: {'µg/l': UnitConv(1)},
      aliases: ['PSA', 'Total PSA', 'PSA ολικό', 'Ολικό PSA', 'Προστατικό ειδικό αντιγόνο', 'Ειδικό προστατικό αντιγόνο']),
];

/// Γρήγορη αναζήτηση με id.
final Map<String, LabTest> labById = {for (final t in labCatalog) t.id: t};

const _accents = {
  'ά': 'α', 'έ': 'ε', 'ή': 'η', 'ί': 'ι', 'ό': 'ο', 'ύ': 'υ', 'ώ': 'ω', 'ϊ': 'ι', 'ϋ': 'υ', 'ΐ': 'ι', 'ΰ': 'υ', 'ς': 'σ',
  // Τελικός έλεγχος (Συμβούλιο 3, Λ3): τα ίδια τονισμένα γράμματα στο «πολυτονικό» μπλοκ του Unicode (U+1F71 ά … U+1F7D ώ,
  // U+1FD3 ΐ, U+1FE3 ΰ). Μερικές γραμματοσειρές PDF τα βγάζουν έτσι· πριν χάνονταν ολόκληρα («Γλυκόζη» → «γλυκζη»).
  '\u{1F71}': 'α', '\u{1F73}': 'ε', '\u{1F75}': 'η', '\u{1F77}': 'ι', '\u{1F79}': 'ο', '\u{1F7B}': 'υ', '\u{1F7D}': 'ω', '\u{1FD3}': 'ι',
  '\u{1FE3}': 'υ',
};

/// Ελληνικά γράμματα που μοιάζουν με λατινικά (στα PDF συμβαίνει «ΗDL» με ελληνικό Η ή «Β12» με
/// ελληνικό Β). Διπλώνονται και στις δύο πλευρές, άρα η σύγκριση μένει σωστή.
const _lookalike = {
  'α': 'a', 'β': 'b', 'ε': 'e', 'ζ': 'z', 'η': 'h', 'ι': 'i', 'κ': 'k', 'μ': 'm', 'ν': 'n', 'ο': 'o', 'ρ': 'p', 'τ': 't',
  'υ': 'y', 'χ': 'x', 'µ': 'm',
};

/// Ό,τι μένει στο διπλωμένο όνομα: λατινικά πεζά, ψηφία, ελληνικά (U+0370–U+03FF). Τόνοι που ήρθαν χωριστά από το γράμμα
/// («ο» + U+0301), κενά (και τα «σκληρά», U+00A0), παύλες, παρενθέσεις: φεύγουν.
final _kept = RegExp(r'[a-z0-9Ͱ-Ͽ]');

/// «Διπλωμένο» όνομα: πεζά, χωρίς τόνους, ελληνικά-λατινικά που μοιάζουν ίδια, χωρίς κενά και σημεία.
String foldName(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    var c = _accents[ch] ?? ch;
    c = _lookalike[c] ?? c;
    if (_kept.hasMatch(c)) b.write(c);
  }
  return b.toString();
}

/// Κανονικοποιημένη μονάδα: πεζά, χωρίς κενά, «u»/«μ» → «µ», «×10^9» → «10^9».
/// Τελικός έλεγχος (Συμβούλιο 1, Σ3): «gr» αντί για «g» («gr/dL», «mgr/dl»: έτσι γράφουν ελληνικά εργαστήρια) και οι
/// γραφές του eGFR («1.73m^2», «1,73 m2») γίνονται μία. Πρώτα το «gr/», για να πιάσει μετά και το «ugr/».
String unitKey(String s) {
  var u = s.trim().toLowerCase().replaceAll(' ', '').replaceAll('μ', 'µ').replaceAll('×', '').replaceAll('x10', '10');
  u = u.replaceAll('gr/', 'g/');
  u = u.replaceAll('ug/', 'µg/').replaceAll('umol/', 'µmol/').replaceAll('uiu/', 'µiu/').replaceAll('/ul', '/µl');
  u = u.replaceAll('10⁹', '10^9').replaceAll('10¹²', '10^12').replaceAll('10³', '10^3').replaceAll('10⁶', '10^6');
  u = u.replaceAll('1,73', '1.73').replaceAll('m^2', 'm²').replaceAll('m2', 'm²');
  return u;
}

final Map<String, String> _aliasIndex = () {
  final m = <String, String>{};
  for (final t in labCatalog) {
    for (final a in [t.name, ...t.aliases]) {
      final k = foldName(a);
      assert(m[k] == null || m[k] == t.id, 'Το «$a» ταιριάζει σε δύο εξετάσεις');
      m[k] = t.id;
    }
  }
  return m;
}();

final List<String> _suffixes = [foldName('ορού'), 'serum'];

/// Ως τόσα γράμματα (διπλωμένα) ένα όνομα είναι «σύντομος κωδικός» (TG, Cr, Ca, UA, Fe, K…). Οι σύντομοι κωδικοί δεν
/// είναι μοναδικοί ανάμεσα στις εξετάσεις: «Tg» γράφεται και η θυρεοσφαιρίνη (ng/mL), «Cr» και το χρώμιο.
const shortCodeLength = 3;

/// Ποια εξέταση είναι το όνομα που έγραψε το εργαστήριο. Πρώτα όσα έμαθες εσύ για αυτό το εργαστήριο ([learned]:
/// διπλωμένο όνομα → id), μετά ο κατάλογος. Αν δεν βρεθεί: null (η εφαρμογή ρωτά, δεν μαντεύει).
///
/// [unit] (τελικός έλεγχος, Συμβούλιο 1, Σ3): η μονάδα όπως τη γράφει το εργαστήριο, αν είναι γνωστή. Όταν το όνομα
/// είναι σύντομος κωδικός ([shortCodeLength]) και η εξέταση του καταλόγου ΔΕΝ δέχεται αυτή τη μονάδα, δεν ταιριάζει
/// (null: η εφαρμογή ρωτά). Έτσι «Tg» σε ng/mL (θυρεοσφαιρίνη) δεν γίνεται ποτέ «Τριγλυκερίδια». Ένα ολόκληρο όνομα
/// («Αιμοσφαιρίνη») ταιριάζει και με άγνωστη μονάδα («gr/dL»): τότε ρωτιέται μόνο η μονάδα. Όσα έμαθες εσύ δεν κρίνονται.
///
/// Όνομα με κωδικό στο τέλος (τελικός έλεγχος, Συμβούλιο 3, Λ1): «Γλυκόζη (GLUC)», «Μέσος Όγκος Ερυθρών (ΜCV)»,
/// «25-υδροξυβιταμίνη D [25(ΟΗ)D]». Έτσι γράφει σχεδόν κάθε γραμμή η Βιοϊατρική· πριν αναγνωριζόταν μόνο όποια τύχαινε
/// να είναι γραμμένη ολόιδια στον κατάλογο («Γλυκοζυλιωμένη Αιμοσφαιρίνη (HbA1C)»).
/// Κανόνας, πάντα προς το «η εφαρμογή ρωτά» όταν κάτι δεν δένει ([splitNameCode]):
/// - όνομα ΚΑΙ κωδικός γνωστά: ταιριάζει μόνο αν δείχνουν την ίδια εξέταση («Χοληστερόλη (non-HDL)» → ρωτά)·
/// - όνομα γνωστό, κωδικός άγνωστος: ρωτά («Χοληστερόλη (VLDL)» δεν γίνεται ποτέ «Ολική χοληστερίνη»)·
/// - όνομα άγνωστο, κωδικός γνωστός: με γνωστή μονάδα ταιριάζει μόνο αν η εξέταση τη δέχεται («Θυρεοσφαιρίνη (TG)»
///   σε ng/mL και «Κάθαρση κρεατινίνης (CREA)» σε mL/min → ρωτά)· χωρίς μονάδα, μόνο αν ο κωδικός δεν είναι σύντομος
///   («…λιποπρωτεϊνών (ΗDL-C)»)· ποτέ όταν το όνομα λέει ούρα («Κάλιο ούρων (K)»).
String? matchTest(String rawName, {Map<String, String> learned = const {}, String? unit}) {
  final k = foldName(rawName);
  if (k.isEmpty) return null;
  final l = learned[k];
  if (l != null && labById.containsKey(l)) return l;
  // «Ca++»: έτσι γράφεται το ιονισμένο ασβέστιο (άλλη εξέταση, γύρω στο 1,2 mmol/L) αλλά, σε μερικά εργαστήρια, και το
  // ολικό. Το δίπλωμα σβήνει τα «+», άρα θα γινόταν «Ca» = ολικό ασβέστιο χωρίς ερώτηση. Εδώ η εφαρμογή ρωτά.
  if (rawName.contains('++')) return null;
  final u = unit?.trim() ?? '';
  bool unitFits(String id) => toBase(labById[id]!, 1, u) != null;
  String? checked(String? id, String key) {
    if (id == null || u.isEmpty || key.length > shortCodeLength) return id;
    return unitFits(id) ? id : null;
  }

  /// Ένα διπλωμένο όνομα στον κατάλογο, και χωρίς το «ορού» / «serum» που προσθέτουν συχνά τα εργαστήρια στο τέλος.
  String? lookup(String key) {
    final hit = checked(_aliasIndex[key], key);
    if (hit != null) return hit;
    for (final suffix in _suffixes) {
      if (key.endsWith(suffix) && key.length > suffix.length) {
        final short = key.substring(0, key.length - suffix.length);
        final h = checked(_aliasIndex[short], short);
        if (h != null) return h;
      }
    }
    return null;
  }

  final whole = lookup(k);
  if (whole != null) return whole;

  final parts = splitNameCode(rawName);
  if (parts == null) return null;
  final nameKey = foldName(parts.name), codeKey = foldName(parts.code);
  if (nameKey.isEmpty || codeKey.isEmpty) return null;
  final byName = lookup(nameKey);
  // Ο κωδικός όπως είναι στον κατάλογο, χωρίς έλεγχο μονάδας: εδώ μετρά μόνο αν συμφωνεί με το όνομα.
  final byCode = _aliasIndex[codeKey];
  if (byName != null) return byCode == byName ? byName : null;
  if (byCode == null) return null;
  // Μόνο ο κωδικός είναι γνωστός. Το όνομα μπορεί να λέει άλλη εξέταση με τον ίδιο κωδικό:
  // - δείγμα ούρων («Κάλιο ούρων (K)»): ο κατάλογος έχει μόνο εξετάσεις αίματος·
  // - άλλη μονάδα («Κάθαρση κρεατινίνης (CREA)» σε mL/min): όταν η μονάδα είναι γνωστή, πρέπει να είναι της εξέτασης·
  // - χωρίς μονάδα, ένας σύντομος κωδικός («TG», «K») δεν φτάνει μόνος του.
  if (specimenKind(parts.name) == 'urine') return null;
  if (u.isNotEmpty) return unitFits(byCode) ? byCode : null;
  return codeKey.length > shortCodeLength ? byCode : null;
}

/// Χωρίζει ένα όνομα που τελειώνει με παρένθεση ή αγκύλη στο κυρίως όνομα και σε ό,τι έχει μέσα της: «Γλυκόζη (GLUC)» →
/// («Γλυκόζη», «GLUC»), «25-υδροξυβιταμίνη D [25(ΟΗ)D]» → («25-υδροξυβιταμίνη D», «25(ΟΗ)D»). Μετρά τις φωλιασμένες
/// παρενθέσεις, ώστε να βρει το σωστό ταίρι της τελευταίας. null: δεν τελειώνει έτσι, ή κάποιο από τα δύο μέρη είναι κενό.
({String name, String code})? splitNameCode(String raw) {
  final s = raw.trim();
  if (s.length < 3) return null;
  final close = s[s.length - 1];
  final open = switch (close) { ')' => '(', ']' => '[', _ => null };
  if (open == null) return null;
  var depth = 0;
  for (var i = s.length - 1; i >= 0; i--) {
    final ch = s[i];
    if (ch == close) {
      depth++;
    } else if (ch == open) {
      depth--;
      if (depth == 0) {
        final name = s.substring(0, i).trim();
        final code = s.substring(i + 1, s.length - 1).trim();
        return name.isEmpty || code.isEmpty ? null : (name: name, code: code);
      }
    }
  }
  return null;
}

/// Το είδος του δείγματος όπως το γράφει το εργαστήριο («Είδος δείγματος: Ορός»), σε τρεις ομάδες: «blood» (ορός,
/// πλάσμα, ολικό αίμα), «urine» (ούρα, και 24ώρου), «other» (ό,τι άλλο: κόπρανα, σίελος, ΕΝΥ…). null: δεν γράφτηκε.
/// Τελικός έλεγχος (Συμβούλιο 1, Σ3): ο κατάλογος έχει ΜΟΝΟ εξετάσεις αίματος· «Γλυκόζη», «Κρεατινίνη», «Νάτριο»,
/// «Ουρικό οξύ», «Λευκωματίνη» μετριούνται και στα ούρα, με το ίδιο όνομα και συχνά την ίδια μονάδα.
String? specimenKind(String? raw) {
  if (raw == null) return null;
  final k = foldName(raw);
  if (k.isEmpty) return null;
  bool has(String word) => k.contains(foldName(word));
  // Πρώτα τα ούρα: «λευκωματίνη ούρων» δεν είναι αίμα, ό,τι άλλο κι αν γράφει η γραμμή.
  if (has('ούρα') || has('ούρων') || has('urine') || has('urinary')) return 'urine';
  const blood = ['ορός', 'ορού', 'serum', 'πλάσμα', 'plasma', 'αίμα', 'blood', 'EDTA', 'φλεβικ', 'venous', 'τριχοειδ', 'capillary'];
  if (blood.any(has)) return 'blood';
  // Ό,τι δεν αναγνωρίζεται ΔΕΝ θεωρείται αίμα: καλύτερα μια σύγκριση λιγότερη παρά μια λάθος.
  return 'other';
}

/// Μέθοδος LDL από το όνομα (υπολογισμένη ή άμεση): άλλη μέθοδος = σύγκριση λιγότερο σίγουρη.
String? methodOf(String rawName) {
  final k = foldName(rawName);
  if (k.contains('direct') || k.contains(foldName('άμεση'))) return 'direct';
  if (k.contains('calc') || k.contains(foldName('υπολογ'))) return 'calc';
  return null;
}

/// Η τιμή στη βασική μονάδα, ή null αν η μονάδα είναι άγνωστη (τότε καμία σύγκριση· η εφαρμογή ρωτά).
double? toBase(LabTest t, double value, String unit) {
  final u = unitKey(unit);
  if (u == unitKey(t.unit)) return value;
  final c = t.units[u];
  return c?.toBase(value);
}
