import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/food/food_model.dart';

void main() {
  final food = {
    'id': 'M1',
    'name': 'Γιαούρτι 2%',
    'cat': 'Τα προϊόντα μου',
    'source': 'Ετικέτα',
    'n': {'kcal': 70, 'protein': 10, 'salt': {'lt': 0.1}},
  };
  final entry = {
    'id': 'E1',
    'day': '2026-11-01',
    'meal': 'lunch',
    'food': food,
    'grams': 170,
    'time': DateTime(2026, 11, 1, 14).millisecondsSinceEpoch,
  };

  test('Εξαγωγή → επαναφορά: ίδια δεδομένα', () {
    final text = buildBackup(
      foodLog: [entry],
      myFoods: [food],
      prefs: {'kitchen': {'a': 1}, 'cards': {'sleep': true}, 'themeMode': 'dark', 'backfillFrom': '2025-11-01'},
      now: DateTime(2026, 11, 1, 18),
    );
    final b = parseBackup(text);
    expect(b.entries.single.id, 'E1');
    expect(b.entries.single.grams, 170);
    expect(b.entries.single.total(Nk.kcal), closeTo(119, 0.001));
    expect(b.entries.single.food.n['salt']!.lessThan, isTrue);
    expect(b.myFoods.single.name, 'Γιαούρτι 2%');
    expect(b.prefs['themeMode'], 'dark');
    expect(b.prefs.containsKey('backfillFrom'), isFalse, reason: 'η πρόοδος του ιστορικού δεν μεταφέρεται');
    expect(b.skipped, 0);
  });

  test('Χαλασμένες εγγραφές παραλείπονται, οι υπόλοιπες μένουν', () {
    final text = jsonEncode({
      'app': backupApp,
      'version': 1,
      'foodLog': [entry, {'id': 'E2'}, {...entry, 'id': 'E3', 'grams': 0}],
      'myFoods': [food, {'name': 'χωρίς id'}],
    });
    final b = parseBackup(text);
    expect(b.entries.map((e) => e.id), ['E1']);
    expect(b.myFoods.length, 1);
    expect(b.skipped, 3);
  });

  test('Ξένο αρχείο ή νεότερη έκδοση: καθαρό μήνυμα, τίποτα δεν γράφεται', () {
    expect(() => parseBackup('όχι json'), throwsA(isA<BackupError>()));
    expect(() => parseBackup(jsonEncode({'app': 'άλλη'})), throwsA(isA<BackupError>()));
    expect(() => parseBackup(jsonEncode({'app': backupApp, 'version': 99})), throwsA(isA<BackupError>()));
  });

  test('Ενικός και πληθυντικός', () {
    expect(entriesText(1), '1 καταχώριση');
    expect(entriesText(3), '3 καταχωρίσεις');
    expect(productsText(1), '1 προϊόν');
    expect(productsText(0), '0 προϊόντα');
  });

  test('Όνομα αρχείου', () {
    expect(backupFileName(DateTime(2026, 3, 5)), 'ygeia-antigrafo-2026-03-05.json');
  });
}
