import 'dart:convert';

import 'package:flutter/services.dart';

/// Κανάλι «ygeia/food» προς το Kotlin (FoodBridge).
class FoodChannel {
  static const _channel = MethodChannel('ygeia/food');

  static Future<Map<String, dynamic>> _call(String method, [Map<String, dynamic>? args]) async {
    try {
      final raw = await _channel.invokeMethod<String>(method, args);
      if (raw == null) return {'ok': false, 'kind': 'other', 'message': 'Κενή απάντηση'};
      final d = jsonDecode(raw);
      return d is Map<String, dynamic> ? d : <String, dynamic>{};
    } on PlatformException catch (e) {
      return {'ok': false, 'kind': 'other', 'message': e.message ?? e.code};
    } on MissingPluginException {
      return {'ok': false, 'kind': 'not_android', 'message': 'Διαθέσιμο μόνο στο κινητό'};
    } on FormatException catch (e) {
      return {'ok': false, 'kind': 'other', 'message': e.message};
    }
  }

  static Future<Map<String, dynamic>> logRange(String from, String to) => _call('logRange', {'from': from, 'to': to});
  /// Οι εγγραφές στη βάση μία-μία, με τη σειρά που ζητήθηκαν (έλεγχος 4/11, A8): π.χ. «διαγραφή» και αμέσως
  /// «Αναίρεση» δεν φτάνουν ποτέ ανάποδα (μετά η καταχώριση θα έμενε σβησμένη).
  static Future<Map<String, dynamic>> _writes = Future.value(const {});

  /// Round 1 (integ1): πόσες εγγραφές δεν έχουν τελειώσει ακόμα. Χωρίς καμία σε εξέλιξη, η νέα ξεκινά αμέσως (η σειρά
  /// μένει ίδια: δεν υπάρχει τίποτα να περιμένει), αντί να «κρεμαστεί» από μια αλυσίδα που έχει ήδη τελειώσει: μια τέτοια
  /// αλυσίδα από άλλη ζώνη (π.χ. μια προηγούμενη δοκιμή οθόνης) δεν συνεχίζει ποτέ, και η εγγραφή δεν θα γινόταν ποτέ.
  static var _pendingWrites = 0;
  static Future<Map<String, dynamic>> _write(String method, Map<String, dynamic> args) {
    final run = (_pendingWrites == 0
            ? _call(method, args)
            : _writes.catchError((_) => const <String, dynamic>{}).then((_) => _call(method, args)))
        .whenComplete(() {
      _pendingWrites--;
    });
    _pendingWrites++;
    _writes = run.catchError((_) => const <String, dynamic>{});
    return run;
  }

  static Future<Map<String, dynamic>> logPut(String json) => _write('logPut', {'json': json});
  static Future<Map<String, dynamic>> logDelete(String id) => _write('logDelete', {'id': id});
  static Future<Map<String, dynamic>> myFoods() => _call('myFoods');
  static Future<Map<String, dynamic>> myFoodPut(String json) => _write('myFoodPut', {'json': json});
  static Future<Map<String, dynamic>> myFoodDelete(String id) => _write('myFoodDelete', {'id': id});
  /// Επαναφορά από αντίγραφο (τελικός έλεγχος, Συμβούλιο 4, Γ1): όλες οι καταχωρίσεις και τα προϊόντα που λείπουν σε μία
  /// κλήση και μία συναλλαγή στη βάση (ή όλα ή τίποτα). [log] και [foods]: πίνακες JSON. Απάντηση: πόσα γράφτηκαν
  /// («entries», «foods»). Μπαίνει στην ίδια σειρά με τις άλλες εγγραφές.
  static Future<Map<String, dynamic>> restorePut(String log, String foods) => _write('restorePut', {'log': log, 'foods': foods});
  /// Round 7 (R7-A9-1, f4): μετά από βλάβη της βάσης, οι καταχωρίσεις («entries») και τα προϊόντα («foods») που
  /// διαβάζονται από το αρχείο που κρατήθηκε για τη βλάβη [at] (μόνο ανάγνωση· το αρχείο δεν αλλάζει). «done»: έγινε
  /// ήδη (με το πόσα ξαναμπήκαν τότε). [salvageDone]: σημειώνει ότι έγινε, με το πόσα ξαναμπήκαν.
  static Future<Map<String, dynamic>> salvageRead(int at) => _call('salvageRead', {'at': at});
  static Future<Map<String, dynamic>> salvageDone(int at, int entries, int foods) =>
      _write('salvageDone', {'at': at, 'entries': entries, 'foods': foods});
  static Future<Map<String, dynamic>> scanBarcode() => _call('scanBarcode');
  static Future<Map<String, dynamic>> saveBackup(String json, String name) =>
      _call('saveBackup', {'json': json, 'name': name});
  static Future<Map<String, dynamic>> shareBackup(String uri) => _call('shareBackup', {'uri': uri});
  static Future<Map<String, dynamic>> pickBackup() => _call('pickBackup');
  static Future<Map<String, dynamic>> offLookup(String code) => _call('offLookup', {'code': code});
}
