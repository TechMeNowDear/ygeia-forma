/// Το σχέδιο πηγών σε δικό του μικρό αρχείο («sources.json», γράφεται ατομικά: προσωρινό αρχείο + μετονομασία),
/// ανεξάρτητο από τις ρυθμίσεις (μετά τον έλεγχο της 2/11, B1), και ένα ημερολόγιο αλλαγών («sources_log.json»).
///
/// Γιατί: αν το αρχείο ρυθμίσεων χαλάσει και η εφαρμογή ξεκινήσει από τις προεπιλογές, το σχέδιο πηγών ΔΕΝ
/// πρέπει να χαθεί — αλλιώς ο ύπνος θα γύριζε σιωπηλά στο ρολόι. Αντίγραφα: το ημερολόγιο (κάθε αλλαγή με την ώρα
/// της) και οι ρυθμίσεις («sourcesAt»). Αν χαθεί το αρχείο, μπαίνει το ΝΕΟΤΕΡΟ αντίγραφο.
/// Το ίδιο αρχείο διαβάζει η πλευρά Android (SleepPolicy.kt): ως ποια νύχτα διαβάζεται ο ύπνος του ρολογιού.
///
/// Αν το σχέδιο δεν μπορεί να βρεθεί με σιγουριά, η κατάσταση είναι «άγνωστη»: οι νύχτες μένουν κενές με εξήγηση,
/// τίποτα δεν γράφεται στο ιστορικό, και ο χρήστης διαλέγει ρητά ([recoveryOptions]).
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import 'format.dart';
import 'history.dart';
import 'sources.dart';

enum PlanState {
  /// Δεν έχει διαβαστεί ακόμα (ή δεν μπορεί να κριθεί ακόμα): τίποτα δεν γράφεται.
  loading,

  /// Γνωστό σχέδιο.
  ok,

  /// Το σχέδιο χάθηκε ή χάλασε ενώ υπάρχουν (ή μπορεί να υπάρχουν) δεδομένα Oura: κενές νύχτες, τίποτα δεν
  /// γράφεται, ο χρήστης διαλέγει.
  unknown,
}

/// Η ανάγνωση ενός αρχείου: «missing» (δεν υπάρχει), «ok» (με το κείμενο), «error» (υπάρχει, δεν διαβάστηκε).
typedef PlanRead = ({String state, String? json});

/// Ένα σχέδιο με την ώρα που ορίστηκε (ms).
typedef DatedPlan = ({SourcePlan plan, int at});

abstract class PlanFile {
  Future<PlanRead> read();

  /// `true` αν γράφτηκε (ατομικά).
  Future<bool> write(String json);

  Future<PlanRead> readLog();
  Future<bool> writeLog(String json);
}

class ChannelPlanFile implements PlanFile {
  const ChannelPlanFile();
  static const _channel = MethodChannel('ygeia/oura');
  static const _log = 'sources_log.json';

  Future<PlanRead> _read(String? name) async {
    try {
      final raw = await _channel.invokeMethod<String>('readPlan', {if (name != null) 'name': name});
      if (raw == null) return (state: 'error', json: null);
      final j = jsonDecode(raw);
      if (j is! Map) return (state: 'error', json: null);
      return (state: j['state'] is String ? j['state'] as String : 'error', json: j['json'] is String ? j['json'] as String : null);
    } on MissingPluginException {
      // Χωρίς Android (δοκιμές, στιγμιότυπα): σαν να μην υπάρχει αρχείο.
      return (state: 'missing', json: null);
    } catch (_) {
      return (state: 'error', json: null);
    }
  }

  Future<bool> _write(String? name, String json) async {
    try {
      return await _channel.invokeMethod<bool>('writePlan', {'json': json, if (name != null) 'name': name}) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<PlanRead> read() => _read(null);
  @override
  Future<bool> write(String json) => _write(null, json);
  @override
  Future<PlanRead> readLog() => _read(_log);
  @override
  Future<bool> writeLog(String json) => _write(_log, json);
}

class MemoryPlanFile implements PlanFile {
  MemoryPlanFile([this.content, this.state = 'ok']);
  String? content;

  /// «ok», «missing» ή «error» για τις δοκιμές.
  String state;
  String? log;
  bool failWrites = false;
  bool failLogWrites = false;

  /// Πόσες φορές να επιστρέψει «error» πριν διαβαστεί κανονικά (προσωρινό σφάλμα ανάγνωσης).
  int transientErrors = 0;
  int writes = 0;
  int reads = 0;

  @override
  Future<PlanRead> read() async {
    reads++;
    if (transientErrors > 0) {
      transientErrors--;
      return (state: 'error', json: null);
    }
    if (state == 'error') return (state: 'error', json: null);
    if (content == null) return (state: 'missing', json: null);
    return (state: 'ok', json: content);
  }

  @override
  Future<bool> write(String json) async {
    if (failWrites) return false;
    writes++;
    content = json;
    state = 'ok';
    return true;
  }

  @override
  Future<PlanRead> readLog() async => log == null ? (state: 'missing', json: null) : (state: 'ok', json: log);

  @override
  Future<bool> writeLog(String json) async {
    if (failLogWrites) return false;
    log = json;
    return true;
  }
}

/// Το περιεχόμενο του αρχείου για το σχέδιο [plan] τη μέρα [today].
String encodePlanFile(SourcePlan plan, DateTime today, {int? at}) {
  final cut = plan.watchSleepCutoff(today);
  return jsonEncode({
    'v': 1,
    'sources': plan.toJson(),
    if (at != null) 'at': at,
    if (cut != null) 'sleepUntil': dateKey(cut),
    // Μόνο με Oura: οι αναλυτικές μετρήσεις οξυγόνου (λεπτά κάτω από 90%) — πριν, η ανάγνωση μένει όπως ήταν.
    'spo2Series': plan.eras.isNotEmpty,
  });
}

/// Αυστηρή ανάγνωση μιας λίστας εποχών: κάθε εγγραφή πρέπει να διαβάζεται (αλλιώς χάθηκε μια αλλαγή πηγής).
SourcePlan? _strictPlan(Object? list) {
  if (list is! List) return null;
  final p = SourcePlan.fromJson(list);
  return p.eras.length == list.length ? p : null;
}

/// Αυστηρή ανάγνωση: οτιδήποτε δεν είναι ακριβώς η μορφή μας = null (χαλασμένο).
SourcePlan? decodePlanFile(String? raw) {
  if (raw == null) return null;
  try {
    final j = jsonDecode(raw);
    if (j is! Map || j['v'] != 1) return null;
    return _strictPlan(j['sources']);
  } catch (_) {
    return null;
  }
}

/// Το ημερολόγιο αλλαγών: η τελευταία καταχώριση + η νέα, το πολύ [_logMax].
const _logMax = 30;

String appendPlanLog(String? raw, SourcePlan plan, int at) {
  final entries = <Object?>[];
  try {
    final j = raw == null ? null : jsonDecode(raw);
    if (j is Map && j['entries'] is List) entries.addAll(j['entries'] as List);
  } catch (_) {}
  entries.add({'at': at, 'sources': plan.toJson()});
  final keep = entries.length > _logMax ? entries.sublist(entries.length - _logMax) : entries;
  return jsonEncode({'v': 1, 'entries': keep});
}

/// Η τελευταία έγκυρη καταχώριση του ημερολογίου.
DatedPlan? lastLoggedPlan(String? raw) {
  if (raw == null) return null;
  try {
    final j = jsonDecode(raw);
    if (j is! Map || j['entries'] is! List) return null;
    for (final e in (j['entries'] as List).reversed) {
      if (e is! Map || e['at'] is! num) continue;
      final p = _strictPlan(e['sources']);
      if (p != null) return (plan: p, at: (e['at'] as num).toInt());
    }
  } catch (_) {}
  return null;
}

/// Η πρώτη μέρα του ιστορικού με τιμές Oura («o.*»), αν υπάρχει.
DateTime? earliestOuraDay(Map<String, Map<String, double>> history) {
  String? best;
  for (final e in history.entries) {
    if (!e.value.keys.any(ouraKeySet.contains)) continue;
    if (best == null || e.key.compareTo(best) < 0) best = e.key;
  }
  return best == null ? null : parseDateKey(best);
}

/// Το σχέδιο όπως φαίνεται από τα αποθηκευμένα δεδομένα: από την πρώτη μέρα με τιμές Oura, Oura· μέρες μετά με
/// τιμές νύχτας του ρολογιού (και χωρίς Oura) = εποχή ρολογιού· ξανά τιμές Oura = ξανά Oura. Μέρες χωρίς τίποτα
/// δεν αλλάζουν την εποχή (δεν ξεχωρίζει «καμία πηγή» από νύχτα χωρίς δαχτυλίδι).
SourcePlan rebuildTimeline(Map<String, Map<String, double>> history) {
  final keys = history.keys.toList()..sort();
  final eras = <SourceEra>[];
  Source? cur;
  for (final k in keys) {
    final row = history[k]!;
    final hasO = row.keys.any(ouraKeySet.contains);
    final hasW = row.keys.any(watchNightKeys.contains);
    final s = hasO ? Source.oura : (hasW && cur != null ? Source.watch : null);
    if (s == null || s == cur) continue;
    eras.add(SourceEra(s, parseDateKey(k)));
    cur = s;
  }
  return eras.isEmpty ? SourcePlan.samsungOnly : SourcePlan(eras);
}

/// Από πού βγαίνει το σχέδιο, με τη σειρά:
/// 1. Το αρχείο του, αν διαβάζεται.
/// 2. Το ΝΕΟΤΕΡΟ από τα αντίγραφα: το ημερολόγιο ([logged]) και οι ρυθμίσεις ([prefsCopy], μόνο αν διαβάστηκαν
///    κανονικά). Τότε το αρχείο ξαναγράφεται.
/// 3. Χωρίς αρχείο, χωρίς αντίγραφο, χωρίς ένδειξη Oura ([evidence]: αρχείο νυχτών, «ouraSyncedTo») και
///    χωρίς τιμές Oura στο ιστορικό: δεν συνδέθηκε ποτέ → όπως πάντα.
/// 4. Αλλιώς «άγνωστο»: οι νύχτες από την πρώτη μέρα με τιμές Oura (ή από σήμερα) δεν έχουν πηγή — ποτέ
///    σιωπηλά πίσω στο ρολόι.
/// [history] null = το ιστορικό δεν διαβάστηκε: χωρίς αρχείο, χωρίς αντίγραφο και χωρίς ένδειξη δεν κρίνεται ακόμα.
({PlanState state, SourcePlan plan, bool rewrite}) resolvePlan({
  required PlanRead file,
  DatedPlan? logged,
  DatedPlan? prefsCopy,
  required Map<String, Map<String, double>>? history,
  bool evidence = false,
  required DateTime today,
}) {
  final fromFile = file.state == 'ok' ? decodePlanFile(file.json) : null;
  if (fromFile != null) return (state: PlanState.ok, plan: fromFile, rewrite: false);
  final copy = logged == null
      ? prefsCopy
      : prefsCopy == null || logged.at >= prefsCopy.at
          ? logged
          : prefsCopy;
  if (copy != null) return (state: PlanState.ok, plan: copy.plan, rewrite: true);
  final broken = file.state != 'missing';
  if (history == null) {
    return broken || evidence
        ? (state: PlanState.unknown, plan: SourcePlan([SourceEra(Source.none, DateTime(2000))]), rewrite: false)
        : (state: PlanState.loading, plan: SourcePlan.samsungOnly, rewrite: false);
  }
  final first = earliestOuraDay(history);
  if (!broken && !evidence && first == null) return (state: PlanState.ok, plan: SourcePlan.samsungOnly, rewrite: false);
  return (state: PlanState.unknown, plan: SourcePlan([SourceEra(Source.none, first ?? dayOf(today))]), rewrite: false);
}

/// Μία επιλογή επαναφοράς: τι λέει, και ποιο σχέδιο θα μπει (με όλη τη χρονογραμμή του, για επιβεβαίωση).
class RecoveryOption {
  const RecoveryOption(this.label, this.plan, {this.primary = false});
  final String label;
  final SourcePlan plan;
  final bool primary;
}

/// Οι επιλογές στην «άγνωστη» κατάσταση. null = το ιστορικό δεν διαβάστηκε ακόμα: καμία επιλογή («Δοκίμασε ξανά»),
/// ώστε να μην προταθεί «ρολόι» επειδή απλώς δεν φαίνονται ακόμα οι τιμές του Oura.
List<RecoveryOption>? recoveryOptions({
  required Map<String, Map<String, double>>? history,
  required bool evidence,
  required DateTime today,
}) {
  if (history == null) return null;
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  // Το ημερολόγιο αλλαγών δεν χρειάζεται επιλογή: αν διαβάζεται, το σχέδιο επανέρχεται μόνο του ([resolvePlan]).
  final rebuilt = rebuildTimeline(history);
  final out = <RecoveryOption>[];
  var base = SourcePlan.samsungOnly;
  if (rebuilt.eras.isNotEmpty) {
    base = rebuilt;
    // Ρήμα και ημερομηνίες, όχι «Όπως φαίνεται από τα αποθηκευμένα δεδομένα» (έλεγχος UX U11).
    out.add(RecoveryOption('Κράτα: ${shortTimeline(rebuilt)}', rebuilt, primary: true));
  }
  // Με ένδειξη Oura (αρχείο νυχτών, ανάγνωση, τιμές) υπάρχει ΠΑΝΤΑ η επιλογή «από το Oura».
  final anyOura = evidence || rebuilt.eras.isNotEmpty;
  if (anyOura && base.nightSource(tomorrow) != Source.oura) {
    out.add(RecoveryOption('Ύπνος από το Oura, από απόψε', base.withEra(Source.oura, tomorrow), primary: out.isEmpty));
  }
  if (!anyOura) {
    out.add(RecoveryOption('Ύπνος από το ρολόι, όπως πριν', SourcePlan.samsungOnly, primary: true));
  } else if (base.eras.isEmpty) {
    out.add(RecoveryOption('Ύπνος από το ρολόι, όπως πριν', SourcePlan.samsungOnly));
  } else if (base.nightSource(tomorrow) != Source.watch) {
    out.add(RecoveryOption('Ύπνος από το ρολόι, από απόψε', base.withEra(Source.watch, tomorrow)));
  }
  return out;
}

/// Η χρονογραμμή ενός σχεδίου σε απλά ελληνικά (οι νύχτες έχουν την ημερομηνία του πρωινού).
List<String> describePlan(SourcePlan p) {
  if (p.eras.isEmpty) return const ['Όλες οι νύχτες: ρολόι'];
  final first = p.eras.first.from;
  return [
    'Ως τη νύχτα προς ${shortDayDate(DateTime(first.year, first.month, first.day - 1))}: ${sourceName(Source.watch)}',
    for (final e in p.eras) 'Από τη νύχτα προς ${shortDayDate(e.from)}: ${sourceName(e.source)}',
  ];
}

/// Η χρονογραμμή σε μία γραμμή, για κουμπί: «ρολόι ως 5/11, Oura από 6/11».
String shortTimeline(SourcePlan p) {
  String name(Source s) => switch (s) {
        Source.oura => 'Oura',
        Source.watch => 'ρολόι',
        _ => 'χωρίς πηγή',
      };
  String dm(DateTime d) => '${d.day}/${d.month}';
  if (p.eras.isEmpty) return 'ρολόι';
  final parts = <String>[];
  for (var i = -1; i < p.eras.length; i++) {
    final source = i < 0 ? Source.watch : p.eras[i].source;
    final next = i + 1 < p.eras.length ? p.eras[i + 1].from : null;
    final until = next == null ? null : DateTime(next.year, next.month, next.day - 1);
    if (i < 0) {
      parts.add('${name(source)} ως ${dm(until!)}');
    } else if (until == null) {
      parts.add('${name(source)} από ${dm(p.eras[i].from)}');
    } else {
      parts.add('${name(source)} ${dm(p.eras[i].from)}–${dm(until)}');
    }
  }
  return parts.join(', ');
}
