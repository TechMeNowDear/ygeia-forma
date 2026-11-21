// Βαθύς έλεγχος 20/11/2026, κατηγορία 5 (συσκευές: Samsung Health, Oura, InBody): οι διορθώσεις των K5-api και K5-meaning.
// Επινοημένα δεδομένα. Κάθε δοκιμή γράφει τι έβγαινε ΠΡΙΝ.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/labels.dart';
import 'package:ygeia_forma/oura/config.dart';
import 'package:ygeia_forma/oura/oura_view.dart';
import 'package:ygeia_forma/reference.dart';
import 'package:ygeia_forma/sources.dart';

int _ms(DateTime t) => t.millisecondsSinceEpoch;

const _inbody = 'com.inbody2014.inbody';

Map<String, dynamic> _w(DateTime day, double kg, {double? bmi, double? height, String app = _inbody}) => {
      'time': _ms(day.add(const Duration(hours: 8))),
      'weight': kg,
      if (bmi != null) 'bmi': bmi,
      if (height != null) 'height': height,
      'app': app,
    };

void main() {
  // ------------------------------------------------------------------ K5A-05 / K5M-01
  group('K5A-05 / K5M-01: το ύψος της ζύγισης', () {
    test('η εγγραφή διαβάζει το δικό της ύψος («height», cm)· παράλογη τιμή = δεν υπάρχει', () {
      final d = Dashboard.fromJson({
        'readAt': _ms(DateTime(2026, 11, 23, 12)),
        'body': [
          _w(DateTime(2026, 11, 21), 84.2, bmi: 29.1, height: 170),
          _w(DateTime(2026, 11, 22), 84.0, bmi: 25.93),
          _w(DateTime(2026, 11, 23), 83.8, bmi: 25.9, height: 17),
          // K5-R-04: ύψος σε μέτρα ή 0 (αν η Samsung το γράφει αλλιώς) = δεν υπάρχει· τότε μετρά ο δείκτης.
          _w(DateTime(2026, 11, 24), 83.8, bmi: 25.9, height: 1.8),
          _w(DateTime(2026, 11, 25), 83.8, bmi: 25.9, height: 0),
        ],
      });
      expect([for (final b in d.body) b.heightCm], [170.0, null, null, null, null]);
    });

    test('ύψος εγγραφής 170, δείκτης 25,93 (= 180 cm), στοιχεία μου 180: μήνυμα με «170» (πριν: κανένα μήνυμα)', () {
      final note = scaleHeightNote(recordCm: 170, weight: 84.0, bmi: 25.93, profileCm: 180);
      expect(note, startsWith('Η ζύγιση γράφτηκε με ύψος 170 cm, τα στοιχεία σου 180 cm.'));
      // K5-R-04: δεν ξέρουμε ακόμα ποιος γράφει το ύψος της εγγραφής: το μήνυμα στέλνει και στις δύο εφαρμογές.
      expect(note, endsWith('έλεγξε το ύψος στην InBody και στη Samsung Health: από το ύψος της InBody βγαίνουν λίπος και μύες.'));
    });

    test('ύψος εγγραφής ίσο με τα στοιχεία μου, δείκτης από άλλο ύψος: κανένα μήνυμα (πριν: «Η εφαρμογή InBody έχει ύψος 178»)', () {
      // Προφίλ Samsung Health 178 cm → δείκτης 26,51· η InBody και η εφαρμογή έχουν 180.
      expect(scaleHeightNote(recordCm: 180, weight: 84.0, bmi: 26.51, profileCm: 180), isNull);
    });

    test('χωρίς ύψος στην εγγραφή: από τον δείκτη, και δεν το αποδίδει μόνο στην InBody', () {
      final note = scaleHeightNote(weight: 84.0, bmi: 26.51, profileCm: 180);
      expect(note, startsWith('Η Samsung Health ή η InBody έχει ύψος 178 cm'));
      expect(note, isNot(contains('Η εφαρμογή InBody έχει')));
      expect(note, endsWith('έλεγξε το ύψος στην InBody και στη Samsung Health: από το ύψος της InBody βγαίνουν λίπος και μύες.'));
      expect(scaleHeightNote(weight: 84.0, bmi: 25.93, profileCm: 180), isNull, reason: 'διαφορά κάτω από 1 cm');
      expect(scaleHeightNote(weight: 84.0, bmi: 26.51), isNull, reason: 'χωρίς ύψος στα στοιχεία μου');
      expect(scaleHeightNote(profileCm: 180), isNull);
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
    test('ο κανόνας: ως 3, ή ως το 10% των ζυγίσεων της ζυγαριάς που δίνει τώρα η Samsung', () {
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

    test('K5-R-01: οι μέρες ΑΛΛΩΝ εφαρμογών δεν μεγαλώνουν το όριο (2 από 12 ζυγίσεις + 120 μέρες του ρολογιού: όλες μένουν)', () {
      // Νέο κινητό: η Samsung Health έχει 120 μέρες από άλλη εφαρμογή, και η InBody έχει ξαναστείλει μόνο τις 2 τελευταίες
      // από τις 12 ζυγίσεις. Με παρονομαστή και τις άλλες εφαρμογές (122) θα έφευγαν οι 10: 10 × 10 ≤ 122.
      final h = history(12, const []);
      final d = Dashboard.fromJson({
        'readAt': _ms(DateTime(2026, 11, 20, 12)),
        'body': [
          for (var i = 10; i < 12; i++) _w(DateTime(2026, 8, 1 + i), 85.0 - i * 0.05),
          for (var i = 0; i < 120; i++) _w(DateTime(2026, 4, 1 + i), 84.0, app: 'com.samsung.android.wear.shealth'),
        ],
      });
      expect(d.body.length, 2);
      expect(d.otherBodyDays.length, 120);
      applyRecentRead(h, d, plan: SourcePlan.samsungOnly);
      expect(h.values.where((m) => m.containsKey(K.weight)).length, 12);
    });

    test('56 από 60 και μετά πλήρης ανάγνωση: οι 4 φεύγουν (για τον κώδικα είναι «σβήστηκαν») και ξαναμπαίνουν όταν ξαναφανούν', () {
      final h = history(60, const []);
      final partial = Dashboard.fromJson({
        'readAt': _ms(DateTime(2026, 11, 20, 12)),
        'body': [for (var i = 0; i < 56; i++) _w(DateTime(2026, 8, 1 + i), 85.0 - i * 0.05)],
      });
      applyRecentRead(h, partial, plan: SourcePlan.samsungOnly);
      expect(h.values.where((m) => m.containsKey(K.weight)).length, 56);
      expect(h['2026-09-29']![K.steps], 7000, reason: 'οι άλλες τιμές της μέρας μένουν');
      applyRecentRead(h, read(60), plan: SourcePlan.samsungOnly);
      expect(h.values.where((m) => m.containsKey(K.weight)).length, 60);
      expect(h['2026-09-29']![K.weight], closeTo(85.0 - 59 * 0.05, 1e-9));
    });
  });

  // ------------------------------------------------------------------ K5A-03, K5A-04
  test('K5A-03 / K5A-04: τα παράθυρα επανανάγνωσης', () {
    expect(HealthStore.gapLeadDays, 3, reason: 'το κενό μετά από κλειστή εφαρμογή αρχίζει 3 μέρες πριν από την τελευταία γραμμένη');
    expect(ouraRecentDays, 7, reason: 'η Oura διορθώνει νύχτες και μετά τη 2η μέρα· πριν 3');
    expect(ouraRecentDays, lessThanOrEqualTo(ouraMissingDays));
  });

  test('K5A-03: τελευταία γραμμένη μέρα 2/12, άνοιγμα 5/1 → το κενό αρχίζει 29/11 (πριν: 2/12, και η 1/12 έμενε με μισά βήματα)', () {
    final last = DateTime(2026, 12, 2);
    expect(HealthStore.gapStart(last: last, today: DateTime(2027, 1, 5)), DateTime(2026, 11, 29));
    // Κενό που δεν είχε ολοκληρωθεί: κρατιέται η παλιότερη αρχή.
    expect(HealthStore.gapStart(last: last, today: DateTime(2027, 1, 5), prev: DateTime(2026, 11, 20)), DateTime(2026, 11, 20));
    expect(HealthStore.gapStart(last: last, today: DateTime(2027, 1, 5), prev: DateTime(2026, 12, 1)), DateTime(2026, 11, 29));
    // Ως 6 μέρες κλειστή: κανένα κενό (η κανονική ανάγνωση τις καλύπτει)· από 7: κενό.
    expect(HealthStore.gapStart(last: last, today: DateTime(2026, 12, 8)), isNull);
    expect(HealthStore.gapStart(last: last, today: DateTime(2026, 12, 9)), DateTime(2026, 11, 29));
    expect(HealthStore.gapStart(last: null, today: DateTime(2027, 1, 5)), isNull);
  });

  test('K5A-04: άδεια νύχτα μετά από προσωρινό σφάλμα: «δεν διαβάστηκε ακόμα» ως τη μέρα −6 (πριν −2), μετά «χωρίς δεδομένα»', () {
    final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 1));
    final now = DateTime(2026, 11, 20, 13);
    EmptyNight? r(int back, {String? error}) {
      final day = DateTime(2026, 11, 20 - back);
      return emptyNightReason(
          plan: plan, day: day, now: now, night: null, hasTokens: true, error: error, synced: DateTime(2026, 11, 20, 7));
    }

    for (var back = 0; back < ouraRecentDays; back++) {
      expect(r(back, error: 'network'), EmptyNight.notRead, reason: 'μέρα −$back');
    }
    expect(r(ouraRecentDays, error: 'network'), EmptyNight.noRing, reason: 'έξω από τις μέρες που ξαναδιαβάζονται');
    expect(r(3), EmptyNight.noRing, reason: 'χωρίς σφάλμα: όπως πριν');
  });

  test('K5M-05: η «μυϊκή μάζα» της Samsung είναι ποσοστό', () {
    expect(fieldLabel('MUSCLE_MASS'), contains('%'));
  });
}
