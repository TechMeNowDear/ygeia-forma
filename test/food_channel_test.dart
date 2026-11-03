// Έλεγχος 4/11, A8: οι εγγραφές του φαγητού φτάνουν στη βάση μία-μία, με τη σειρά τους (διαγραφή → αναίρεση).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/food/food_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Διαγραφή και αμέσως «Αναίρεση»: η δεύτερη ξεκινά μόνο αφού τελειώσει η πρώτη', () async {
    final gate = Completer<void>();
    final order = <String>[];
    var inFlight = 0;
    var maxInFlight = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('ygeia/food'), (call) async {
      inFlight++;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      order.add(call.method);
      if (call.method == 'logDelete') await gate.future;
      inFlight--;
      return jsonEncode({'ok': true});
    });
    final del = FoodChannel.logDelete('E1');
    final undo = FoodChannel.logPut(jsonEncode({'id': 'E1', 'day': '2026-11-04'}));
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(order, ['logDelete'], reason: 'η «Αναίρεση» περιμένει');
    gate.complete();
    expect((await del)['ok'], isTrue);
    expect((await undo)['ok'], isTrue);
    expect(order, ['logDelete', 'logPut']);
    expect(maxInFlight, 1);
  });
}
