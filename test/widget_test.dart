import 'package:flutter_test/flutter_test.dart';

import 'package:ygeia_forma/labels.dart';

void main() {
  test('Τα ονόματα πεδίων μεταφράζονται', () {
    expect(fieldLabel('WEIGHT'), 'Βάρος (kg)');
    expect(fieldLabel('skeletal_muscle_mass'), 'Σκελετικοί μύες (kg)');
    expect(fieldLabel('kati_allo'), 'kati_allo');
  });
}
