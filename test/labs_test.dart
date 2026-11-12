// Κατάλογος εξετάσεων (12/11): ονόματα, μονάδες, όρια. Φανταστικές τιμές (δημόσιο repo).
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
  });

  group('μονάδες', () {
    test('mmol/L σε mg/dL (από μοριακά βάρη)', () {
      expect(toBase(labById['ldl']!, 4.14, 'mmol/L')!, closeTo(160.1, 0.1));
      expect(toBase(labById['tg']!, 1.67, 'mmol/l')!, closeTo(147.9, 0.1));
      expect(toBase(labById['glu']!, 6.4, 'mmol/L')!, closeTo(115.3, 0.1));
      expect(toBase(labById['crea']!, 94.6, 'µmol/L')!, closeTo(1.07, 0.01));
      expect(toBase(labById['crea']!, 94.6, 'umol/L')!, closeTo(1.07, 0.01), reason: 'u αντί για µ');
      expect(toBase(labById['b12']!, 188, 'pmol/L')!, closeTo(254.8, 0.5));
      expect(toBase(labById['vitd']!, 70, 'nmol/L')!, closeTo(28.0, 0.1));
      expect(toBase(labById['hba1c']!, 37, 'mmol/mol')!, closeTo(5.5, 0.05));
      expect(toBase(labById['wbc']!, 6.2, '10^9/L'), 6.2);
      expect(toBase(labById['wbc']!, 6200, '/µL'), closeTo(6.2, 1e-9));
    });

    test('ίδια μονάδα με άλλη γραφή· άγνωστη μονάδα = καμία σύγκριση', () {
      expect(toBase(labById['ldl']!, 160, 'mg/dl'), 160);
      expect(toBase(labById['ldl']!, 160, 'MG/DL '), 160);
      expect(toBase(labById['tsh']!, 1.52, 'mIU/L'), 1.52);
      expect(toBase(labById['ldl']!, 160, 'g/L'), isNull);
      expect(toBase(labById['lpa']!, 75, 'nmol/L'), isNull, reason: 'Lp(a): δεν μετατρέπεται με ασφάλεια');
    });
  });

  group('αποτέλεσμα', () {
    const a = LabResult(day: '2026-11-10', rawName: 'LDL', value: 160, unit: 'mg/dL', testId: 'ldl', lab: 'Εργαστήριο Α', refHi: 130);
    const b = LabResult(day: '2027-02-10', rawName: 'LDL-C', value: 3.36, unit: 'mmol/L', testId: 'ldl', lab: 'Εργαστήριο Β', refHi: 3.4);

    test('σύγκριση στη βασική μονάδα, με «άλλο εργαστήριο»', () {
      final c = LabChange(a, b);
      expect(c.diff!, closeTo(-30.1, 0.2));
      expect(c.pct!, closeTo(-18.8, 0.2));
      expect(c.lessSure, isTrue);
      expect(a.flag, 1);
      expect(b.flag, 0);
      expect(b.baseHi!, closeTo(131.5, 0.1));
    });

    test('αποθήκευση και ανάγνωση· άγνωστο id μένει «άλλη εξέταση»', () {
      expect(LabResult.fromJson(a.toJson())!.toJson(), a.toJson());
      final odd = LabResult.fromJson({...a.toJson(), 't': 'kati-neo'})!;
      expect((odd.testId, odd.rawName, odd.value), (null, 'LDL', 160.0));
      expect(LabResult.fromJson({...a.toJson(), 'd': '10/11/2026'}), isNull);
      expect(LabResult.fromJson({...a.toJson(), 'v': 'x'}), isNull);
    });
  });
}
