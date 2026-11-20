// Αποφάσεις 20/11: δικό μου (σκαναρισμένο) προϊόν που μετρά στα φρούτα και λαχανικά της μέρας. Επινοημένα δεδομένα.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/off.dart';

Food _mine({bool fv = false}) => foodFromDraft(
      FoodDraft(name: 'Μπρόκολο κατεψυγμένο', values: {Nk.kcal: 34, Nk.protein: 2.8, Nk.carbs: 4, Nk.fat: 0.4}, fruitVeg: fv),
      'mine-1',
    );

void main() {
  test('ο διακόπτης αποθηκεύεται, ξαναδιαβάζεται και μένει στη «Διόρθωση»', () {
    final f = _mine(fv: true);
    expect(f.fruitVeg, isTrue);
    expect(f.toJson()['fv'], true);
    expect(Food.fromJson(f.toJson()).fruitVeg, isTrue);
    expect(Food.fromJson(Map<String, dynamic>.from(f.toSnapshotJson())).fruitVeg, isTrue);
    expect(draftFromFood(f).fruitVeg, isTrue);
    // Χωρίς τον διακόπτη: κανένα νέο κλειδί (οι παλιές εκδόσεις διαβάζουν το ίδιο αρχείο).
    expect(_mine().toJson().containsKey('fv'), isFalse);
  });

  test('μετρά στα φρούτα/λαχανικά μόνο με τον διακόπτη· η βάση από την κατηγορία της', () {
    expect(isFruitVeg(_mine(fv: true)), isTrue);
    expect(isFruitVeg(_mine()), isFalse);
    final apple = Food(id: 'C13039', name: 'Μήλο', cat: 'Φρούτα', n: Nutrients({}), source: 'CIQUAL 2025');
    final lemonJuice = Food(id: 'C2007', name: 'Χυμός λεμονιού', cat: 'Φρούτα', n: Nutrients({}), source: 'CIQUAL 2025');
    expect(isFruitVeg(apple), isTrue);
    expect(isFruitVeg(lemonJuice), isFalse);
  });
}
