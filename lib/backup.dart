/// Αντίγραφο ασφαλείας: ημερολόγιο φαγητού, «Τα προϊόντα μου» και ρυθμίσεις σε ένα αρχείο JSON.
///
/// Αυτά υπάρχουν μόνο στο κινητό (τα δεδομένα της Samsung ξαναδιαβάζονται, γι' αυτό δεν μπαίνουν).
/// Η επαναφορά **δεν σβήνει τίποτα**: προσθέτει ό,τι λείπει και ενημερώνει ό,τι έχει το ίδιο id.
library;

import 'dart:convert';

import 'food/food_model.dart';

const backupApp = 'ygeia-forma';
const backupVersion = 1;

/// Οι ρυθμίσεις που μπαίνουν στο αντίγραφο (όχι η πρόοδος του ιστορικού, που είναι τεχνική).
const backupPrefKeys = ['cards', 'kitchen', 'themeMode', 'dayTheme', 'nightTheme'];

String buildBackup({
  required List<Map<String, dynamic>> foodLog,
  required List<Map<String, dynamic>> myFoods,
  required Map<String, dynamic> prefs,
  required DateTime now,
}) {
  return const JsonEncoder.withIndent(' ').convert({
    'app': backupApp,
    'version': backupVersion,
    'created': now.toIso8601String(),
    'foodLog': foodLog,
    'myFoods': myFoods,
    'prefs': {
      for (final k in backupPrefKeys)
        if (prefs[k] != null) k: prefs[k],
    },
  });
}

/// Ό,τι βρέθηκε σε ένα αρχείο αντιγράφου, ελεγμένο.
class BackupContents {
  BackupContents(this.entries, this.myFoods, this.prefs, this.created, this.skipped);
  final List<LogEntry> entries;
  final List<Food> myFoods;
  final Map<String, dynamic> prefs;
  final DateTime? created;

  /// Εγγραφές που δεν διαβάστηκαν (χαλασμένες) και παραλείπονται.
  final int skipped;
}

class BackupError implements Exception {
  BackupError(this.message);
  final String message;
  @override
  String toString() => message;
}

BackupContents parseBackup(String text) {
  Object? j;
  try {
    j = jsonDecode(text);
  } catch (_) {
    throw BackupError('Το αρχείο δεν είναι αντίγραφο της εφαρμογής.');
  }
  if (j is! Map || j['app'] != backupApp) {
    throw BackupError('Το αρχείο δεν είναι αντίγραφο της εφαρμογής.');
  }
  final v = j['version'];
  if (v is! num || v.toInt() > backupVersion) {
    throw BackupError('Το αντίγραφο είναι από νεότερη έκδοση της εφαρμογής. Ενημέρωσε πρώτα την εφαρμογή.');
  }
  var skipped = 0;
  final entries = <LogEntry>[];
  for (final e in (j['foodLog'] is List ? j['foodLog'] as List : const [])) {
    try {
      final le = LogEntry.fromJson(Map<String, dynamic>.from(e as Map));
      if (le.id.isEmpty || le.day.isEmpty || !(le.grams > 0)) throw const FormatException();
      entries.add(le);
    } catch (_) {
      skipped++;
    }
  }
  final foods = <Food>[];
  for (final f in (j['myFoods'] is List ? j['myFoods'] as List : const [])) {
    try {
      final food = Food.fromJson(Map<String, dynamic>.from(f as Map));
      if (food.id.isEmpty) throw const FormatException();
      foods.add(food);
    } catch (_) {
      skipped++;
    }
  }
  final prefs = j['prefs'] is Map
      ? {
          for (final e in (j['prefs'] as Map).entries)
            if (backupPrefKeys.contains(e.key)) e.key.toString(): e.value,
        }
      : <String, dynamic>{};
  return BackupContents(
    entries,
    foods,
    prefs,
    j['created'] is String ? DateTime.tryParse(j['created'] as String) : null,
    skipped,
  );
}

/// «ygeia-antigrafo-2026-11-01.json»
String backupFileName(DateTime now) =>
    'ygeia-antigrafo-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json';
