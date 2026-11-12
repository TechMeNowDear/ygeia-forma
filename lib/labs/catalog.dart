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
    'Λιποπρωτεΐνη χαμηλής πυκνότητας',
  ]),
  LabTest(id: 'hdl', name: 'HDL χοληστερίνη', cat: LabCat.lipids, unit: 'mg/dL', units: _chol, aliases: [
    'HDL', 'HDL-C', 'HDL χοληστερόλη', 'Χοληστερίνη HDL', 'Χοληστερόλη HDL', 'HDL cholesterol', 'Cholesterol HDL',
    'High density lipoprotein', 'Λιποπρωτεΐνη υψηλής πυκνότητας',
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
  }, aliases: ['eGFR', 'GFR', 'Ρυθμός σπειραματικής διήθησης', 'Σπειραματική διήθηση', 'eGFR CKD-EPI']),
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
      aliases: ['TSH', 'Θυρεοειδοτρόπος ορμόνη', 'Θυρεοτροπίνη', 'Thyroid stimulating hormone']),
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
      aliases: ['PSA', 'Total PSA', 'PSA ολικό', 'Ολικό PSA', 'Προστατικό ειδικό αντιγόνο']),
];

/// Γρήγορη αναζήτηση με id.
final Map<String, LabTest> labById = {for (final t in labCatalog) t.id: t};

const _accents = {'ά': 'α', 'έ': 'ε', 'ή': 'η', 'ί': 'ι', 'ό': 'ο', 'ύ': 'υ', 'ώ': 'ω', 'ϊ': 'ι', 'ϋ': 'υ', 'ΐ': 'ι', 'ΰ': 'υ', 'ς': 'σ'};

/// Ελληνικά γράμματα που μοιάζουν με λατινικά (στα PDF συμβαίνει «ΗDL» με ελληνικό Η ή «Β12» με
/// ελληνικό Β). Διπλώνονται και στις δύο πλευρές, άρα η σύγκριση μένει σωστή.
const _lookalike = {
  'α': 'a', 'β': 'b', 'ε': 'e', 'ζ': 'z', 'η': 'h', 'ι': 'i', 'κ': 'k', 'μ': 'm', 'ν': 'n', 'ο': 'o', 'ρ': 'p', 'τ': 't',
  'υ': 'y', 'χ': 'x', 'µ': 'm',
};

/// «Διπλωμένο» όνομα: πεζά, χωρίς τόνους, ελληνικά-λατινικά που μοιάζουν ίδια, χωρίς κενά και σημεία.
String foldName(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    var c = _accents[ch] ?? ch;
    c = _lookalike[c] ?? c;
    if (RegExp(r'[a-z0-9Ͱ-Ͽ]').hasMatch(c)) b.write(c);
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
String? matchTest(String rawName, {Map<String, String> learned = const {}, String? unit}) {
  final k = foldName(rawName);
  if (k.isEmpty) return null;
  final l = learned[k];
  if (l != null && labById.containsKey(l)) return l;
  // «Ca++»: έτσι γράφεται το ιονισμένο ασβέστιο (άλλη εξέταση, γύρω στο 1,2 mmol/L) αλλά, σε μερικά εργαστήρια, και το
  // ολικό. Το δίπλωμα σβήνει τα «+», άρα θα γινόταν «Ca» = ολικό ασβέστιο χωρίς ερώτηση. Εδώ η εφαρμογή ρωτά.
  if (rawName.contains('++')) return null;
  final u = unit?.trim() ?? '';
  String? checked(String? id, String key) {
    if (id == null || u.isEmpty || key.length > shortCodeLength) return id;
    return toBase(labById[id]!, 1, u) == null ? null : id;
  }

  final hit = checked(_aliasIndex[k], k);
  if (hit != null) return hit;
  // Συχνή προσθήκη των εργαστηρίων: «ορού» / «serum» στο τέλος.
  for (final suffix in _suffixes) {
    if (k.endsWith(suffix) && k.length > suffix.length) {
      final short = k.substring(0, k.length - suffix.length);
      final h = checked(_aliasIndex[short], short);
      if (h != null) return h;
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
