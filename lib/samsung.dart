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
      return jsonDecode(raw) as Map<String, dynamic>;
    } on PlatformException catch (e) {
      return {'ok': false, 'kind': 'other', 'message': e.message ?? e.code};
    } on MissingPluginException {
      return {
        'ok': false,
        'kind': 'not_android',
        'message': 'Διαθέσιμο μόνο στο κινητό',
      };
    }
  }

  static Future<Map<String, dynamic>> status() => _call('status');

  static Future<Map<String, dynamic>> requestPermissions() =>
      _call('requestPermissions');

  static Future<Map<String, dynamic>> readAll({int days = 30}) =>
      _call('readAll', {'days': days});

  static Future<Map<String, dynamic>> resolve() => _call('resolve');
}
