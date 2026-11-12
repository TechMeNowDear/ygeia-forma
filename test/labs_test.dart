// Κατάλογος εξετάσεων (12/11): ονόματα, μονάδες, όρια.
// ΟΛΕΣ οι τιμές και οι ημερομηνίες εδώ είναι φανταστικές, στρογγυλές (δημόσιο repo): ποτέ πραγματικά αποτελέσματα.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/labs/catalog.dart';
import 'package:ygeia_forma/labs/lab_number.dart';
import 'package:ygeia_forma/labs/lab_result.dart';

void main() {
  group('ονόματα εργαστηρίων', () {
    test('κάθε εργαστήριο, ίδια εξέταση', () {
      for (final (raw, id) in [
        ('LDL', 'ldl'),
        ('LDL-C', 'ldl'),
        ('Χοληστερίνη LDL', 'ldl'),
        ('LDL χοληστερόλη', 'ldl'),
        ('ldl cholesterol', 'ldl'),
        ('LDL (υπολογιζόμενη)', 'ldl'),
        ('ΗDL', 'hdl'), // ελληνικό Η
        ('Ολική Χοληστερόλη', 'chol'),
        ('CHOL', 'chol'),
        ('Τριγλυκερίδια ορού', 'tg'),
        ('Σάκχαρο', 'glu'),
        ('Γλυκόζη νηστείας', 'glu'),
        ('HbA1c', 'hba1c'),
        ('SGOT', 'ast'),
        ('S.G.O.T.', 'ast'),
        ('γ-GT', 'ggt'),
        ('Βιταμίνη Β12', 'b12'), // ελληνικό Β
        ('25-OH Vitamin D', 'vitd'),
        ('Φυλλικό Οξύ', 'folate'),
        ('TSH', 'tsh'),
        ('Κάλιο', 'k'),
        ('K', 'k'),
        ('K+', 'k'),
        ('Na+', 'na'),
        ('PSA ολικό', 'psa'),
      ]) {
        expect(matchTest(raw), id, reason: raw);
      }
    });

    test('άγνωστο όνομα: null, όχι εικασία· μετά μαθαίνει για το εργαστήριο', () {
      expect(matchTest('Χοληστερόλη χαμηλής πυκνότητας'), isNull);
      final learned = {foldName('Χοληστερόλη χαμηλής πυκνότητας'): 'ldl'};
      expect(matchTest('Χοληστερόλη χαμηλής πυκνότητας', learned: learned), 'ldl');
      expect(matchTest('   '), isNull);
    });

    test('κανένα όνομα δεν ταιριάζει σε δύο εξετάσεις', () {
      final seen = <String, String>{};
      for (final t in labCatalog) {
        for (final a in [t.name, ...t.aliases]) {
          final k = foldName(a);
          expect(seen[k] == null || seen[k] == t.id, isTrue, reason: '$a: ${seen[k]} και ${t.id}');
          seen[k] = t.id;
        }
      }
      expect(labCatalog.map((t) => t.id).toSet().length, labCatalog.length);
    });

    test('μέθοδος LDL από το όνομα', () {
      expect(methodOf('LDL direct'), 'direct');
      expect(methodOf('LDL άμεση'), 'direct');
      expect(methodOf('LDL (υπολογιζόμενη)'), 'calc');
      expect(methodOf('LDL'), isNull);
    });

    test('Σ3: σύντομος κωδικός με μονάδα άλλης εξέτασης δεν ταιριάζει (η εφαρμογή ρωτά)', () {
      // «Tg» γράφεται και η θυρεοσφαιρίνη (ng/mL)· «Cr» και το χρώμιο· «ALB» και η λευκωματίνη ούρων (mg/L).
      expect(matchTest('Tg', unit: 'ng/mL'), isNull);
      expect(matchTest('TG', unit: 'mg/dL'), 'tg');
      expect(matchTest('TG', unit: 'mmol/L'), 'tg');
      expect(matchTest('TG'), 'tg', reason: 'χωρίς μονάδα: όπως πριν');
      expect(matchTest('TG', unit: '  '), 'tg', reason: 'κενή μονάδα = χωρίς μονάδα');
      expect(matchTest('Cr', unit: 'µg/L'), isNull);
      expect(matchTest('Cr', unit: 'mg/dL'), 'crea');
      expect(matchTest('Cr', unit: 'umol/L'), 'crea');
      expect(matchTest('ALB', unit: 'mg/L'), isNull);
      expect(matchTest('ALB', unit: 'g/dL'), 'alb');
      // Και μετά το «ορού» στο τέλος.
      expect(matchTest('Fe ορού', unit: 'µg/dL'), 'iron');
      expect(matchTest('Fe ορού', unit: 'mg/L'), isNull);
    });

    test('Σ3: ολόκληρο όνομα ταιριάζει και με άγνωστη μονάδα· όσα έμαθες εσύ δεν κρίνονται', () {
      expect(matchTest('Αιμοσφαιρίνη', unit: 'κάτι/άλλο'), 'hgb');
      expect(matchTest('Τριγλυκερίδια ορού', unit: 'ng/mL'), 'tg');
      expect(matchTest('Tg', learned: {foldName('Tg'): 'tg'}, unit: 'ng/mL'), 'tg');
    });

    test('Σ3: «Ca++» (ιονισμένο ή ολικό) δεν γίνεται «Ca» χωρίς ερώτηση', () {
      expect(matchTest('Ca'), 'ca');
      expect(matchTest('Ca++'), isNull);
      expect(matchTest('Ca++', unit: 'mmol/L'), isNull);
      expect(matchTest('Ca++', learned: {foldName('Ca++'): 'ca'}), 'ca', reason: 'αν το πεις εσύ, ισχύει');
    });
  });

  group('μονάδες', () {
    test('mmol/L σε mg/dL (από μοριακά βάρη)', () {
      expect(toBase(labById['ldl']!, 3.0, 'mmol/L')!, closeTo(116.0, 0.1));
      expect(toBase(labById['tg']!, 2.0, 'mmol/l')!, closeTo(177.1, 0.1));
      expect(toBase(labById['glu']!, 5.0, 'mmol/L')!, closeTo(90.1, 0.1));
      expect(toBase(labById['crea']!, 100, 'µmol/L')!, closeTo(1.13, 0.01));
      expect(toBase(labById['crea']!, 100, 'umol/L')!, closeTo(1.13, 0.01), reason: 'u αντί για µ');
      expect(toBase(labById['b12']!, 300, 'pmol/L')!, closeTo(406.6, 0.5));
      expect(toBase(labById['vitd']!, 50, 'nmol/L')!, closeTo(20.0, 0.1));
      expect(toBase(labById['hba1c']!, 42, 'mmol/mol')!, closeTo(6.0, 0.05));
      expect(toBase(labById['wbc']!, 5.0, '10^9/L'), 5.0);
      expect(toBase(labById['wbc']!, 5000, '/µL'), closeTo(5.0, 1e-9));
    });

    test('ίδια μονάδα με άλλη γραφή· άγνωστη μονάδα = καμία σύγκριση', () {
      expect(toBase(labById['ldl']!, 120, 'mg/dl'), 120);
      expect(toBase(labById['ldl']!, 120, 'MG/DL '), 120);
      expect(toBase(labById['tsh']!, 2.0, 'mIU/L'), 2.0);
      expect(toBase(labById['ldl']!, 120, 'g/L'), isNull);
      expect(toBase(labById['lpa']!, 50, 'nmol/L'), isNull, reason: 'Lp(a): δεν μετατρέπεται με ασφάλεια');
    });

    test('Σ3: «gr» αντί για «g» και οι γραφές του eGFR είναι η ίδια μονάδα', () {
      expect(toBase(labById['hgb']!, 14.0, 'gr/dL'), 14.0);
      expect(toBase(labById['glu']!, 90, 'mgr/dl'), 90);
      expect(toBase(labById['iron']!, 100, 'ugr/dl'), 100);
      expect(toBase(labById['egfr']!, 90, 'mL/min/1,73m²'), 90);
      expect(toBase(labById['egfr']!, 90, 'mL/min/1.73m^2'), 90);
      expect(toBase(labById['egfr']!, 90, 'ml/min/1,73 m2'), 90);
      expect(toBase(labById['egfr']!, 90, 'mL/min'), 90);
      expect(toBase(labById['egfr']!, 90, 'mL/sec'), isNull);
    });
  });

  group('αποτέλεσμα', () {
    const a = LabResult(day: '2030-01-15', rawName: 'LDL', value: 150, unit: 'mg/dL', testId: 'ldl', lab: 'Εργαστήριο Α', refHi: 130);
    const b = LabResult(day: '2030-04-15', rawName: 'LDL-C', value: 3.0, unit: 'mmol/L', testId: 'ldl', lab: 'Εργαστήριο Β', refHi: 3.4);

    test('σύγκριση στη βασική μονάδα, με «άλλο εργαστήριο»', () {
      final c = LabChange(a, b);
      expect(c.diff!, closeTo(-34.0, 0.2));
      expect(c.pct!, closeTo(-22.7, 0.2));
      expect(c.lessSure, isTrue);
      expect(a.flag, 1);
      expect(b.flag, 0);
      expect(b.baseHi!, closeTo(131.5, 0.1));
    });

    test('αποθήκευση και ανάγνωση· άγνωστο id μένει «άλλη εξέταση»', () {
      expect(LabResult.fromJson(a.toJson())!.toJson(), a.toJson());
      final odd = LabResult.fromJson({...a.toJson(), 't': 'kati-neo'})!;
      expect((odd.testId, odd.rawName, odd.value), (null, 'LDL', 150.0));
      expect(LabResult.fromJson({...a.toJson(), 'd': '15/01/2030'}), isNull);
      expect(LabResult.fromJson({...a.toJson(), 'v': 'x'}), isNull);
    });

    test('Σ3: άλλη εξέταση δεν συγκρίνεται, ό,τι μονάδα κι αν έχουν', () {
      const hdl = LabResult(day: '2030-04-15', rawName: 'HDL', value: 50, unit: 'mg/dL', testId: 'hdl');
      expect(LabChange(a, hdl).comparable, isFalse);
      expect(LabChange(a, hdl).diff, isNull);
      expect(LabChange(a, hdl).pct, isNull);
    });
  });

  group('Σ3: είδος δείγματος', () {
    test('αίμα, ούρα, άλλο, άγνωστο', () {
      for (final (raw, kind) in [
        ('Ορός', 'blood'),
        ('ΟΡΟΣ', 'blood'),
        ('Serum', 'blood'),
        ('Πλάσμα (EDTA)', 'blood'),
        ('Ολικό αίμα', 'blood'),
        ('Φλεβικό', 'blood'),
        ('Ούρα', 'urine'),
        ('Ούρα 24ώρου', 'urine'),
        ('Δείγμα ούρων', 'urine'),
        ('Urine', 'urine'),
        ('Κόπρανα', 'other'),
        ('Δείγμα', 'other'),
      ]) {
        expect(specimenKind(raw), kind, reason: raw);
      }
      expect(specimenKind(null), isNull);
      expect(specimenKind('  '), isNull);
    });

    const blood = LabResult(day: '2030-01-15', rawName: 'Γλυκόζη', value: 90, unit: 'mg/dL', testId: 'glu', specimen: 'Ορός');
    const urine = LabResult(day: '2030-04-15', rawName: 'Γλυκόζη', value: 15, unit: 'mg/dL', testId: 'glu', specimen: 'Ούρα');
    const old = LabResult(day: '2030-04-15', rawName: 'Γλυκόζη', value: 100, unit: 'mg/dL', testId: 'glu');

    test('ούρα με το ίδιο όνομα και την ίδια μονάδα: δεν είναι η εξέταση αίματος, δεν συγκρίνονται', () {
      expect(blood.notBlood, isFalse);
      expect(blood.test?.id, 'glu');
      expect(blood.base, 90);
      expect(urine.notBlood, isTrue);
      expect(urine.test, isNull);
      expect(urine.base, isNull);
      expect(LabChange(blood, urine).diff, isNull);
      expect(LabChange(blood, urine).pct, isNull);
    });

    test('το δείγμα αποθηκεύεται· τίποτα δεν χάνεται· παλιά καταχώριση χωρίς δείγμα όπως πριν', () {
      final back = LabResult.fromJson(urine.toJson())!;
      expect((back.specimen, back.testId, back.value), ('Ούρα', 'glu', 15.0));
      expect(old.toJson().containsKey('s'), isFalse);
      expect(LabResult.fromJson(old.toJson())!.specimen, isNull);
      expect(old.notBlood, isFalse);
      expect(LabChange(blood, old).diff, 10);
    });
  });

  group('Σ3: τιμή «< …» ή «> …»', () {
    const low = LabResult(day: '2030-01-15', rawName: 'hs-CRP', value: 0.5, unit: 'mg/L', testId: 'hscrp', below: true, refHi: 5);
    const next = LabResult(day: '2030-04-15', rawName: 'hs-CRP', value: 1.2, unit: 'mg/L', testId: 'hscrp', refHi: 5);

    test('δεν αφαιρείται σαν αριθμός', () {
      expect(low.censored, isTrue);
      expect(next.censored, isFalse);
      expect(LabChange(low, next).comparable, isFalse);
      expect(LabChange(low, next).diff, isNull);
      expect(LabChange(low, next).pct, isNull);
      expect(LabChange(next, low).diff, isNull);
      expect(LabResult.fromJson(low.toJson())!.below, isTrue);
    });

    test('όρια: «< 3» με κάτω όριο 3 είναι κάτω· ό,τι δεν ξέρουμε μένει 0', () {
      LabResult r(double v, {bool below = false, bool above = false, double? lo, double? hi}) => LabResult(
          day: '2030-01-15', rawName: 'Χ', value: v, unit: 'mg/L', below: below, above: above, refLo: lo, refHi: hi);
      expect(r(3, lo: 3).flag, 0, reason: 'ακριβώς στο όριο: μέσα');
      expect(r(3, below: true, lo: 3).flag, -1);
      expect(r(2, below: true, lo: 3).flag, -1);
      expect(r(4, below: true, lo: 3).flag, 0, reason: '«< 4» με όριο 3: δεν ξέρουμε');
      expect(r(100, hi: 100).flag, 0);
      expect(r(100, above: true, hi: 100).flag, 1);
      expect(r(120, above: true, hi: 100).flag, 1);
      expect(r(90, above: true, hi: 100).flag, 0, reason: '«> 90» με όριο 100: δεν ξέρουμε');
      expect(r(200, below: true, hi: 150).flag, 0, reason: '«< 200» δεν είναι σίγουρα πάνω από 150');
      expect(r(2, above: true, lo: 5).flag, 0, reason: '«> 2» δεν είναι σίγουρα κάτω από 5');
      expect(r(0.5, below: true, hi: 5).flag, 0);
      expect(r(7, lo: 3, hi: 5).flag, 1);
      expect(r(1, lo: 3, hi: 5).flag, -1);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  // Τελικός έλεγχος, Συμβούλιο 3. Τα ονόματα είναι όπως τα τυπώνει ένα εργαστήριο σε κάθε γραμμή (όχι προσωπικά
  // δεδομένα)· οι τιμές είναι φανταστικές.
  // ---------------------------------------------------------------------------------------------------------------

  group('Λ1: όνομα με κωδικό στο τέλος, «Γλυκόζη (GLUC)»', () {
    // (όνομα όπως τυπώνεται, μονάδα όπως τυπώνεται, εξέταση του καταλόγου ή null όταν ο κατάλογος δεν την έχει)
    const lines = <(String, String, String?)>[
      ('Λευκά Αιμοσφαίρια (WBC)', 'x10^3 / μL', 'wbc'),
      ('Ερυθρά Αιμοσφαίρια (RBC)', 'x10^6 / μL', 'rbc'),
      ('Αιμοσφαιρίνη (HGB)', 'gr/dL', 'hgb'),
      ('Αιματοκρίτης (HCT)', '%', 'hct'),
      ('Μέσος Όγκος Ερυθρών (ΜCV)', 'fl', 'mcv'), // ελληνικό Μ
      ('Μέση περιεκτικότητα αιμοσφαιρίνης (MCH)', 'pg', null),
      ('Μέση συγκέντρωση αιμοσφαιρίνης (MCHC)', 'gr/dL', null),
      ('Εύρος κατανομής ερυθρών (RDW)', '%', null),
      ('Αιμοπετάλια (PLT)', 'x10^3 / μL', 'plt'),
      ('Μέσος όγκος αιμοπεταλίων (MPV)', 'fl', null),
      ('Ουδετερόφιλα (NEUT)', '%', null),
      ('Λεμφοκύτταρα (LYMPH)', '%', null),
      ('Γλυκόζη (GLUC)', 'mg/dL', 'glu'),
      ('Γλυκοζυλιωμένη Αιμοσφαιρίνη (HbA1C)', '%', 'hba1c'),
      ('Ολική χοληστερόλη (TC)', 'mg/dL', 'chol'),
      ('Τριγλυκερίδια (TRIG)', 'mg/dL', 'tg'),
      ('Χοληστερόλη υψηλής πυκνότητας λιποπρωτεϊνών (ΗDL-C)', 'mg/dL', 'hdl'), // ελληνικό Η
      ('Χοληστερόλη χαμηλής πυκνότητας λιποπρωτεϊνών (LDL-C)', 'mg/dL', 'ldl'),
      ('Ουρία (UREA)', 'mg/dL', 'urea'),
      ('Κρεατινίνη (CREA)', 'mg/dL', 'crea'),
      ('Ουρικό οξύ (UA)', 'mg/dL', 'uric'),
      ('Estimated GFR 2021 CKD-EPI Creatinine', 'mL/min/1.73m^2', 'egfr'),
      ('Οξαλοξική τρανσαμινάση (SGOT/AST)', 'U/L', 'ast'),
      ('Πυροσταφυλική τρανσαμινάση (SGPT/ALT)', 'U/L', 'alt'),
      ('γ-Γλουταμυλοτρανσφεράση (γ-GT)', 'U/L', 'ggt'),
      ('Κάλιο (K)', 'mmol/L', 'k'),
      ('Νάτριο (Na)', 'mmol/L', 'na'),
      ('Φερριτίνη', 'ng/mL', 'ferritin'),
      ('Βιταμίνη Β12', 'pg/mL', 'b12'), // ελληνικό Β
      ('Φυλλικό οξύ', 'ng/mL', 'folate'),
      ('C-Αντιδρώσα πρωτεϊνη (CRP)', 'mg/L', 'crp'),
      ('25-υδροξυβιταμίνη D [25(ΟΗ)D]', 'ng/mL', 'vitd'), // ελληνικά Ο και Η, αγκύλες, παρένθεση μέσα
      ('Θυρεοτρόπος ορμόνη (TSH)', 'μIU/mL', 'tsh'),
      ('Ειδικό προστατικό αντιγόνο (PSA)', 'ng/mL', 'psa'),
    ];

    test('κάθε γραμμή του εργαστηρίου: η σωστή εξέταση, με και χωρίς μονάδα· ποτέ λάθος εξέταση', () {
      // Πριν: 4 από τις 28 γραμμές που έχει ο κατάλογος (όσες δεν είχαν κωδικό).
      for (final (raw, unit, id) in lines) {
        expect(matchTest(raw, unit: unit), id, reason: '$raw [$unit]');
        expect(matchTest(raw), id, reason: '$raw, χωρίς μονάδα');
      }
      expect(lines.where((l) => l.$3 != null).length, 28);
    });

    test('χωρισμός ονόματος και κωδικού, και με παρένθεση μέσα στην αγκύλη', () {
      expect(splitNameCode('Γλυκόζη (GLUC)'), (name: 'Γλυκόζη', code: 'GLUC'));
      expect(splitNameCode('25-υδροξυβιταμίνη D [25(ΟΗ)D]'), (name: '25-υδροξυβιταμίνη D', code: '25(ΟΗ)D'));
      expect(splitNameCode('Λιποπρωτεΐνη (Lp(a))'), (name: 'Λιποπρωτεΐνη', code: 'Lp(a)'));
      expect(splitNameCode('  Κάλιο  ( K )  '), (name: 'Κάλιο', code: 'K'));
      for (final raw in ['Γλυκόζη', 'Γλυκόζη (GLUC', 'Γλυκόζη GLUC)', '(GLUC)', 'Γλυκόζη ()', 'Γλυκόζη (GLUC) *', 'a)', '']) {
        expect(splitNameCode(raw), isNull, reason: raw);
      }
    });

    test('όταν όνομα και κωδικός δεν δένουν, η εφαρμογή ρωτά', () {
      for (final (raw, unit) in <(String, String?)>[
        ('Χοληστερόλη (non-HDL)', null), // όνομα = ολική, κωδικός = non-HDL
        ('Χοληστερόλη (VLDL)', null), // γνωστό όνομα, άγνωστος κωδικός: ποτέ «Ολική χοληστερίνη»
        ('Αιμοσφαιρίνη (MCH)', null),
        ('Αιμοσφαιρίνη (HbA1c)', null),
        ('Λευκά (NEUT)', null),
        ('Σίδηρος (TIBC)', null),
        ('Θυρεοσφαιρίνη (TG)', 'ng/mL'), // «TG» εδώ δεν είναι τριγλυκερίδια
        ('Θυρεοσφαιρίνη (TG)', null),
        ('Χρώμιο (Cr)', 'µg/L'),
        ('Χρώμιο (Cr)', null),
        ('Κάλιο ούρων (K)', 'mmol/L'), // ίδια μονάδα με το κάλιο αίματος
        ('Κάλιο ούρων (K)', null),
        ('Κρεατινίνη ούρων (CREA)', 'mg/dL'),
        ('Γλυκόζη ούρων (GLUC)', 'mg/dL'),
        ('Urine creatinine (CREA)', null),
        ('Κάθαρση κρεατινίνης (CREA)', 'mL/min'),
        ('Ασβέστιο ιονισμένο (Ca++)', 'mmol/L'),
        ('Άγνωστη εξέταση (XYZ)', null),
        ('Γλυκόζη (GLUC', null),
        ('Γλυκόζη GLUC)', null),
      ]) {
        expect(matchTest(raw, unit: unit), isNull, reason: '$raw [$unit]');
      }
    });

    test('ο κωδικός μόνος του αρκεί μόνο με τους όρους του', () {
      expect(matchTest('Άγνωστο όνομα (TRIG)'), 'tg', reason: 'κωδικός πάνω από 3 γράμματα, χωρίς μονάδα');
      expect(matchTest('Άγνωστο όνομα (TRIG)', unit: 'mg/dL'), 'tg');
      expect(matchTest('Άγνωστο όνομα (TRIG)', unit: 'ng/mL'), isNull, reason: 'η μονάδα δεν είναι της εξέτασης');
      expect(matchTest('Άγνωστο όνομα (TG)', unit: 'mg/dL'), 'tg', reason: 'σύντομος κωδικός με δεκτή μονάδα');
      expect(matchTest('Άγνωστο όνομα (TG)'), isNull, reason: 'σύντομος κωδικός χωρίς μονάδα');
      expect(matchTest('WBC (Λευκά αιμοσφαίρια)', unit: 'K/μL'), 'wbc', reason: 'και με ανάποδη σειρά');
      expect(matchTest('Αιματοκρίτης (Ht)', unit: '%'), 'hct');
      expect(matchTest('Λευκά αιμοσφαίρια (WBC)', unit: 'κάτι/άλλο'), 'wbc', reason: 'όνομα και κωδικός συμφωνούν: η μονάδα ρωτιέται χωριστά');
      expect(matchTest('Κρεατινίνη ορού (CREA)', unit: 'mg/dL'), 'crea');
      expect(matchTest('Χοληστερόλη (LDL)'), 'ldl', reason: 'ολόκληρο το όνομα είναι ήδη γνωστό: οι παρενθέσεις διπλώνονται');
      expect(matchTest('Χοληστερόλη (VLDL)', learned: {foldName('Χοληστερόλη (VLDL)'): 'chol'}), 'chol', reason: 'ό,τι έμαθες εσύ ισχύει');
    });
  });

  group('Λ2: eGFR όπως γράφεται στις «Παρατηρήσεις»', () {
    test('ολόκληρο το όνομα είναι eGFR, ποτέ κρεατινίνη', () {
      for (final raw in [
        'Estimated GFR 2021 CKD-EPI Creatinine',
        'estimated gfr',
        'eGFR CKD-EPI 2021',
        'eGFR (CKD-EPI)',
        'eGFR',
        'Εκτιμώμενος ρυθμός σπειραματικής διήθησης',
      ]) {
        expect(matchTest(raw), 'egfr', reason: raw);
        expect(matchTest(raw, unit: 'mL/min/1.73m^2'), 'egfr', reason: raw);
      }
      expect(matchTest('Creatinine'), 'crea');
      expect(matchTest('Κρεατινίνη'), 'crea');
      expect(matchTest('Estimated GFR 2021 CKD-EPI Cystatin C'), isNull, reason: 'άλλη εξίσωση: η εφαρμογή ρωτά');
      expect(toBase(labById['egfr']!, 90, 'mL/min/1.73m^2'), 90);
    });
  });

  group('Λ3: ελληνικά και λατινικά γράμματα που μοιάζουν, τόνοι', () {
    test('κάθε κεφαλαίο ζευγάρι διπλώνεται ίδια', () {
      for (final pair in ['ΑA', 'ΒB', 'ΕE', 'ΖZ', 'ΗH', 'ΙI', 'ΚK', 'ΜM', 'ΝN', 'ΟO', 'ΡP', 'ΤT', 'ΥY', 'ΧX']) {
        expect(foldName(pair[0]), foldName(pair[1]), reason: pair);
      }
      expect(foldName('µIU/mL'), foldName('μIU/mL'), reason: 'το «μικρο» (U+00B5) και το ελληνικό μ');
    });

    test('κωδικοί και ονόματα με ανακατεμένα γράμματα', () {
      for (final (raw, id) in [
        ('ΗDL-C', 'hdl'), ('HDL-C', 'hdl'), ('ΜCV', 'mcv'), ('MCV', 'mcv'), ('Β12', 'b12'), ('B12', 'b12'), ('ΤSΗ', 'tsh'),
        ('ΑLΤ', 'alt'), ('ΑSΤ', 'ast'), ('ΡLΤ', 'plt'), ('ΗΒΑ1C', 'hba1c'), ('25(ΟΗ)D', 'vitd'), ('25(OH)D', 'vitd'),
        ('Kάλιο', 'k'), ('Oυρία', 'urea'), ('Tριγλυκερίδια', 'tg'), ('Aιμοσφαιρίνη', 'hgb'), // λατινικό πρώτο γράμμα
        ('Προστατικό Ειδικό Αντιγόνο (ΡSΑ)', 'psa'),
      ]) {
        expect(matchTest(raw), id, reason: raw);
      }
    });

    test('τόνος από το πολυτονικό μπλοκ, τόνος χωριστά από το γράμμα, κεφαλαία, σκληρό κενό', () {
      // Πριν: το «ό» ως U+1F79 χανόταν ολόκληρο («γλυκζη») και η γραμμή δεν αναγνωριζόταν.
      expect(matchTest('Γλυκ\u{1F79}ζη'), 'glu');
      expect(matchTest('Γλυκο\u{301}ζη'), 'glu');
      expect(matchTest('ΓΛΥΚΟΖΗ'), 'glu');
      expect(matchTest('Ολική\u{A0}χοληστερόλη'), 'chol');
      expect(matchTest('ΦΕΡΡΙΤΙΝΗ'), 'ferritin');
      expect(foldName('\u{1F71}\u{1F73}\u{1F75}\u{1F77}\u{1F79}\u{1F7B}\u{1F7D}\u{1FD3}\u{1FE3}'), foldName('άέήίόύώΐΰ'));
    });
  });

  group('Λ4: παρόμοιες εξετάσεις δεν μπερδεύονται', () {
    test('η ίδια εξέταση με τα ονόματά της', () {
      for (final (raw, id) in [
        ('Χολερυθρίνη ολική', 'bili'), ('PSA', 'psa'), ('FT4', 'ft4'), ('Ελεύθερη T4', 'ft4'), ('Σίδηρος ορού', 'iron'), ('Hb', 'hgb'),
        ('HbA1c', 'hba1c'), ('Ca', 'ca'), ('CRP', 'crp'), ('hs-CRP', 'hscrp'), ('CRP υψηλής ευαισθησίας', 'hscrp'), ('ApoB', 'apob'),
        ('Lp(a)', 'lpa'), ('Non-HDL', 'nonhdl'), ('Ουρία', 'urea'), ('Ουρικό οξύ', 'uric'), ('Κρεατινίνη ορού', 'crea'), ('Λευκά', 'wbc'),
        ('Λευκωματίνη', 'alb'), ('Αιμοσφαιρίνη', 'hgb'), ('Γλυκοζυλιωμένη αιμοσφαιρίνη', 'hba1c'),
      ]) {
        expect(matchTest(raw), id, reason: raw);
      }
    });

    test('άλλη εξέταση με παρόμοιο όνομα: null (η εφαρμογή ρωτά, δεν μαντεύει)', () {
      for (final raw in [
        'Χολερυθρίνη άμεση', 'Χολερυθρίνη έμμεση', 'Direct bilirubin', 'Ελεύθερο PSA', 'Free PSA', 'PSA ελεύθερο', 'Λόγος ελεύθερου/ολικού PSA',
        'T4', 'T3', 'FT3', 'Ολική T4', 'Σιδηροδεσμευτική ικανότητα', 'TIBC', 'Τρανσφερρίνη', 'Κορεσμός τρανσφερρίνης', 'MCH', 'MCHC', 'RDW',
        'MPV', 'CA 125', 'CA 19-9', 'CA 15-3', 'CEA', 'Vitamin K', 'Βιταμίνη K', 'Χλώριο', 'Μαγνήσιο', 'Φώσφορος', 'Apo A1', 'VLDL',
        'Χοληστερόλη VLDL', 'Λευκώματα ολικά', 'Ολικά λευκώματα', 'Σφαιρίνες', 'Κάθαρση κρεατινίνης', 'Κρεατινίνη ούρων', 'Γλυκόζη ούρων',
        'Λευκωματίνη ούρων', 'Μικρολευκωματίνη', 'Ούρα', 'Γενική ούρων', 'Γλυκόζη 2 ωρών', 'Καμπύλη σακχάρου', 'Anti-TPO', 'Anti-Tg',
        'Θυρεοσφαιρίνη', 'CK', 'CPK', 'LDH', 'Αμυλάση', 'Ομοκυστεΐνη', 'Ινωδογόνο', 'D-Dimers', 'ΤΚΕ', 'Ουδετερόφιλα', 'Λεμφοκύτταρα',
      ]) {
        expect(matchTest(raw), isNull, reason: raw);
      }
    });
  });

  group('Λ5: αριθμός όπως τον γράφει το εργαστήριο', () {
    (double, bool, bool)? read(String raw, [DecimalMark? mark]) {
      final n = parseLabNumber(raw, mark: mark);
      return n == null ? null : (n.value, n.below, n.above);
    }

    test('«4.500»: 4,5 σε έγγραφο με τελεία, 4.500 σε έγγραφο με κόμμα, ερώτηση όταν δεν φαίνεται', () {
      expect(read('4.500', DecimalMark.dot), (4.5, false, false));
      expect(read('4.500', DecimalMark.comma), (4500.0, false, false));
      expect(read('4.500'), isNull);
      expect(read('250.000', DecimalMark.comma), (250000.0, false, false));
      expect(read('250.000', DecimalMark.dot), (250.0, false, false));
      expect(read('12,345', DecimalMark.comma), (12.345, false, false));
      expect(read('12,345', DecimalMark.dot), (12345.0, false, false));
      expect(read('12,345'), isNull);
    });

    test('«4,5», «< 0,5», «> 1000», «≤ 5.7»', () {
      expect(read('4,5'), (4.5, false, false));
      expect(read('4,5', DecimalMark.comma), (4.5, false, false));
      expect(read('4,5', DecimalMark.dot), isNull, reason: 'κόμμα σε έγγραφο με τελεία: ύποπτο, η εφαρμογή ρωτά');
      expect(read('< 0,5'), (0.5, true, false));
      expect(read('<0.5', DecimalMark.dot), (0.5, true, false));
      expect(read('> 1000'), (1000.0, false, true));
      expect(read('≤ 5.7'), (5.7, true, false));
      expect(read('<= 5.7'), (5.7, true, false));
      expect(read('>=60'), (60.0, false, true));
      expect(read('≥ 90'), (90.0, false, true));
      expect(read('13.2'), (13.2, false, false));
      expect(read('0,63'), (0.63, false, false));
      expect(read('105'), (105.0, false, false));
      expect(read('0.125'), (0.125, false, false), reason: 'ομάδα χιλιάδων δεν αρχίζει με 0: σίγουρα δεκαδικός');
      expect(read('1234.567'), (1234.567, false, false));
      expect(read('\u{A0}4,5\u{A0}'), (4.5, false, false));
    });

    test('χιλιάδες και δεκαδικά μαζί διαβάζονται από το σχήμα τους', () {
      expect(read('1.234,5'), (1234.5, false, false));
      expect(read('1,234.5'), (1234.5, false, false));
      expect(read('1.234,5', DecimalMark.dot), isNull, reason: 'αντιφάσκει με το έγγραφο');
      expect(read('1.234.567'), (1234567.0, false, false));
      expect(read('1.234.567', DecimalMark.dot), isNull);
      expect(read('1.23.456'), isNull, reason: 'κακές ομάδες');
    });

    test('δύο αριθμοί, εύρος, σημάδια, γράμματα: δεν είναι τιμή', () {
      // «4.5 5.1»: σημερινή και προηγούμενη τιμή στο ίδιο κελί. «4.00 - 10.50»: όρια αναφοράς.
      for (final raw in [
        '4.5 5.1', '4.00 - 10.50', '4,5-10,5', '74 – 100', '', '   ', 'αρνητικό', '4,5*', '115 H', '5.', '.5', '1e3', 'NaN', '-2.5',
        '4..5', '4,,5', '<', '< >5', '4.5 mg/dL',
      ]) {
        for (final mark in [null, DecimalMark.dot, DecimalMark.comma]) {
          expect(parseLabNumber(raw, mark: mark), isNull, reason: '«$raw» με $mark');
        }
      }
    });

    test('η υποδιαστολή βγαίνει από όλο το έγγραφο', () {
      expect(decimalMarkOf(['4.00', '10.50', '6.54', '115', '< 45', '4.500']), DecimalMark.dot);
      expect(decimalMarkOf(['4,5', '13,2', '250.000', '1.234,5']), DecimalMark.comma);
      expect(decimalMarkOf(['4.500', '250.000', '115']), isNull, reason: 'μόνο διφορούμενοι αριθμοί');
      expect(decimalMarkOf(['4.5', '4,5']), isNull, reason: 'ανάμεικτα');
      expect(decimalMarkOf(const []), isNull);
      expect(decimalMarkOf(['abc', '4.00 - 10.50']), isNull);
      expect(decimalMarkOf(['1.234.567']), DecimalMark.comma, reason: 'τελείες στις χιλιάδες: υποδιαστολή το κόμμα');
      expect(decimalMarkOf(['1,234,567']), DecimalMark.dot);
      // Το ίδιο «4.500» σε δύο έγγραφα.
      expect(read('4.500', decimalMarkOf(['6.54', '4.00', '10.50', '4.500'])), (4.5, false, false));
      expect(read('4.500', decimalMarkOf(['4.500', '4.000', '10.500', '13,2'])), (4500.0, false, false));
    });

    test('λευκά αιμοσφαίρια: ίδια τιμή στη βασική μονάδα, όπως κι αν γραφτεί', () {
      final wbc = labById['wbc']!;
      // Έγγραφο με τελεία, σε χιλιάδες ανά μικρόλιτρο.
      expect(toBase(wbc, parseLabNumber('4.50', mark: DecimalMark.dot)!.value, 'x10^3 / μL'), closeTo(4.5, 1e-9));
      // Έγγραφο με κόμμα, σε κύτταρα ανά μικρόλιτρο.
      expect(toBase(wbc, parseLabNumber('4.500', mark: DecimalMark.comma)!.value, '/μL'), closeTo(4.5, 1e-9));
      expect(toBase(wbc, parseLabNumber('4,5', mark: DecimalMark.comma)!.value, 'K/μL'), closeTo(4.5, 1e-9));
    });
  });
}
