/// Το σχέδιο πηγών σε δικό του μικρό αρχείο («sources.json», γράφεται ατομικά: προσωρινό αρχείο + μετονομασία),
/// ανεξάρτητο από τις ρυθμίσεις (μετά τον έλεγχο της 2/11, B1).
///
/// Γιατί: αν το αρχείο ρυθμίσεων χαλάσει και η εφαρμογή ξεκινήσει από τις προεπιλογές, το σχέδιο πηγών ΔΕΝ
/// πρέπει να χαθεί — αλλιώς ο ύπνος θα γύριζε σιωπηλά στο ρολόι. Αντίγραφο του σχεδίου μένει και στις ρυθμίσεις.
/// Το ίδιο αρχείο διαβάζει η πλευρά Android (SleepPolicy.kt): ως ποια νύχτα διαβάζεται ο ύπνος του ρολογιού.
///
/// Αν το σχέδιο δεν μπορεί να βρεθεί με σιγουριά, η κατάσταση είναι «άγνωστη»: οι νύχτες μένουν κενές με εξήγηση,
/// τίποτα δεν γράφεται στο ιστορικό, και ο χρήστης διαλέγει ρητά (δες [resolvePlan]).
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

/// Η ανάγνωση του αρχείου: «missing» (δεν υπάρχει), «ok» (με το κείμενο), «error» (υπάρχει, δεν διαβάστηκε).
typedef PlanRead = ({String state, String? json});

abstract class PlanFile {
  Future<PlanRead> read();

  /// `true` αν γράφτηκε (ατομικά).
  Future<bool> write(String json);
}

class ChannelPlanFile implements PlanFile {
  const ChannelPlanFile();
  static const _channel = MethodChannel('ygeia/oura');

  @override
  Future<PlanRead> read() async {
    try {
      final raw = await _channel.invokeMethod<String>('readPlan');
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

  @override
  Future<bool> write(String json) async {
    try {
      return await _channel.invokeMethod<bool>('writePlan', {'json': json}) ?? false;
    } catch (_) {
      return false;
    }
  }
}

class MemoryPlanFile implements PlanFile {
  MemoryPlanFile([this.content, this.state = 'ok']);
  String? content;

  /// «ok», «missing» ή «error» για τις δοκιμές.
  String state;
  bool failWrites = false;
  int writes = 0;

  @override
  Future<PlanRead> read() async {
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
}

/// Το περιεχόμενο του αρχείου για το σχέδιο [plan] τη μέρα [today].
String encodePlanFile(SourcePlan plan, DateTime today) {
  final cut = plan.watchSleepCutoff(today);
  return jsonEncode({
    'v': 1,
    'sources': plan.toJson(),
    if (cut != null) 'sleepUntil': dateKey(cut),
    // Μόνο με Oura: οι αναλυτικές μετρήσεις οξυγόνου (λεπτά κάτω από 90%) — πριν, η ανάγνωση μένει όπως ήταν.
    'spo2Series': plan.eras.isNotEmpty,
  });
}

/// Αυστηρή ανάγνωση: οτιδήποτε δεν είναι ακριβώς η μορφή μας = null (χαλασμένο).
SourcePlan? decodePlanFile(String? raw) {
  if (raw == null) return null;
  try {
    final j = jsonDecode(raw);
    if (j is! Map || j['v'] != 1 || j['sources'] is! List) return null;
    final list = j['sources'] as List;
    final p = SourcePlan.fromJson(list);
    // Κάθε εγγραφή πρέπει να διαβάστηκε (αλλιώς χάθηκε μια αλλαγή πηγής).
    if (p.eras.length != list.length) return null;
    return p;
  } catch (_) {
    return null;
  }
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

/// Από πού βγαίνει το σχέδιο, με τη σειρά:
/// 1. Το αρχείο του, αν διαβάζεται.
/// 2. Το αντίγραφο στις ρυθμίσεις, ΜΟΝΟ αν οι ρυθμίσεις διαβάστηκαν κανονικά ([trustedPrefsPlan]).
/// 3. Χωρίς αρχείο, χωρίς αντίγραφο και χωρίς τιμές Oura στο ιστορικό: δεν συνδέθηκε ποτέ → όπως πάντα.
/// 4. Αλλιώς «άγνωστο»: οι νύχτες από την πρώτη μέρα με τιμές Oura (ή από σήμερα, αν χάλασε το αρχείο χωρίς
///    τιμές ακόμα) δεν έχουν πηγή — ποτέ σιωπηλά πίσω στο ρολόι.
/// [history] null = το ιστορικό δεν διαβάστηκε: χωρίς αρχείο δεν κρίνεται ακόμα (loading).
({PlanState state, SourcePlan plan, bool rewrite}) resolvePlan({
  required PlanRead file,
  required SourcePlan? trustedPrefsPlan,
  required Map<String, Map<String, double>>? history,
  required DateTime today,
}) {
  final fromFile = file.state == 'ok' ? decodePlanFile(file.json) : null;
  if (fromFile != null) return (state: PlanState.ok, plan: fromFile, rewrite: false);
  final broken = file.state != 'missing';
  if (trustedPrefsPlan != null && trustedPrefsPlan.eras.isNotEmpty) {
    return (state: PlanState.ok, plan: trustedPrefsPlan, rewrite: true);
  }
  if (history == null) {
    return broken
        ? (state: PlanState.unknown, plan: SourcePlan([SourceEra(Source.none, DateTime(2000))]), rewrite: false)
        : (state: PlanState.loading, plan: SourcePlan.samsungOnly, rewrite: false);
  }
  final first = earliestOuraDay(history);
  if (!broken && first == null) return (state: PlanState.ok, plan: SourcePlan.samsungOnly, rewrite: false);
  return (state: PlanState.unknown, plan: SourcePlan([SourceEra(Source.none, first ?? dayOf(today))]), rewrite: false);
}
