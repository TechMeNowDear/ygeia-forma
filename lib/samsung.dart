import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Μιλά με τη γέφυρα Kotlin (SamsungHealthBridge) στο κανάλι «ygeia/samsung».
/// Κάθε απάντηση είναι ένας χάρτης· αν `ok` είναι false, υπάρχουν `kind` και `message`.
class SamsungHealth {
  static const _channel = MethodChannel('ygeia/samsung');

  /// [objectOnly]: απάντηση που διαβάζεται ως JSON αλλά ΔΕΝ είναι αντικείμενο (π.χ. «[]», «null») είναι σφάλμα
  /// («corrupt»), όχι «κενό αντικείμενο» (round 1, S3-2: ένα τέτοιο prefs.json διαβαζόταν ως «καμία ρύθμιση»).
  static Future<Map<String, dynamic>> _call(
    String method, [
    Map<String, dynamic>? args,
    bool objectOnly = false,
  ]) async {
    try {
      final raw = await _channel.invokeMethod<String>(method, args);
      if (raw == null) {
        return {'ok': false, 'kind': 'other', 'message': 'Κενή απάντηση'};
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return objectOnly ? {'ok': false, 'kind': 'corrupt'} : <String, dynamic>{};
    } on PlatformException catch (e) {
      return {'ok': false, 'kind': 'other', 'message': e.message ?? e.code};
    } on MissingPluginException {
      return {
        'ok': false,
        'kind': 'not_android',
        'message': 'Διαθέσιμο μόνο στο κινητό',
      };
    } on FormatException catch (e) {
      return {'ok': false, 'kind': 'other', 'message': e.message};
    }
  }

  /// Η απάντηση όπως είναι (κείμενο JSON), για να διαβαστεί σε άλλο νήμα (δες parseDashboard).
  static Future<String> _callRaw(String method, [Map<String, dynamic>? args]) async {
    try {
      final raw = await _channel.invokeMethod<String>(method, args);
      return raw ?? jsonEncode({'ok': false, 'kind': 'other', 'message': 'Κενή απάντηση'});
    } on PlatformException catch (e) {
      return jsonEncode({'ok': false, 'kind': 'other', 'message': e.message ?? e.code});
    } on MissingPluginException {
      return jsonEncode({'ok': false, 'kind': 'not_android', 'message': 'Διαθέσιμο μόνο στο κινητό'});
    }
  }

  static Future<String> dashboardRaw() => _callRaw('dashboard');
  static Future<String> cachedDashboardRaw() => _callRaw('cachedDashboard');
  static Future<String> readRangeRaw(String from, String to) => _callRaw('readRange', {'from': from, 'to': to});

  static Future<Map<String, dynamic>> status() => _call('status');

  static Future<Map<String, dynamic>> requestPermissions() => _call('requestPermissions');

  static Future<Map<String, dynamic>> readAll({int days = 30}) => _call('readAll', {'days': days});



  static Future<Map<String, dynamic>> loadPrefs() => _call('loadPrefs', null, true);

  static Future<Map<String, dynamic>> savePrefs(String json) => _call('savePrefs', {'json': json});

  /// Round 1 (S3-2 / S9-1): το χαλασμένο prefs.json μπαίνει στην άκρη ως «prefs.json.bad» (κρατιέται), μόνο όταν το
  /// ζητήσει ο χρήστης. `ok` true αν μετακινήθηκε ή δεν υπήρχε· αρχείο που διαβάζεται κανονικά δεν μετακινείται.
  static Future<Map<String, dynamic>> prefsSetAside() => _call('prefsSetAside');

  static Future<Map<String, dynamic>> resolve() => _call('resolve');


  static Future<Map<String, dynamic>> saveDays(String json) => _call('saveDays', {'json': json});

  static Future<Map<String, dynamic>> loadDays() => _call('loadDays');

  /// Αν η βάση βρέθηκε χαλασμένη και κρατήθηκε αντίγραφο (A7): {"ok", "corrupt": ms ή null}.
  static Future<Map<String, dynamic>> dbStatus() => _call('dbStatus');
  static Future<Map<String, dynamic>> dbStatusSeen() => _call('dbStatusSeen');

  /// Σελίδες PNG (A4) → PDF στις Λήψεις. Επιστρέφει `uri`.
  static Future<Map<String, dynamic>> savePdf(List<Uint8List> pages, String name) =>
      _call('savePdf', {'pages': pages, 'name': name});

  static Future<Map<String, dynamic>> sharePdf(String uri) => _call('sharePdf', {'uri': uri});

  static Future<Map<String, dynamic>> openPdf(String uri) => _call('openPdf', {'uri': uri});
}
