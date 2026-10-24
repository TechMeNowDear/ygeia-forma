import 'dart:convert';

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

  static Future<Map<String, dynamic>> status() => _call('status');

  static Future<Map<String, dynamic>> requestPermissions() => _call('requestPermissions');

  static Future<Map<String, dynamic>> readAll({int days = 30}) => _call('readAll', {'days': days});

  static Future<Map<String, dynamic>> dashboard() => _call('dashboard');

  static Future<Map<String, dynamic>> cachedDashboard() => _call('cachedDashboard');

  static Future<Map<String, dynamic>> loadPrefs() => _call('loadPrefs');

  static Future<Map<String, dynamic>> savePrefs(String json) => _call('savePrefs', {'json': json});

  static Future<Map<String, dynamic>> resolve() => _call('resolve');

  /// Δεδομένα για το διάστημα [from, to) — ημερομηνίες «2026-10-01».
  static Future<Map<String, dynamic>> readRange(String from, String to) =>
      _call('readRange', {'from': from, 'to': to});

  static Future<Map<String, dynamic>> saveDays(String json) => _call('saveDays', {'json': json});

  static Future<Map<String, dynamic>> loadDays() => _call('loadDays');
}
