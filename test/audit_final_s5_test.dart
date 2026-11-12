// Τελικός έλεγχος, Συμβούλιο 5 (UI/UX, εργονομία στο γυμναστήριο, αναδιπλούμενες οθόνες, ασφάλεια).
// U-3: γράμματα και εικονίδια πάνω σε πράσινο και κόκκινο διαβάζονται σε κάθε θέμα (πριν, στα σκούρα, λευκό πάνω σε
//      ανοιχτό πράσινο: αντίθεση 1,3–2,8:1). U-1: το ✓ του σετ είναι 48 dp. U-2: το τέλος του διαλείμματος στο κινητό
//      έρχεται με ξυπνητήρι που ξυπνά το κινητό, χωρίς νέα άδεια. Όλα τα νούμερα είναι δοκιμαστικά.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/pages/training/session_page.dart';
import 'package:ygeia_forma/theme.dart';

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18, 0);

void main() {
  group('Συμβούλιο 5 · U-3: γράμματα πάνω σε πράσινο και κόκκινο, σε κάθε θέμα', () {
    test('η αντίθεση υπολογίζεται με τον τύπο WCAG', () {
      expect(Aigaio.contrast(Colors.white, Colors.black), closeTo(21, 0.01));
      expect(Aigaio.contrast(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(Aigaio.contrast(Colors.white, Colors.white), closeTo(1, 0.001));
      // #767676 πάνω σε λευκό: το γνωστό όριο 4,54:1
      expect(Aigaio.contrast(const Color(0xFF767676), Colors.white), closeTo(4.54, 0.01));
    });

    test('το χρώμα που διαλέγει η inkOn διαβάζεται (αντίθεση τουλάχιστον 4,5:1) σε όλα τα θέματα', () {
      for (final t in [...Aigaio.dayThemes, ...Aigaio.nightThemes]) {
        for (final (name, solid) in [('good', t.good), ('bad', t.bad)]) {
          expect(Aigaio.contrast(Aigaio.inkOn(solid), solid), greaterThanOrEqualTo(4.5), reason: '${t.id} $name');
        }
      }
    });

    test('στα θέματα ημέρας μένει το λευκό· στα σκούρα το λευκό δεν διαβαζόταν και τώρα μπαίνει σκούρο', () {
      for (final t in Aigaio.dayThemes) {
        expect(Aigaio.inkOn(t.good), Colors.white, reason: t.id);
        expect(Aigaio.inkOn(t.bad), Colors.white, reason: t.id);
      }
      for (final t in Aigaio.nightThemes) {
        // το σφάλμα που διορθώθηκε: λευκό πάνω στο ανοιχτό πράσινο ή κόκκινο των σκούρων θεμάτων
        expect(Aigaio.contrast(Colors.white, t.good), lessThan(3), reason: '${t.id}: λευκό στο πράσινο');
        expect(Aigaio.contrast(Colors.white, t.bad), lessThan(3), reason: '${t.id}: λευκό στο κόκκινο');
        expect(Aigaio.inkOn(t.good), Aigaio.ink, reason: t.id);
        expect(Aigaio.inkOn(t.bad), Aigaio.ink, reason: t.id);
      }
    });
  });

  group('Συμβούλιο 5 · οθόνη προπόνησης στα σκούρα θέματα', () {
    for (final palette in Aigaio.nightThemes) {
      testWidgets('«Έγινε» και ✓ διαβάζονται στο θέμα «${palette.id}»· το ✓ είναι 48 dp', (tester) async {
        final store = sampleTraining(now);
        store.start(store.program!.workout('A')!);
        await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark, palette), home: SessionPage(training: store)));
        await tester.pump();
        const key = ValueKey('sess-tick-0');
        // το τρέχον σετ: το κουμπί «Έγινε»
        final done = tester.widget<FilledButton>(find.byKey(key));
        final fg = done.style!.foregroundColor!.resolve(<WidgetState>{})!;
        expect(fg, Aigaio.inkOn(palette.good));
        expect(Aigaio.contrast(fg, palette.good), greaterThanOrEqualTo(4.5));
        expect(tester.getSize(find.byKey(key)).height, greaterThanOrEqualTo(48));
        await tester.ensureVisible(find.byKey(key));
        await tester.pump();
        await tester.tap(find.byKey(key));
        await tester.pump();
        // το σετ έγινε: το τετράγωνο ✓ του
        expect(store.current!.items[0].log[0].done, isTrue);
        expect(tester.getSize(find.byKey(key)), const Size(48, 48));
        final icon = tester.widget<Icon>(find.descendant(of: find.byKey(key), matching: find.byType(Icon)));
        expect(icon.color, Aigaio.inkOn(palette.good));
        // κλείνει η οθόνη (σταματά το ρολόι του δευτερολέπτου)
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }
  });

  group('Συμβούλιο 5 · U-2: το διάλειμμα στο κινητό', () {
    test('το τέλος έρχεται με ξυπνητήρι που ξυπνά το κινητό· η δόνηση είναι «ξυπνητήρι»· καμία νέα άδεια', () {
      const dir = 'android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma';
      final bridge = File('$dir/TrainingBridge.kt').readAsStringSync();
      expect(bridge, contains('AlarmManager.ELAPSED_REALTIME_WAKEUP'));
      expect(bridge, contains('AlarmManager.OnAlarmListener'));
      expect(bridge, contains('VibrationAttributes.USAGE_ALARM'));
      expect(bridge, contains('TrainingRules.restTrigger'));
      // ένα διάλειμμα που ακυρώθηκε δεν χτυπά, και το ξυπνητήρι του ακυρώνεται
      expect(bridge, contains('if (pending !== this) return'));
      expect(bridge, contains('?.cancel(l)'));
      // Η άδεια «Ξυπνητήρια και υπενθυμίσεις» ΔΕΝ δηλώνεται: θα ήταν απόφαση του χρήστη (απόφαση 1 του Συμβουλίου 5).
      final manifest = File('tools/android/patch_manifest.py').readAsStringSync();
      expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
      expect(manifest, isNot(contains('USE_EXACT_ALARM')));
    });
  });
}
