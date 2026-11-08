import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'training_store.dart';

/// Κινητό στην προπόνηση: οθόνη αναμμένη, άδεια ειδοποιήσεων, διάλειμμα με ειδοποίηση και δόνηση.
/// Χωρίς Android (δοκιμές, στιγμιότυπα) δεν κάνει τίποτα.
class TrainingDevice {
  static const _c = ChannelTrainingIO.channel;

  static Future<void> _call(String m, [Map<String, dynamic>? a]) async {
    try {
      await _c.invokeMethod<Object?>(m, a);
    } on MissingPluginException {
      // δοκιμές
    } catch (_) {}
  }

  static Future<void> keepOn(bool on) => _call('keepOn', {'on': on});
  static Future<void> askNotify() => _call('askNotify');
  static Future<void> rest(DateTime end, {required String title, required String text, required String doneTitle, required String doneText}) =>
      _call('rest', {'endAt': end.millisecondsSinceEpoch, 'title': title, 'text': text, 'doneTitle': doneTitle, 'doneText': doneText});
  static Future<void> restCancel() => _call('restCancel');
  static Future<void> buzz() => _call('buzz');

  /// Ανοίγει την κλήση με τον αριθμό έτοιμο (χωρίς άδεια τηλεφώνου: πατάς εσύ «κλήση»).
  /// false μόνο αν το Android είπε ότι δεν άνοιξε (π.χ. χωρίς εφαρμογή τηλεφώνου).
  static Future<bool> dial(String number) async {
    try {
      return await _c.invokeMethod<bool>('dial', {'n': number}) ?? true;
    } on MissingPluginException {
      // Δοκιμές (που τρέχουν ως Android) ναι· σε υπολογιστή, όπου δεν υπάρχει κλήση, όχι (έλεγχος #2).
      return defaultTargetPlatform == TargetPlatform.android;
    } catch (_) {
      return false;
    }
  }
}
