import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/plan_file.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/training/training_store.dart';

import 'training_sample.dart';

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
    expect(backupFileName(DateTime(2026, 3, 5)), 'ygeia-antigrafo-2026-03-05.json.gz');
  });

  test('A10: το σχέδιο πηγών και το ημερολόγιό του μπαίνουν στο αντίγραφο και διαβάζονται πίσω', () {
    final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 6));
    final file = encodePlanFile(plan, DateTime(2026, 11, 7), at: 1234);
    final log = appendPlanLog(null, plan, 1234);
    final b = parseBackup(buildBackup(foodLog: [entry], myFoods: const [], prefs: const {}, now: DateTime(2026, 11, 7),
        sources: (plan: file, log: log)));
    expect(b.sources!.plan, file);
    expect(decodePlanFile(b.sources!.plan), plan);
    expect(b.sources!.log, log);
    // Παλιό αντίγραφο χωρίς πηγές, ή χαλασμένο σχέδιο: χωρίς πηγές (τίποτα δεν αλλάζει στο κινητό).
    expect(parseBackup(buildBackup(foodLog: const [], myFoods: const [], prefs: const {}, now: DateTime(2026, 11, 7))).sources, isNull);
    final broken = jsonEncode({'app': backupApp, 'version': 1, 'sources': {'plan': '{"v":1,"sources":"x"}'}});
    expect(parseBackup(broken).sources, isNull);
  });

  test('Προπονήσεις στο αντίγραφο· επαναφορά μόνο όσων λείπουν, ποτέ το όριο παλμών (έλεγχος 8/11, TRN-17)', () async {
    final now = DateTime(2026, 11, 20, 18);
    final src = sampleTraining(now);
    final b = parseBackup(buildBackup(foodLog: const [], myFoods: const [], prefs: const {}, now: now, training: src.toJson()));
    expect(b.training, isNotNull);
    final fresh = TrainingStore(io: MemoryTrainingIO(), clock: () => now);
    await fresh.load();
    expect(fresh.mergeBackup(b.training!), src.sessions.length);
    expect(fresh.hrLimit, isNull, reason: 'η οδηγία του γιατρού δεν έρχεται από αντίγραφο');
    expect(fresh.program, isNotNull);
    // δεύτερη φορά: τίποτα διπλό
    expect(fresh.mergeBackup(b.training!), 0);
    expect(fresh.sessions.length, src.sessions.length);
  });
}
