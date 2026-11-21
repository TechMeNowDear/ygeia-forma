// Βαθύς έλεγχος 20/11/2026, κατηγορία 5 (συσκευές: Samsung Health, Oura, InBody): οι διορθώσεις των K5-api και K5-meaning.
// Επινοημένα δεδομένα. Κάθε δοκιμή γράφει τι έβγαινε ΠΡΙΝ.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/config.dart';
import 'package:ygeia_forma/reference.dart';
import 'package:ygeia_forma/sources.dart';

int _ms(DateTime t) => t.millisecondsSinceEpoch;

const _inbody = 'com.inbody2014.inbody';

Map<String, dynamic> _w(DateTime day, double kg, {double? bmi, double? height}) => {
      'time': _ms(day.add(const Duration(hours: 8))),
      'weight': kg,
      if (bmi != null) 'bmi': bmi,
      if (height != null) 'height': height,
      'app': _inbody,
    };

void main() {
  // ------------------------------------------------------------------ K5A-05 / K5M-01
  group('K5A-05 / K5M-01: το ύψος της ζύγισης', () {
    test('η εγγραφή διαβάζει το δικό της ύψος («height», cm)· παράλογη τιμή = δεν υπάρχει', () {
      final d = Dashboard.fromJson({
        'readAt': _ms(DateTime(2026, 11, 23, 12)),
        'body': [
          _w(DateTime(2026, 11, 21), 82.4, bmi: 26.3, height: 170),
          _w(DateTime(2026, 11, 22), 82.2, bmi: 26.24),
          _w(DateTime(2026, 11, 23), 82.0, bmi: 26.2, height: 17),
        ],
      });
      expect([for (final b in d.body) b.heightCm], [170.0, null, null]);
    });

    test('ύψος εγγραφής 170, δείκτης 26,24 (= 177 cm), στοιχεία μου 177: μήνυμα με «170» (πριν: κανένα μήνυμα)', () {
      final note = scaleHeightNote(recordCm: 170, weight: 82.2, bmi: 26.24, profileCm: 177);
      expect(note, startsWith('Η ζύγιση γράφτηκε με ύψος 170 cm, τα στοιχεία σου 177 cm.'));
      expect(note, contains('εφαρμογή InBody'));
    });

    test('ύψος εγγραφής ίσο με τα στοιχεία μου, δείκτης από άλλο ύψος: κανένα μήνυμα (πριν: «Η εφαρμογή InBody έχει ύψος 175»)', () {
      // Προφίλ Samsung Health 175 cm → δείκτης 26,84· η InBody και η εφαρμογή έχουν 177.
      expect(scaleHeightNote(recordCm: 177, weight: 82.2, bmi: 26.84, profileCm: 177), isNull);
    });

    test('χωρίς ύψος στην εγγραφή: από τον δείκτη, και δεν το αποδίδει μόνο στην InBody', () {
      final note = scaleHeightNote(weight: 82.2, bmi: 26.84, profileCm: 177);
      expect(note, startsWith('Η Samsung Health ή η InBody έχει ύψος 175 cm'));
      expect(note, isNot(contains('Η εφαρμογή InBody έχει')));
      expect(scaleHeightNote(weight: 82.2, bmi: 26.24, profileCm: 177), isNull, reason: 'διαφορά κάτω από 1 cm');
      expect(scaleHeightNote(weight: 82.2, bmi: 26.84), isNull, reason: 'χωρίς ύψος στα στοιχεία μου');
      expect(scaleHeightNote(profileCm: 177), isNull);
    });

    test('scaleHeightCm: πρώτα η εγγραφή, μετά ο δείκτης', () {
      expect(scaleHeightCm(recordCm: 170, weight: 81, bmi: 25), (cm: 170.0, fromRecord: true));
      final h = scaleHeightCm(weight: 81, bmi: 25)!;
      expect(h.cm, closeTo(180.0, 1e-9));
      expect(h.fromRecord, isFalse);
      expect(scaleHeightCm(weight: 81), isNull);
    });
  });

  // ------------------------------------------------------------------ K5A-06
  group('K5A-06: ζυγίσεις που σβήστηκαν στη Samsung / InBody', () {
    test('ο κανόνας: ως 3, ή ως το 10% των ημερών που δίνει τώρα η Samsung', () {
      expect(bodyRemovalAllowed(3, 5), isTrue);
      expect(bodyRemovalAllowed(4, 60), isTrue);
      expect(bodyRemovalAllowed(4, 39), isFalse);
      expect(bodyRemovalAllowed(6, 60), isTrue);
      expect(bodyRemovalAllowed(7, 60), isFalse);
      expect(bodyRemovalAllowed(70, 30), isFalse, reason: 'μισή απάντηση (π.χ. μόνο 30 μέρες): τίποτα');
    });

    Map<String, Map<String, double>> history(int n, List<DateTime> extra) => {
          for (var i = 0; i < n; i++) dateKey(DateTime(2026, 8, 1 + i)): {K.weight: 85.0 - i * 0.05, K.steps: 7000},
          for (final d in extra) dateKey(d): {K.weight: 60.0, K.steps: 5000},
        };
    Dashboard read(int n) => Dashboard.fromJson({
          'readAt': _ms(DateTime(2026, 11, 20, 12)),
          'body': [for (var i = 0; i < n; i++) _w(DateTime(2026, 8, 1 + i), 85.0 - i * 0.05)],
        });
    // Έξω από τις 30 μέρες της κανονικής ανάγνωσης, ώστε να κρίνεται μόνο ο κανόνας των ζυγίσεων.
    final guest = [for (var i = 0; i < 4; i++) DateTime(2026, 10, 1 + i)];

    test('4 ζυγίσεις επισκέπτη σβήστηκαν και η Samsung δίνει τις άλλες 60: φεύγουν (πριν έμεναν για πάντα)', () {
      final h = history(60, guest);
      applyRecentRead(h, read(60), plan: SourcePlan.samsungOnly);
      for (final d in guest) {
        expect(h[dateKey(d)]!.containsKey(K.weight), isFalse, reason: dateKey(d));
        expect(h[dateKey(d)]![K.steps], 5000, reason: 'οι άλλες τιμές της μέρας μένουν');
      }
      expect(h['2026-08-01']![K.weight], 85.0);
    });

    test('η Samsung δίνει μόνο 10 ζυγίσεις και θα έφευγαν 4: τίποτα δεν σβήνεται (όπως πριν)', () {
      final h = history(10, guest);
      applyRecentRead(h, read(10), plan: SourcePlan.samsungOnly);
      for (final d in guest) {
        expect(h[dateKey(d)]![K.weight], 60.0);
      }
    });

    test('μισή απάντηση (30 από 60 μέρες): καμία από τις 30 που λείπουν δεν σβήνεται', () {
      final h = history(60, const []);
      applyRecentRead(h, read(30), plan: SourcePlan.samsungOnly);
      expect(h.values.where((m) => m.containsKey(K.weight)).length, 60);
    });
  });

  // ------------------------------------------------------------------ K5A-03, K5A-04
  test('K5A-03 / K5A-04: τα παράθυρα επανανάγνωσης', () {
    expect(HealthStore.gapLeadDays, 3, reason: 'το κενό μετά από κλειστή εφαρμογή αρχίζει 3 μέρες πριν από την τελευταία γραμμένη');
    expect(ouraRecentDays, 7, reason: 'η Oura διορθώνει νύχτες και μετά τη 2η μέρα· πριν 3');
    expect(ouraRecentDays, lessThanOrEqualTo(ouraMissingDays));
  });
}
