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
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/walk_stats.dart';

Session _walk({
  required List<List<int>> hr,
  List<List<int>> pz = const [],
  double meters = 0,
  int steps = 800,
  bool gps = true,
  int? hrGap,
  int? hrDel,
  int? lim,
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
}
