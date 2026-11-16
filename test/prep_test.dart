// «Ο εξοπλισμός μου» και «Ετοίμασε πριν ξεκινήσεις» (16/11).
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/training/equipment.dart';
import 'package:ygeia_forma/training/prep.dart';

const bought = Equipment(handleKg: 2.0, handles: 8, counts: [8, 10, 8, 8]);

void main() {
  tearDown(() => equip = Equipment.standard);

  test('Προεπιλογή: τα ίδια βάρη με πριν (2 λαβές 1,8 kg, 4 δίσκοι από κάθε βάρος)', () {
    final pair = available(LoadKind.dbPair);
    expect(pair.first, 1.8);
    expect(pair.last, 20.3, reason: '1,8 + 2 × (5 + 2,5 + 1,25 + 0,5)');
    expect(pair, hasLength(16));
    expect(available(LoadKind.bar).last, 47);
    expect(setupText(LoadKind.dbPair, 1.8), 'μόνο η λαβή (1,8 kg), και στους δύο αλτήρες');
  });

  test('Αρχείο: γράφεται και διαβάζεται· ό,τι δεν είναι λογικό παίρνει την προεπιλογή', () {
    final back = Equipment.fromJson(bought.toJson());
    expect(back.handles, 8);
    expect(back.handleKg, 2.0);
    expect(back.count(2.5), 10);
    expect(Equipment.standard.isStandard, isTrue);
    expect(bought.isStandard, isFalse);
    final bad = Equipment.fromJson({
      'handleKg': 50,
      'handles': 0,
      'plates': {'5.0': -1, '2.5': 6}
    });
    expect(bad.handleKg, 1.8);
    expect(bad.handles, 2);
    expect(bad.count(5), 4);
    expect(bad.count(2.5), 6);
    expect(Equipment.fromJson('χαλασμένο').isStandard, isTrue);
  });

  test('Μετά την αγορά: βαρύτεροι αλτήρες και μπάρα, με τη νέα λαβή', () {
    equip = bought;
    expect(available(LoadKind.dbPair).first, 2.0);
    expect(available(LoadKind.dbPair), contains(22.0), reason: '2 + 2 × (5 + 5)');
    expect(available(LoadKind.bar).last, 89, reason: '10 + 40 + 25 + 10 + 4 (όλοι οι δίσκοι)');
    expect(platesPerSide(LoadKind.dbPair, 12.0), [5]);
  });

  final day = <PrepIn>[
    (name: 'Πιεστικό σε κλίση', kind: LoadKind.dbPair, load: 11.8),
    (name: 'Κωπηλασία', kind: LoadKind.db, load: 14.3),
    (name: 'Σφυριά', kind: LoadKind.dbPair, load: 6.8),
    (name: 'Τρικέφαλοι', kind: LoadKind.dbPair, load: 6.8),
    (name: 'Λάστιχο', kind: LoadKind.band, load: 30),
    (name: 'Κάμψεις', kind: LoadKind.bodyweight, load: null),
  ];

  test('Ετοίμασε: με 2 λαβές στήνεται μόνο το πρώτο ζευγάρι· τα άλλα «όταν φτάσεις εκεί»', () {
    final p = prepFor(day, Equipment.standard);
    expect(p.handlesNeeded, 5, reason: '2 + 1 + 2 (οι σφυριά και οι τρικέφαλοι μοιράζονται τα 6,8 kg)');
    expect(p.short, isTrue);
    final ready = [for (final l in p.lines) if (!l.later) l.what];
    expect(ready.first, '2 αλτήρες 11,8 kg');
    expect([for (final l in p.lines) if (l.later) l.what], ['1 αλτήρας 14,3 kg', '2 αλτήρες 6,8 kg']);
  });

  test('Ετοίμασε: με τον νέο εξοπλισμό όλα μαζί, με τους δίσκους σωστά μοιρασμένους', () {
    const e = Equipment(handleKg: 1.8, handles: 8, counts: [8, 10, 8, 8]);
    final p = prepFor(day, e);
    expect(p.short, isFalse);
    final byWhat = {for (final l in p.lines) l.what: l};
    expect(byWhat['2 αλτήρες 11,8 kg']!.how, 'σε κάθε άκρη 5');
    expect(byWhat['1 αλτήρας 14,3 kg']!.how, 'σε κάθε άκρη 5 + 1,25');
    expect(byWhat['2 αλτήρες 6,8 kg']!.how, 'σε κάθε άκρη 2,5');
    expect(byWhat['2 αλτήρες 6,8 kg']!.forWhat, ['Σφυριά', 'Τρικέφαλοι']);
    expect(p.lines.last.what, startsWith('Λάστιχο'));
    expect(p.lines.where((l) => l.forWhat.contains('Κάμψεις')), isEmpty);
  });

  test('Ετοίμασε: όταν τελειώνουν οι δίσκοι, το λέει (όχι λάθος στήσιμο)', () {
    const e = Equipment(handleKg: 1.8, handles: 8, counts: [4, 4, 4, 4]);
    final p = prepFor([
      (name: 'Α', kind: LoadKind.dbPair, load: 11.8),
      (name: 'Β', kind: LoadKind.dbPair, load: 11.8 + 0.01),
      (name: 'Γ', kind: LoadKind.dbPair, load: 21.8),
    ], e);
    expect(p.short, isTrue);
    expect(p.lines.where((l) => l.later).map((l) => l.what), contains('2 αλτήρες 21,8 kg'));
  });
}
