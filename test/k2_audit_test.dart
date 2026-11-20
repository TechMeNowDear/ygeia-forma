// Έλεγχος 17/11, κατηγορία 2 (βάση τροφίμων και καταγραφή). Μόνο φανταστικά δεδομένα.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/recipe.dart';
import 'package:ygeia_forma/food/replaced_foods.dart';
import 'package:ygeia_forma/pages/dishes.dart';
import 'package:ygeia_forma/pages/food_add.dart';

import 'sample_food.dart';

Food _byId(String id) => basicFoods().firstWhere((f) => f.id == id);

void main() {
  group('Κ2: μόνο μαγειρεμένα τρόφιμα της βάσης', () {
    test('κεφτέδες, σουβλάκι: «Βάρος μετά το μαγείρεμα» (πριν «πριν το μαγείρεμα»)', () {
      for (final id in ['C25163', 'C25585', 'C25586', 'C26024', 'C9313', 'C20049']) {
        final f = _byId(id);
        expect(f.rawId, isNull, reason: f.name);
        expect(f.isCooked, isTrue, reason: f.name);
        expect(stateNote(f), startsWith('Βάρος μετά το μαγείρεμα'), reason: f.name);
      }
    });

    test('δεν μπαίνουν στα ωμά υλικά των οδηγιών για συνταγές', () {
      final lines = rawFoodLines(basicFoods(), const FoodLikes()).join('\n');
      for (final id in ['C25163', 'C25585', 'C6110', 'C21501', 'C36005', 'C40116']) {
        expect(lines, isNot(contains('$id ')), reason: id);
      }
      for (final id in ['C6111', 'C6510', 'C21500', 'C36016', 'C40111']) {
        expect(lines, contains('$id '), reason: id);
      }
    });

    test('ωμές μορφές για τα ψητά κρέατα, με ζευγάρι', () {
      expect(_byId('C6110').rawId, 'C6111');
      // Έλεγχος 20/11 (K2-C-03 / K2-S-04): μοσχαρίσια μπριζόλα και αρνίσια παϊδάκια ΔΕΝ είναι πια ζευγάρι: η ωμή γραμμή της
      // πηγής είναι το κρέας με το λίπος, η ψητή μόνο το ψαχνό (το ίδιο κομμάτι έγραφε −57% θερμίδες, −72% κορεσμένα).
      for (final (raw, cooked) in [('C6510', 'C6511'), ('C21500', 'C21501')]) {
        expect(_byId(cooked).rawId, isNull, reason: cooked);
        expect(_byId(cooked).isCooked, isTrue, reason: cooked);
        expect(_byId(raw).cooked, isEmpty, reason: raw);
        expect(_byId(raw).name, contains('με το λίπος'), reason: raw);
        expect(_byId(cooked).name, contains('μόνο το ψαχνό'), reason: cooked);
      }
      expect(_byId('C36005').rawId, 'C36016');
      expect(_byId('C40116').rawId, 'C40111');
      expect(_byId('C26229').rawId, 'C26036');
      expect(_byId('C10007').rawId, 'C10021');
    });
  });

  group('Κ2: δεδομένα', () {
    test('φασόλια: ξερά και βρασμένα από την ίδια πηγή (ίνες με τον ίδιο λόγο)', () {
      final dry = _byId('C20501'), boiled = _byId('U175203');
      expect(boiled.rawId, 'C20501');
      expect(replacedFoods['C20502'], 'U175203');
      final rProt = dry.n.amount(Nk.protein) / boiled.n.amount(Nk.protein);
      final rFib = dry.n.amount(Nk.fiber) / boiled.n.amount(Nk.fiber);
      expect(rFib, closeTo(rProt, 0.15));
    });

    test('αλάτι από τη CIQUAL όπου το νάτριο δεν στέκει', () {
      expect(_byId('C15045').n.amount(Nk.salt), closeTo(2.63, 1e-9));
      expect(_byId('C26700').n.amount(Nk.salt), closeTo(4.15, 1e-9));
      expect(_byId('C12114').n.amount(Nk.salt), closeTo(1.3, 1e-9));
    });
  });

  group('Κ2-H1: ανέγγιχτο πεδίο κρατά την αποθηκευμένη τιμή', () {
    test('0,25 μερίδες φαίνονται «0,3» αλλά μένουν 0,25', () {
      final t = TextEditingController(text: gramsField(0.25));
      expect(t.text, '0,3');
      expect(keptFieldValue(t, 0.25), 0.25);
      t.text = '0,5';
      expect(keptFieldValue(t, 0.25), 0.5);
    });
  });

  group('Κ2-M1: πρόγραμμα εβδομάδας και υπενθύμιση στο αντίγραφο', () {
    test('γράφονται και διαβάζονται', () {
      final json = buildBackup(
        foodLog: const [],
        myFoods: const [],
        prefs: const {},
        now: DateTime(2026, 11, 17),
        foodWeek: const {'v': 1},
        foodRemind: 21 * 60,
      );
      final j = jsonDecode(json) as Map<String, dynamic>;
      expect(j['foodWeek'], {'v': 1});
      expect(j['foodRemind'], 21 * 60);
      final b = parseBackup(json);
      expect(b.week, {'v': 1});
      expect(b.remind, 21 * 60);
    });
  });
}
