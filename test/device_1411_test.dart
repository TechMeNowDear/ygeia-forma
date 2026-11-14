// Δοκιμή στις συσκευές 14/11 (πρώτο περπάτημα από το ρολόι, μέσα στο σπίτι, χωρίς όριο γιατρού):
// 1. «0,00 km» με 812 βήματα (GPS ανοιχτό, χωρίς σήμα) → «—», όπως η κάρτα την ώρα του περπατήματος.
// 2. «Οι παλμοί έλειπαν έως 22 δευτερόλεπτα» (κεχριμπάρι) ενώ υπήρχε τιμή σχεδόν κάθε δευτερόλεπτο: τα 22″ ήταν το κενό
//    ανάμεσα στις παραδόσεις του ρολογιού. Χωρίς όριο κρίνεται από τις ίδιες τις τιμές.
// 3. «πάνω όριο (134)» στο τεστ ομιλίας, ενώ το ρολόι λέει «χωρίς όριο» → «πάνω άκρο της ζώνης».
// 4. Η κάρτα του τεστ ομιλίας χωρίς ερώτηση κρύβεται (απόφαση χρήστη 14/11).
// Συνθετικά δεδομένα (όχι του χρήστη).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/pages/training/hr_widgets.dart';
import 'package:ygeia_forma/pages/training/training_page.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/data.dart' show todayCards;
import 'package:ygeia_forma/pages/settings.dart' show voiceSettingText;
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/walk_stats.dart';
import 'package:ygeia_forma/training/wear_link.dart' show watchPlan;
import 'package:ygeia_forma/training/zone.dart' show zoneHoldSec;

Session _walk({
  required List<List<int>> hr,
  List<List<int>> pz = const [],
  double meters = 0,
  int steps = 800,
  bool gps = true,
  int? hrGap,
  int? hrDel,
  int? lim,
  double? est,
}) =>
    Session(
      id: 'w1',
      workout: 'walk',
      name: 'Περπάτημα',
      programId: '',
      start: DateTime(2026, 11, 1, 18),
      end: DateTime(2026, 11, 1, 18, 7, 8),
      cardioMinutes: 7,
      cardioSec: 428,
      meters: meters,
      metersEst: est,
      steps: steps,
      gps: gps,
      hr: hr,
      pauses: pz,
      hrMode: '5s',
      hrGap: hrGap,
      hrDel: hrDel,
      limit: lim,
      source: 'watch',
    );

/// Τιμή κάθε 1–2″ από το 2″ ως το 428″, με ένα κενό 4″ στο 121″ (όπως έρχονται από το ρολόι ανά 5″ ζωντανά).
List<List<int>> _dense() {
  final out = <List<int>>[];
  var t = 2;
  while (t <= 428) {
    out.add([t, 110]);
    t += t == 121 ? 4 : (t % 7 == 0 ? 2 : 1);
  }
  if (out.last[0] != 428) out.add([428, 112]);
  return out;
}

void main() {
  group('1. απόσταση χωρίς σήμα GPS', () {
    test('812 βήματα, 0 m: «—», όχι «0,00»· η κάρτα και η σύνοψη το ίδιο', () {
      expect(kmValue(_walk(hr: const [], meters: 0, steps: 812)), isNull);
      expect(kmValue(_walk(hr: const [], meters: 9, steps: 812)), isNull);
      expect(kmValue(_walk(hr: const [], meters: 2310, steps: 3000)), '2,31');
      expect(recentWorkoutLine(_walk(hr: const [], meters: 0, steps: 812)), isNot(contains('km')));
    });

    test('η σύνοψη: «από βήματα» μόνο δίπλα σε αριθμό', () {
      final page = File('lib/pages/training/session_page.dart').readAsStringSync();
      expect(page, contains("distanceFromSteps(s) && kmValue(s) != null ? 'km (από βήματα)' : 'km'"));
    });
  });

  group('2. κενό στους παλμούς: τιμές, όχι παραδόσεις', () {
    test('hrSampleGap: αρχή, ανάμεσα, τέλος, χωρίς τις παύσεις', () {
      expect(hrSampleGap(const [], const []), isNull);
      expect(hrSampleGap(_dense(), const [], endSec: 428), 4);
      // Αργή πρώτη τιμή: μετρά από την αρχή.
      expect(hrSampleGap([[30, 100], [31, 100]], const []), 30);
      // Οι τιμές σταμάτησαν στο 100″, το περπάτημα τελείωσε στο 150″.
      expect(hrSampleGap([for (var t = 0; t <= 100; t++) [t, 100]], const [], endSec: 150), 50);
      // Κενό 60″ μέσα σε παύση 100–158″: μένουν 2″.
      expect(
        hrSampleGap([for (var t = 0; t <= 100; t++) [t, 100], for (var t = 160; t <= 200; t++) [t, 100]], const [[100, 158]]),
        2,
      );
      // Σειρά άσχετη.
      expect(hrSampleGap([[5, 1], [1, 1], [3, 1]], const []), 2);
    });

    test('χωρίς όριο: κρίνεται από τις τιμές', () {
      final ok = hrGapText(22, '5s', 280, false, sampleGap: 4);
      expect(ok.$1, 'Οι παλμοί μετρήθηκαν συνεχώς (μεγαλύτερο κενό 4 δευτερόλεπτα).');
      expect(ok.$2, isFalse);
      final bad = hrGapText(22, '5s', 280, false, sampleGap: 40);
      expect(bad.$1, 'Οι παλμοί έλειπαν έως 40 δευτερόλεπτα.');
      expect(bad.$2, isTrue);
      expect(hrGapText(22, '5s', 280, false, sampleGap: 1800).$1, 'Οι παλμοί έλειπαν έως 30 λεπτά.');
    });

    test('με όριο: μένει το κενό των παραδόσεων (πόσο άργησε η ειδοποίηση)· όλα μαζί: όπως πριν', () {
      final r = hrGapText(22, '5s', 280, true, sampleGap: 4);
      expect(r.$1, startsWith('Μεγαλύτερο κενό στους παλμούς: 22 δευτερόλεπτα'));
      expect(r.$2, isTrue);
      expect(hrGapText(22, '5s', 1, false, sampleGap: 4).$1, 'Οι παλμοί ήρθαν όλοι μαζί, μία φορά.');
      // Χωρίς τιμές (παλιά σύνοψη): όπως πριν.
      expect(hrGapText(22, '5s', 280, false).$1, 'Οι παλμοί έλειπαν έως 22 δευτερόλεπτα.');
    });

    testWidgets('η κάρτα παλμών: όχι κεχριμπάρι «έλειπαν» όταν οι τιμές είναι συνεχείς', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: SingleChildScrollView(child: HrCard(session: _walk(hr: _dense(), hrGap: 22, hrDel: 280)))),
      ));
      expect(find.textContaining('έλειπαν'), findsNothing);
      expect(find.text('Οι παλμοί μετρήθηκαν συνεχώς (μεγαλύτερο κενό 4 δευτερόλεπτα).'), findsOneWidget);
    });

    testWidgets('η κάρτα παλμών: πραγματικό κενό → κεχριμπάρι', (tester) async {
      final hr = [for (var t = 2; t <= 200; t++) [t, 110], for (var t = 260; t <= 428; t++) [t, 112]];
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: SingleChildScrollView(child: HrCard(session: _walk(hr: hr, hrGap: 61, hrDel: 280)))),
      ));
      expect(find.text('Οι παλμοί έλειπαν έως 60 δευτερόλεπτα.'), findsOneWidget);
    });
  });

  group('3. «πάνω άκρο της ζώνης», όχι «πάνω όριο»', () {
    test('τα κείμενα της ζώνης', () {
      final src = File('lib/pages/training/zone_widgets.dart').readAsStringSync();
      final strings = RegExp(r"'[^'\n]*'").allMatches(src).map((m) => m.group(0)!).join('\n');
      expect(strings, isNot(contains('πάνω όριο')));
      expect(strings, contains('Στο πάνω άκρο της ζώνης μιλάς με προτάσεις'));
    });
  });

  group('4. τεστ ομιλίας: καμία κάρτα όταν δεν υπάρχει ερώτηση (απόφαση χρήστη 14/11)', () {
    test('η κάρτα «δεν έμειναν κοντά…» δεν υπάρχει πια· το shows() το κρίνει', () {
      final src = File('lib/pages/training/zone_widgets.dart').readAsStringSync();
      expect(src, isNot(contains('talk-test-not-near')));
      expect(src, isNot(contains('Η ερώτηση έρχεται σε περπάτημα που φτάνει εκεί')));
      expect(src, contains('if (talkSeconds(s, s.zoneHi!).near < talkNearMinSec) return false;'));
    });
  });

  group('5. απόσταση από τα βήματα (ρολόι από #114)', () {
    test('μέσα στο σπίτι: «≈» από τα βήματα· έξω: GPS· ίδιος κανόνας με το ρολόι', () {
      // 812 βήματα × 0,72 ≈ 584 m, GPS ανοιχτό χωρίς σήμα.
      final indoor = _walk(hr: const [], meters: 0, steps: 812, est: 584);
      expect(kmValue(indoor), '≈ 0,58');
      expect(distanceFromSteps(indoor), isTrue);
      // Ρυθμός από την εκτίμηση: 428″ για 0,584 km ≈ 733″/km, με «≈» (distanceFromSteps).
      expect(paceSecPerKm(indoor), (428 / 0.584).round());
      // Έξω: GPS 2.180 m, εκτίμηση 2.088: το GPS, χωρίς «≈».
      final out = _walk(hr: const [], meters: 2180, steps: 2900, est: 2088);
      expect(kmValue(out), '2,18');
      expect(distanceFromSteps(out), isFalse);
      // Θόρυβος του GPS (6 m): η εκτίμηση.
      expect(kmValue(_walk(hr: const [], meters: 6, steps: 812, est: 584)), '≈ 0,58');
      // GPS που έπιασε αργά (200 από 2.088): η εκτίμηση.
      expect(kmValue(_walk(hr: const [], meters: 200, steps: 2900, est: 2088)), '≈ 2,09');
      // Παλιό ρολόι (χωρίς «mest»): «—».
      expect(kmValue(_walk(hr: const [], meters: 0, steps: 812)), isNull);
      // Ποτέ στην Πρόοδο (μόνο GPS ≥ 500 m).
      expect(indoor.toJson()['mest'], 584);
      expect(Session.fromJson(indoor.toJson()).metersEst, 584);
    });

    test('ζωντανά: ίδιος κανόνας', () {
      expect(liveMeters({'m': 0, 'mest': 584, 'gps': true}), (meters: 584.0, approx: true));
      expect(liveMeters({'m': 2180, 'mest': 2088, 'gps': true}), (meters: 2180.0, approx: false));
      expect(liveMeters({'m': 0}), isNull);
      expect(liveMeters({'m': 1500, 'gps': false}), (meters: 1500.0, approx: true));
    });

    test('μήκος βήματος: από τα περπατήματα με GPS, αλλιώς από το ύψος', () {
      Session w(int day, {double m = 2000, int steps = 2800, bool gps = true}) => Session(
          id: 'w$day', workout: 'walk', name: 'Π', programId: '', start: DateTime(2026, 11, day, 18), end: DateTime(2026, 11, day, 18, 30),
          cardioMinutes: 30, meters: m, steps: steps, gps: gps);
      // Δύο περπατήματα με GPS: (2.000 + 2.100) / (2.800 + 2.900).
      expect(strideFor([w(1), w(2, m: 2100, steps: 2900)], heightCm: 180, sex: 'm'), closeTo(4100 / 5700, 1e-9));
      // Χωρίς GPS (ή πολύ μικρό): από το ύψος, 1,80 × 0,415.
      expect(strideFor([w(1, gps: false), w(2, m: 300)], heightCm: 180, sex: 'm'), closeTo(0.747, 1e-9));
      expect(strideFor(const [], heightCm: 170, sex: 'f'), closeTo(1.70 * 0.413, 1e-9));
      expect(strideFor(const []), isNull);
      // GPS που «πήδηξε» (1,5 m το βήμα): αγνοείται.
      expect(strideFor([w(1, m: 4200, steps: 2800)], heightCm: 180, sex: 'm'), closeTo(0.747, 1e-9));
    });

    test('πρόγραμμα προς το ρολόι: φωνή και μήκος βήματος· γράφονται στο αρχείο', () async {
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => DateTime(2026, 11, 14, 17))..ready = true;
      var plan = watchPlan(t, DateTime(2026, 11, 14, 17), (x) => x);
      expect(plan['voice'], isTrue);
      expect(plan.containsKey('stride'), isFalse);
      t.setVoice(false);
      t.setStride(0.7234);
      plan = watchPlan(t, DateTime(2026, 11, 14, 17), (x) => x);
      expect(plan['voice'], isFalse);
      expect(plan['stride'], 0.72);
      final j = t.toJson();
      expect(j['voice'], isFalse);
      expect(j['stride'], 0.72);
      final back = TrainingStore(io: MemoryTrainingIO(), clock: () => DateTime(2026, 11, 14, 17))..replaceAll(j);
      expect(back.voice, isFalse);
      expect(back.stride, 0.72);
      // Μικρή αλλαγή (κάτω από 1 cm): δεν ξαναγράφεται.
      t.setStride(0.7249);
      expect(t.stride, 0.72);
    });

    test('αποτέλεσμα του ρολογιού: «mest»', () {
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => DateTime(2026, 11, 14, 17))..ready = true;
      final start = DateTime(2026, 11, 14, 16, 11).millisecondsSinceEpoch;
      t.importWatch({
        'v': 1, 'kind': 'cardio', 'id': 'walk$start', 'w': 'walk', 'name': 'Περπάτημα', 'start': start, 'end': start + 428000,
        'cardio': {'activity': 'walk', 'sec': 428, 'm': 0.0, 'steps': 812, 'gps': true, 'mest': 584},
      });
      final s = t.sessions.single;
      expect(s.metersEst, 584);
      expect(kmValue(s), '≈ 0,58');
    });
  });

  group('6. ζώνη και φωνή', () {
    test('5 δευτερόλεπτα· διακόπτης φωνής στις Ρυθμίσεις', () {
      expect(zoneHoldSec, 5);
      expect(voiceSettingText, contains('«Εκτός εύρους»'));
      final settings = File('lib/pages/settings.dart').readAsStringSync();
      expect(settings, contains("key: const ValueKey('settings-voice-switch')"));
    });
  });

  group('7. Σήμερα: Κίνηση, Καρδιά, Σώμα πριν από τη Διατροφή (αίτημα χρήστη 14/11)', () {
    test('νέες κάρτες, ανοιχτές από προεπιλογή', () {
      final keys = [for (final c in todayCards) c.key];
      for (final k in ['exweek', 'awake', 'fat']) {
        expect(keys, contains(k));
        expect(todayCards.firstWhere((c) => c.key == k).defaultOn, isTrue);
      }
    });
    test('η σειρά: Κίνηση, Καρδιά, Σώμα, Διατροφή', () {
      final src = File('lib/pages/today.dart').readAsStringSync();
      final i = src.indexOf("...section('Κίνηση', move),");
      final j = src.indexOf("...section('Καρδιά', heart),");
      final k = src.indexOf("...section('Σώμα', body),");
      final f = src.indexOf("if (foodCard != null) ...[const SectionHeader('Διατροφή'), foodCard],");
      expect(i > 0 && i < j && j < k && k < f, isTrue);
      // Παλμοί ξύπνιος: μόνο ολοκληρωμένη μέρα (όπως στην Καρδιά), με το «συνήθως».
      expect(src, contains("title: datedTitle('Παλμοί ξύπνιος', last, now),"));
    });
  });
}
