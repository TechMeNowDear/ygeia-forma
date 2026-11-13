// Round 2 · g2 · «Samsung Health → ιστορικό, ρυθμίσεις»: R2-B-1 (η ζώνη ώρας μιας εγγραφής ύπνου κρίνεται ΜΙΑ φορά,
// νύχτες αλλαγής ώρας), R2-B-2 (παλμοί μέρας στην περίοδο του Oura με κλειστή την άδεια «Ύπνος»), R2-B-3 (σύνοψη της
// επαναφοράς ρυθμίσεων). Όλα τα νούμερα είναι φανταστικά (δημόσιο repo)· οι αναμενόμενες τιμές βγήκαν από τον γραμμένο
// κανόνα (python με Europe/Athens), όχι από τον κώδικα. Τρέχουν με TZ=Europe/Athens, όπως το CI (ελέγχεται ρητά).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_store.dart';
import 'package:ygeia_forma/pages/settings.dart';
import 'package:ygeia_forma/plan_file.dart';
import 'package:ygeia_forma/sources.dart';

int _ms(DateTime t) => t.millisecondsSinceEpoch;

/// Ένα κομμάτι ύπνου όπως το στέλνει η γέφυρα: όλο ελαφρύς ύπνος (άρα έγκυρη διάρκεια), με «off» και, όπως η Kotlin από
/// το round 2, την αρχή/το τέλος ΟΛΗΣ της εγγραφής της Samsung («recStart»/«recEnd»).
Map<String, dynamic> _piece(DateTime start, DateTime end, {Object? off, (DateTime, DateTime)? rec}) => {
      'start': _ms(start),
      'end': _ms(end),
      'minutes': end.difference(start).inMinutes,
      'stages': [
        ['LIGHT', _ms(start), _ms(end)],
      ],
      if (off != null) 'off': off,
      if (rec != null) 'recStart': _ms(rec.$1),
      if (rec != null) 'recEnd': _ms(rec.$2),
    };

/// Η γραμμή της μέρας που έχει ώρα ύπνου (σχέδιο: μόνο ρολόι).
Map<String, double> _nightRow(List<Map<String, dynamic>> pieces, DateTime readAt) {
  final d = Dashboard.fromJson({'readAt': _ms(readAt), 'sleep': pieces});
  final first = DateTime.fromMillisecondsSinceEpoch(pieces.first['start'] as int);
  final rows = summarizeRange(d, DateTime(first.year, first.month, first.day - 1), readAt);
  return rows.values.where((r) => r.containsKey(K.bedtime)).single;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------------------------------------------
  group('R2-B-1: η ζώνη της εγγραφής κρίνεται μία φορά (σπίτι ή ταξίδι)', () {
    // Αλλαγή ώρας 24→25/10/2026 στις 01:00 UTC (04:00 θερινή → 03:00 χειμερινή). Ύπνος 23:30 → 07:00 στην Αθήνα.
    final octStart = DateTime.utc(2026, 10, 24, 20, 30);
    final octEnd = DateTime.utc(2026, 10, 25, 5, 0);
    final octRead = DateTime(2026, 10, 25, 12);
    // Αλλαγή ώρας 27→28/3/2027 στις 01:00 UTC (03:00 χειμερινή → 04:00 θερινή). Ύπνος 23:30 → 07:00 στην Αθήνα.
    final marStart = DateTime.utc(2027, 3, 27, 21, 30);
    final marEnd = DateTime.utc(2027, 3, 28, 4, 0);
    final marRead = DateTime(2027, 3, 28, 12);

    test('οι δοκιμές τρέχουν με TZ=Europe/Athens (αλλιώς δεν υπάρχει νύχτα αλλαγής ώρας)', () {
      expect(octStart.toLocal().timeZoneOffset.inMinutes, 180);
      expect(octEnd.toLocal().timeZoneOffset.inMinutes, 120);
      expect(marStart.toLocal().timeZoneOffset.inMinutes, 120);
      expect(marEnd.toLocal().timeZoneOffset.inMinutes, 180);
    });

    test('recordZone: ζώνη ίδια με του κινητού στην αρχή Ή στο τέλος = σπίτι (null)· αλλιώς η ίδια για όλη την εγγραφή', () {
      final a = octStart.toLocal();
      final b = octEnd.toLocal();
      expect(recordZone(180, a, b), isNull, reason: 'η ζώνη της αρχής (θερινή)');
      expect(recordZone(120, a, b), isNull, reason: 'η ζώνη του τέλους (χειμερινή)');
      expect(recordZone(120.0, a, b), isNull);
      expect(recordZone(60, a, b), 60, reason: 'Λονδίνο, θερινή');
      expect(recordZone(0, a, b), 0, reason: 'Λονδίνο, χειμερινή');
      expect(recordZone(-300, a, b), -300);
      expect(recordZone(330.4, a, b), 330);
      // Κανονική νύχτα του χειμώνα στην Αθήνα (+2): +3 είναι άλλη ζώνη (ταξίδι).
      final na = DateTime.utc(2026, 11, 9, 21, 30).toLocal();
      final nb = DateTime.utc(2026, 11, 10, 5).toLocal();
      expect(recordZone(120, na, nb), isNull);
      expect(recordZone(180, na, nb), 180);
      for (final bad in <Object?>[null, 'x', double.nan, double.infinity, 18 * 60 + 1, -(18 * 60 + 1)]) {
        expect(recordZone(bad, a, b), isNull, reason: '$bad');
      }
    });

    test('νύχτα 24→25/10/2026 στο σπίτι: 23:30 και 07:00 όποια άκρη κι αν δείχνει η ζώνη της Samsung (όπως το #100)', () {
      final plain = _nightRow([_piece(octStart, octEnd)], octRead);
      expect((plain[K.bedtime], plain[K.wake]), (330, 780), reason: '#100: χωρίς «off», η ώρα του κινητού');
      for (final off in [180, 120]) {
        for (final rec in [null, (octStart, octEnd)]) {
          final r = _nightRow([_piece(octStart, octEnd, off: off, rec: rec)], octRead);
          expect((r[K.bedtime], r[K.wake]), (330, 780), reason: 'off $off, rec ${rec != null}');
          expect(clockFromSix(r[K.bedtime]!), '23:30');
          expect(clockFromSix(r[K.wake]!), '07:00', reason: 'πριν (round 1): 08:00 με off 180');
        }
      }
    });

    test('νύχτα 27→28/3/2027 στο σπίτι: 23:30 και 07:00 και με τις δύο ζώνες', () {
      for (final off in [120, 180]) {
        final r = _nightRow([_piece(marStart, marEnd, off: off, rec: (marStart, marEnd))], marRead);
        expect((r[K.bedtime], r[K.wake]), (330, 780), reason: 'off $off (πριν: 06:00 ή 00:30)');
      }
    });

    test('εγγραφή σε δύο κομμάτια πάνω από την αλλαγή ώρας: η απόφαση με όλη την εγγραφή («recStart»/«recEnd»)', () {
      // Κομμάτι Α 23:30–03:30 (θερινή), κομμάτι Β 03:30–07:00 (χειμερινή), μία εγγραφή της Samsung 23:30–07:00.
      // Το Β είναι ΟΛΟ μετά την αλλαγή: μόνο με την αρχή της εγγραφής φαίνεται ότι το +3 είναι «σπίτι».
      final aEnd = DateTime.utc(2026, 10, 25, 0, 30);
      final bStart = DateTime.utc(2026, 10, 25, 1, 30);
      for (final off in [180, 120]) {
        final r = _nightRow([
          _piece(octStart, aEnd, off: off, rec: (octStart, octEnd)),
          _piece(bStart, octEnd, off: off, rec: (octStart, octEnd)),
        ], octRead);
        expect((r[K.bedtime], r[K.wake]), (330, 780), reason: 'off $off');
        expect(r[K.sleepMin], 450, reason: '240 + 210 λεπτά, μία νύχτα');
      }
    });

    test('ταξίδι (Λονδίνο, κινητό στην ώρα Αθήνας): η ώρα του τόπου και στις δύο άκρες', () {
      // Χειμώνας: 23:00 → 07:00 GMT (+0) = 01:00 → 09:00 στην Αθήνα.
      final ws = DateTime.utc(2026, 11, 9, 23);
      final we = DateTime.utc(2026, 11, 10, 7);
      final w = _nightRow([_piece(ws, we, off: 0, rec: (ws, we))], DateTime(2026, 11, 10, 12));
      expect((w[K.bedtime], w[K.wake]), (300, 780), reason: '23:00 και 07:00 στο Λονδίνο');
      // Καλοκαίρι: 23:00 → 07:00 BST (+1) = 01:00 → 09:00 στην Αθήνα (+3).
      final ss = DateTime.utc(2026, 7, 10, 22);
      final se = DateTime.utc(2026, 7, 11, 6);
      final s = _nightRow([_piece(ss, se, off: 60, rec: (ss, se))], DateTime(2026, 7, 11, 12));
      expect((s[K.bedtime], s[K.wake]), (300, 780));
      // Χωρίς τα νέα κλειδιά (παλιό αντίγραφο της ανάγνωσης): το ίδιο.
      final old = _nightRow([_piece(ws, we, off: 0)], DateTime(2026, 11, 10, 12));
      expect((old[K.bedtime], old[K.wake]), (300, 780));
    });

    test('κανονική νύχτα στο σπίτι με «off» +2: ίδια με χωρίς «off» (23:30, 07:00)', () {
      final s = DateTime.utc(2026, 11, 9, 21, 30);
      final e = DateTime.utc(2026, 11, 10, 5);
      final withOff = _nightRow([_piece(s, e, off: 120, rec: (s, e))], DateTime(2026, 11, 10, 12));
      final without = _nightRow([_piece(s, e)], DateTime(2026, 11, 10, 12));
      expect((withOff[K.bedtime], withOff[K.wake]), (330, 780));
      expect(withOff, without);
    });

    test('η ανανέωση δεν αλλάζει τη σωστή αποθηκευμένη ώρα της νύχτας αλλαγής ώρας', () {
      final k = dateKey(DateTime(2026, 10, 25));
      for (final off in [180, 120]) {
        final h = <String, Map<String, double>>{
          k: {K.sleepMin: 510, K.bedtime: 330, K.wake: 780, K.steps: 1000},
        };
        final j = {
          'ok': true,
          'readAt': _ms(octRead),
          'granted': 10,
          'total': 10,
          'sleep': [_piece(octStart, octEnd, off: off, rec: (octStart, octEnd))],
        };
        final p = parseDashboardSync(jsonEncode(j), plan: SourcePlan.samsungOnly);
        applyRecentRead(h, p.data!,
            plan: SourcePlan.samsungOnly,
            sleepFailed: p.sleepFailed,
            heartFailed: p.heartFailed,
            rows: p.rows,
            keepKeys: p.keep);
        expect(h[k]![K.bedtime], 330, reason: 'off $off');
        expect(h[k]![K.wake], 780, reason: 'off $off (πριν: 840 = 08:00 με off 180, ή bedtime 270 με off 120)');
        expect(h[k]![K.sleepMin], 510);
      }
    });

    test('η γέφυρα στέλνει την αρχή και το τέλος όλης της εγγραφής μαζί με το «off» (πηγαίος κώδικας Kotlin)', () {
      final reader = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/DashboardReader.kt').readAsStringSync();
      expect(reader, contains('val recEnd = ms(p.endTime) ?: start'));
      expect(reader, contains('DataRules.splitSleep(start, recEnd,'));
      expect(reader, contains('o.put("off", off)'));
      expect(reader, contains('o.put("recStart", start).put("recEnd", recEnd)'));
    });
  });

  // -------------------------------------------------------------------------------------------------------------
  group('R2-B-2: κλειστή άδεια «Ύπνος» στην περίοδο του Oura δεν παγώνει τους «Παλμούς ξύπνιος»', () {
    final today = DateTime(2026, 11, 10);
    DateTime at(int h, int m) => DateTime(today.year, today.month, today.day, h, m);
    final ouraPlan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 10, 1));
    // Η νύχτα του Oura που τελειώνει σήμερα το πρωί (μόνο ως ώρες, για να εξαιρεθεί από τους παλμούς της μέρας).
    final windows = SleepWindows([(DateTime(2026, 11, 9, 23), at(7, 0))], {
      '2026-11-10': (DateTime(2026, 11, 9, 23), at(7, 0)),
    });
    // Ανάγνωση στις 20:00 ΧΩΡΙΣ το κλειδί «sleep» (κλειστή άδεια), με παλμούς 70 από τις 08:00 ως τις 16:00 (480 λεπτά,
    // πάνω από τα 360 που χρειάζεται η τιμή της μέρας), καμία κίνηση (0 βήματα) → ξύπνιος 70, ηρεμία 70.
    Map<String, dynamic> noSleepJson() => {
          'ok': true,
          'readAt': _ms(at(20, 0)),
          'granted': 10,
          'total': 10,
          'heart': [
            for (var t = at(8, 0); t.isBefore(at(16, 0)); t = t.add(const Duration(minutes: 4)))
              [_ms(t), _ms(t.add(const Duration(minutes: 4))), 70, 67, 73],
          ],
          'exercise': <Object>[],
          'stepsMin': [
            [_ms(at(0, 0)), 0],
          ],
        };

    test('dropWatchNightDayHeart: μόνο οι μέρες με νύχτα του ρολογιού (της μέρας ή της επόμενης)', () {
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 1));
      Map<String, double> row() => {K.dayHr: 70, K.restHr: 60, K.walkHr: 95, K.steps: 1000};
      final rows = {for (final d in ['2026-10-30', '2026-10-31', '2026-11-01', '2026-11-02']) d: row()};
      dropWatchNightDayHeart(rows, plan);
      expect(rows['2026-10-30'], {K.steps: 1000}, reason: 'νύχτα του ρολογιού');
      expect(rows['2026-10-31'], {K.steps: 1000}, reason: 'η νύχτα της μέρας είναι του ρολογιού (η επόμενη του Oura)');
      expect(rows['2026-11-01'], row(), reason: 'και οι δύο νύχτες του Oura');
      expect(rows['2026-11-02'], row());
      final all = {'2026-11-02': row()};
      dropWatchNightDayHeart(all, SourcePlan.samsungOnly);
      expect(all['2026-11-02'], {K.steps: 1000}, reason: 'σχέδιο μόνο ρολόι: όπως στο round 1 (S3-7)');
    });

    test('σχέδιο Oura, άδεια «Ύπνος» κλειστή: οι παλμοί της μέρας γράφονται κανονικά', () {
      final j = noSleepJson();
      final p = parseDashboardSync(jsonEncode(j), plan: ouraPlan, windows: windows);
      expect(p.data!.sleepOk, isFalse, reason: 'η δοκιμή περνά από τον δρόμο «ύπνος αδιάβαστος»');
      final h = <String, Map<String, double>>{};
      applyRecentRead(h, p.data!,
          plan: ouraPlan,
          windows: windows,
          sleepFailed: p.sleepFailed,
          heartFailed: p.heartFailed,
          rows: p.rows,
          keepKeys: p.keep);
      expect(h[dateKey(today)]![K.dayHr], 70, reason: 'πριν: δεν γραφόταν ποτέ όσο η άδεια ήταν κλειστή');
      expect(h[dateKey(today)]![K.restHr], 70);
      // Και χωρίς έτοιμες γραμμές (υπολογίζονται μέσα στο applyRecentRead).
      final h2 = <String, Map<String, double>>{};
      applyRecentRead(h2, Dashboard.fromJson(j), plan: ouraPlan, windows: windows);
      expect(h2[dateKey(today)]![K.dayHr], 70);
    });

    test('σχέδιο μόνο ρολόι, άδεια «Ύπνος» κλειστή: οι αποθηκευμένοι παλμοί μέρας μένουν (S3-7)', () {
      final h = <String, Map<String, double>>{
        dateKey(today): {K.dayHr: 62, K.restHr: 55},
      };
      final d = Dashboard.fromJson(noSleepJson());
      applyRecentRead(h, d, plan: SourcePlan.samsungOnly);
      expect(h[dateKey(today)]![K.dayHr], 62);
      expect(h[dateKey(today)]![K.restHr], 55);
      // Ακόμα κι αν μια γραμμή φέρει παλμούς μέρας για μέρα του ρολογιού.
      applyRecentRead(h, d, plan: SourcePlan.samsungOnly, rows: {
        dateKey(today): {K.dayHr: 50.0, K.restHr: 45.0, K.steps: 3.0},
      });
      expect(h[dateKey(today)], {K.dayHr: 62.0, K.restHr: 55.0, K.steps: 3.0});
    });
  });

  // -------------------------------------------------------------------------------------------------------------
  group('R2-B-3: η σύνοψη της επαναφοράς λέει «δεν άλλαξαν» μόνο όταν δεν άλλαξαν', () {
    void install({required String load, required bool saveOk}) {
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(const MethodChannel('ygeia/samsung'), (call) async {
        switch (call.method) {
          case 'loadPrefs':
            return load;
          case 'savePrefs':
            return saveOk ? '{"ok":true}' : '{"ok":false,"kind":"write"}';
        }
        return '{"ok":true}';
      });
      m.setMockMethodCallHandler(const MethodChannel('ygeia/oura'), (call) async => null);
      m.setMockMethodCallHandler(const MethodChannel('ygeia/errors'), (call) async => null);
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('ygeia/samsung'), null);
    });

    HealthStore store() => HealthStore()
      ..planFile = MemoryPlanFile(null)
      ..ouraNightsFile = MemoryNightsFile();

    const kitchen = {'pans': ['Τηγάνι δοκιμής'], 'scale': true};

    test('restorePrefsSummary: οι τέσσερις περιπτώσεις', () {
      const notes = ['Σημείωση δοκιμής.'];
      expect(restorePrefsSummary(ok: true, loaded: true, unsaved: false, notes: notes), notes);
      expect(restorePrefsSummary(ok: false, loaded: false, unsaved: false, notes: const []), ['Οι ρυθμίσεις δεν άλλαξαν.']);
      expect(restorePrefsSummary(ok: false, loaded: false, unsaved: true, notes: const []), ['Οι ρυθμίσεις δεν άλλαξαν.'],
          reason: 'ένα παλιό «δεν αποθηκεύτηκε» δεν σημαίνει ότι μπήκε η επαναφορά');
      expect(restorePrefsSummary(ok: false, loaded: true, unsaved: true, notes: notes), [restorePrefsUnsavedText, ...notes]);
      expect(restorePrefsSummary(ok: false, loaded: true, unsaved: false, notes: notes), notes,
          reason: 'γράφτηκαν στο μεταξύ (π.χ. με τις πηγές ύπνου)');
      expect(restorePrefsUnsavedText, contains('«Δοκίμασε ξανά»'));
    });

    test('γεμάτος χώρος: οι ρυθμίσεις μπαίνουν στη μνήμη, η σύνοψη δεν λέει «δεν άλλαξαν»', () async {
      install(load: '{"historyVersion":4}', saveOk: false);
      final s = store();
      await s.loadPrefs();
      expect(s.prefsLoaded, isTrue);
      final ok = await s.restorePrefs({'kitchen': kitchen});
      expect(ok, isFalse);
      expect(s.prefsSaveError, isTrue, reason: 'η κάρτα «Δοκίμασε ξανά» της Σήμερα');
      expect(s.prefs.kitchen, kitchen, reason: 'η επαναφορά φαίνεται στην οθόνη');
      final lines = restorePrefsSummary(ok: ok, loaded: true, unsaved: s.prefsSaveError, notes: const []);
      expect(lines, [restorePrefsUnsavedText]);
      expect(lines.join(' '), isNot(contains('δεν άλλαξαν')));
    });

    test('ρυθμίσεις που δεν διαβάστηκαν: τίποτα δεν αλλάζει και η σύνοψη το λέει', () async {
      install(load: '{"ok":false,"kind":"read"}', saveOk: true);
      final s = store();
      await s.loadPrefs();
      expect(s.prefsLoaded, isFalse);
      final ok = await s.restorePrefs({'kitchen': kitchen});
      expect(ok, isFalse);
      expect(s.prefs.kitchen, isNull);
      expect(restorePrefsSummary(ok: ok, loaded: false, unsaved: s.prefsSaveError, notes: const []),
          ['Οι ρυθμίσεις δεν άλλαξαν.']);
    });
  });
}
