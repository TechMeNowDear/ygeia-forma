// Κατάλογος εξετάσεων (12/11): ονόματα, μονάδες, όρια.
// ΟΛΕΣ οι τιμές και οι ημερομηνίες εδώ είναι φανταστικές, στρογγυλές (δημόσιο repo): ποτέ πραγματικά αποτελέσματα.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/labs/catalog.dart';
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
}
