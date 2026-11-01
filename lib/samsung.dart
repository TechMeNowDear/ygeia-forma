import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Μιλά με τη γέφυρα Kotlin (SamsungHealthBridge) στο κανάλι «ygeia/samsung».
/// Κάθε απάντηση είναι ένας χάρτης· αν `ok` είναι false, υπάρχουν `kind` και `message`.
class SamsungHealth {
  static const _channel = MethodChannel('ygeia/samsung');

  static Future<Map<String, dynamic>> _call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      final raw = await _channel.invokeMethod<String>(method, args);
      if (raw == null) {
        return {'ok': false, 'kind': 'other', 'message': 'Κενή απάντηση'};
      }
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
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



  static Future<Map<String, dynamic>> loadPrefs() => _call('loadPrefs');

  static Future<Map<String, dynamic>> savePrefs(String json) => _call('savePrefs', {'json': json});

  static Future<Map<String, dynamic>> resolve() => _call('resolve');


  static Future<Map<String, dynamic>> saveDays(String json) => _call('saveDays', {'json': json});

  static Future<Map<String, dynamic>> loadDays() => _call('loadDays');

  /// Σελίδες PNG (A4) → PDF στις Λήψεις. Επιστρέφει `uri`.
  static Future<Map<String, dynamic>> savePdf(List<Uint8List> pages, String name) =>
      _call('savePdf', {'pages': pages, 'name': name});

  static Future<Map<String, dynamic>> sharePdf(String uri) => _call('sharePdf', {'uri': uri});

  static Future<Map<String, dynamic>> openPdf(String uri) => _call('openPdf', {'uri': uri});
}
