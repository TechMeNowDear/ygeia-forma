// Premium επανασχεδιασμός (σχέδια 9/11): οδηγός σχεδίασης (χρώμα με σημασία, μορφές), μετακινήσεις οθονών.
// Όλα τα νούμερα είναι δοκιμαστικά.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/theme.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('Ρυθμός και χρονόμετρο (σχέδια 9/11)', () {
    test('«11:15 /km» παντού', () {
      expect(paceText(675), '11:15 /km');
      expect(paceText(600), '10:00 /km');
      expect(paceText(61), '1:01 /km');
    });

    test('στρογγυλεύει πριν χωρίσει: 659,5″ → «11:00», ποτέ «10:60»', () {
      expect(paceText(659.5), '11:00 /km');
      expect(paceText(659.4), '10:59 /km');
      expect(paceText(1319 / 2), '11:00 /km');
    });

    test('χρονόμετρο λεπτά:δευτερόλεπτα', () {
      expect(clock(1471), '24:31');
      expect(clock(3730), '1:02:10');
      expect(clock(59.6), '1:00');
      expect(clock(0), '0:00');
    });
  });

  group('Χρώμα με σημασία (σχέδια 9/11)', () {
    const all = [...Aigaio.dayThemes, ...Aigaio.nightThemes];

    test('το «χειρότερα» έχει δικό του κόκκινο, ποτέ ίδιο με την Άσκηση ή την καρδιά', () {
      expect(Aigaio.light.bad, const Color(0xFFB42318));
      for (final t in all) {
        expect(t.bad, isNot(t.exercise), reason: '${t.name} ${t.dark}');
        expect(t.bad, isNot(t.exerciseSolid), reason: '${t.name} ${t.dark}');
        expect(t.bad, isNot(t.heart), reason: '${t.name} ${t.dark}');
        expect(t.warn, isNot(t.bad), reason: '${t.name} ${t.dark}');
      }
    });

    test('κόκκινο και κεχριμπάρι διαβάζονται (≥ 4,5:1) σε κάρτα και στο κουτί προσοχής', () {
      for (final t in all) {
        expect(contrast(t.bad, t.card), greaterThanOrEqualTo(4.5), reason: 'bad ${t.name} ${t.dark}');
        expect(contrast(t.warn, t.card), greaterThanOrEqualTo(4.5), reason: 'warn ${t.name} ${t.dark}');
        expect(contrast(t.warn, t.warnBg), greaterThanOrEqualTo(4.5), reason: 'warn/warnBg ${t.name} ${t.dark}');
        expect(contrast(t.text, t.warnBg), greaterThanOrEqualTo(4.5), reason: 'text/warnBg ${t.name} ${t.dark}');
      }
    });
  });
}
