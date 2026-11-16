/// Πίεση, σάκχαρο και καρδιογραφήματα, γραμμένα με το χέρι (16/11).
///
/// - Πίεση: μεγάλη/μικρή (mmHg) και σφυγμοί, από πιεσόμετρο του σπιτιού. Ο μέσος όρος 7 ημερών συγκρίνεται με το όριο
///   για μετρήσεις στο σπίτι (ESC 2024: 135/85). Μία μέτρηση μόνη της δεν χαρακτηρίζεται.
/// - Σάκχαρο: mg/dL, με το πότε μετρήθηκε (νηστεία, μετά το φαγητό, τυχαία). Ο μετρητής του σπιτιού δεν κάνει διάγνωση.
/// - Καρδιογράφημα: το αποτέλεσμα όπως το έδειξε το ρολόι (το Samsung Health δεν το δίνει σε άλλες εφαρμογές).
///
/// Αρχείο vitals.json (ατομική εγγραφή, στο αντίγραφο Google και στην «Εξαγωγή αντιγράφου»). Χαλασμένο αρχείο μπαίνει
/// στην άκρη, ποτέ δεν σβήνεται.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'food/food_channel.dart';

enum VitalKind { bp, glucose, ecg }

/// Πότε μετρήθηκε το σάκχαρο.
enum GlucoseWhen { fasting, after, random }

/// Το αποτέλεσμα του καρδιογραφήματος του ρολογιού (όπως το γράφει η εφαρμογή ECG της Samsung).
enum EcgResult { sinus, afib, inconclusive, poor }

String glucoseWhenText(GlucoseWhen w) => switch (w) {
      GlucoseWhen.fasting => 'νηστεία',
      GlucoseWhen.after => '2 ώρες μετά το φαγητό',
      GlucoseWhen.random => 'τυχαία',
    };

String ecgText(EcgResult r) => switch (r) {
      EcgResult.sinus => 'Φλεβοκομβικός ρυθμός',
      EcgResult.afib => 'Κολπική μαρμαρυγή',
      EcgResult.inconclusive => 'Ασαφές',
      EcgResult.poor => 'Κακή καταγραφή',
    };

class Vital {
  const Vital({
    required this.id,
    required this.kind,
    required this.at,
    this.sys,
    this.dia,
    this.pulse,
    this.glucose,
    this.when,
    this.ecg,
    this.note,
  });

  final String id;
  final VitalKind kind;
  final DateTime at;

  /// Πίεση (mmHg) και σφυγμοί.
  final int? sys, dia, pulse;

  /// Σάκχαρο (mg/dL).
  final double? glucose;
  final GlucoseWhen? when;
  final EcgResult? ecg;
  final String? note;

  Map<String, Object> toJson() => {
        'id': id,
        'k': kind.name,
        'at': at.millisecondsSinceEpoch,
        if (sys != null) 'sys': sys!,
        if (dia != null) 'dia': dia!,
        if (pulse != null) 'pulse': pulse!,
        if (glucose != null) 'glu': glucose!,
        if (when != null) 'when': when!.name,
        if (ecg != null) 'ecg': ecg!.name,
        if (note != null && note!.isNotEmpty) 'note': note!,
      };

  /// null αν δεν είναι σωστή (λάθος είδος, τιμές έξω από όσα μετρά μια συσκευή).
  static Vital? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], k = j['k'], at = j['at'];
    if (id is! String || id.isEmpty || at is! int) return null;
    final kind = VitalKind.values.where((x) => x.name == k).firstOrNull;
    if (kind == null) return null;
    final note = j['note'] is String ? j['note'] as String : null;
    final t = DateTime.fromMillisecondsSinceEpoch(at);
    switch (kind) {
      case VitalKind.bp:
        final s = j['sys'], d = j['dia'], p = j['pulse'];
        if (s is! int || d is! int || bpProblem(s, d, p is int ? p : null) != null) return null;
        return Vital(id: id, kind: kind, at: t, sys: s, dia: d, pulse: p is int ? p : null, note: note);
      case VitalKind.glucose:
        final g = j['glu'];
        final w = GlucoseWhen.values.where((x) => x.name == j['when']).firstOrNull;
        if (g is! num || w == null || glucoseProblem(g.toDouble()) != null) return null;
        return Vital(id: id, kind: kind, at: t, glucose: g.toDouble(), when: w, note: note);
      case VitalKind.ecg:
        final r = EcgResult.values.where((x) => x.name == j['ecg']).firstOrNull;
        if (r == null) return null;
        return Vital(id: id, kind: kind, at: t, ecg: r, note: note);
    }
  }
}

/// Τιμές που δεν βγάζει πιεσόμετρο (λάθος πληκτρολόγησης): το λέει, δεν γράφεται.
String? bpProblem(int sys, int dia, int? pulse) {
  if (sys < 60 || sys > 260) return 'Η μεγάλη (συστολική) θέλει αριθμό από 60 ως 260.';
  if (dia < 30 || dia > 160) return 'Η μικρή (διαστολική) θέλει αριθμό από 30 ως 160.';
  if (dia >= sys) return 'Η μικρή πρέπει να είναι μικρότερη από τη μεγάλη.';
  if (pulse != null && (pulse < 25 || pulse > 230)) return 'Οι σφυγμοί θέλουν αριθμό από 25 ως 230.';
  return null;
}

String? glucoseProblem(double g) => g < 20 || g > 600 ? 'Το σάκχαρο θέλει αριθμό από 20 ως 600 mg/dL.' : null;

/// Όριο για τον μέσο όρο μετρήσεων στο σπίτι (ESC 2024).
const homeBpSys = 135, homeBpDia = 85;

/// Μέσος όρος πίεσης των τελευταίων [days] ημερών (ως και [now]), ή null χωρίς μετρήσεις.
({double sys, double dia, int n})? bpAverage(Iterable<Vital> all, DateTime now, {int days = 7}) {
  final from = DateTime(now.year, now.month, now.day - (days - 1));
  final list = [for (final v in all) if (v.kind == VitalKind.bp && !v.at.isBefore(from) && !v.at.isAfter(now)) v];
  if (list.isEmpty) return null;
  return (
    sys: list.fold(0.0, (a, v) => a + v.sys!) / list.length,
    dia: list.fold(0.0, (a, v) => a + v.dia!) / list.length,
    n: list.length,
  );
}

/// «Πάνω από το όριο του σπιτιού» ή «Κάτω από το όριο του σπιτιού», για τον μέσο όρο.
String bpAverageText(({double sys, double dia, int n}) a) {
  final s = a.sys.round(), d = a.dia.round();
  final over = s >= homeBpSys || d >= homeBpDia;
  final n = a.n == 1 ? '1 μέτρηση' : '${a.n} μετρήσεις';
  return 'Μέσος όρος 7 ημερών: $s/$d ($n). ${over ? 'Πάνω' : 'Κάτω'} από το όριο για μετρήσεις στο σπίτι, '
      '$homeBpSys/$homeBpDia (ESC 2024).';
}

/// Πολύ υψηλή μέτρηση (16/11): από 180/110 (ESC 2024: σοβαρή υπέρταση). Μία μέτρηση μόνη της δεν είναι διάγνωση, αλλά
/// σε αυτά τα νούμερα λέγεται αμέσως τι να κάνεις.
String? bpNote(Vital v) {
  if (v.kind != VitalKind.bp || (v.sys! < 180 && v.dia! < 110)) return null;
  return 'Πολύ υψηλή. Ξαναμέτρησε σε 5 λεπτά, ήρεμος. Αν μένει τόσο ψηλά, μίλα σήμερα με γιατρό· με πόνο στο στήθος, '
      'δύσπνοια, αδυναμία ή θόλωμα στην όραση, 166 ή 112.';
}

/// Σημείωση για μία μέτρηση σακχάρου (μόνο ό,τι είναι καθαρό· όχι διάγνωση).
String? glucoseNote(Vital v) {
  final g = v.glucose!;
  if (g < 70) return 'Κάτω από 70 mg/dL: χαμηλό σάκχαρο. Αν έχεις συμπτώματα, φάε κάτι γλυκό και μίλα με τον γιατρό σου.';
  if (v.when == GlucoseWhen.fasting) {
    return g < 100
        ? 'Νηστείας κάτω από 100 mg/dL: στο φυσιολογικό (ADA).'
        : 'Νηστείας 100 και πάνω: πες το στον γιατρό σου. Ο μετρητής του σπιτιού δεν κάνει διάγνωση (ADA).';
  }
  return null;
}

abstract class VitalsIO {
  Future<({String state, String? json})> read();
  Future<bool> write(String json);
  Future<String?> setAside();
}

class ChannelVitalsIO implements VitalsIO {
  const ChannelVitalsIO();
  @override
  Future<({String state, String? json})> read() async {
    final r = await FoodChannel.vitalsRead();
    if (r['ok'] != true) return (state: r['kind'] == 'not_android' ? 'missing' : 'error', json: null);
    if (r['state'] == 'missing') return (state: 'missing', json: null);
    final j = r['json'];
    return r['state'] == 'ok' && j is String ? (state: 'ok', json: j) : (state: 'error', json: null);
  }

  @override
  Future<bool> write(String json) async => (await FoodChannel.vitalsWrite(json))['ok'] == true;

  @override
  Future<String?> setAside() async {
    final r = await FoodChannel.vitalsBad();
    return r['ok'] == true && r['name'] is String ? r['name'] as String : null;
  }
}

class MemoryVitalsIO implements VitalsIO {
  MemoryVitalsIO([this.json]);
  String? json;
  bool failWrites = false;
  @override
  Future<({String state, String? json})> read() async => json == null ? (state: 'missing', json: null) : (state: 'ok', json: json);
  @override
  Future<bool> write(String j) async {
    if (failWrites) return false;
    json = j;
    return true;
  }

  @override
  Future<String?> setAside() async {
    json = null;
    return 'vitals.json.bad';
  }
}

class VitalsStore extends ChangeNotifier {
  VitalsStore({VitalsIO? io}) : _io = io ?? const ChannelVitalsIO();
  final VitalsIO _io;

  static VitalsStore? _main;
  static VitalsStore get main => _main ??= VitalsStore()..ensureLoaded();

  List<Vital> _all = const [];
  List<Object?> _bad = const [];
  bool read = false;
  String? error;

  /// Όλες, νεότερη πρώτη.
  List<Vital> get all => _all;
  List<Vital> of(VitalKind k) => [for (final v in _all) if (v.kind == k) v];

  Future<void>? _loading;

  /// Περιμένει να διαβαστεί το αρχείο (16/11, έλεγχος: η εξαγωγή αντιγράφου και η επαναφορά δεν περίμεναν, και οι
  /// μετρήσεις έλειπαν σιωπηλά). Αν η ανάγνωση απέτυχε, ξαναδοκιμάζει.
  Future<void> ensureLoaded() async {
    if (read) return;
    await (_loading ??= load());
    _loading = null;
  }

  Future<void> load() async {
    final r = await _io.read();
    if (r.state == 'missing') {
      _all = const [];
      read = true;
      notifyListeners();
      return;
    }
    if (r.state != 'ok') {
      read = false;
      error = 'Δεν διαβάστηκαν οι μετρήσεις. Δοκίμασε ξανά αργότερα.';
      notifyListeners();
      return;
    }
    Object? j;
    try {
      j = jsonDecode(r.json!);
    } catch (_) {
      j = null;
    }
    final list = j is Map ? j['items'] : null;
    if (list is! List) {
      final name = await _io.setAside();
      read = name != null;
      _all = const [];
      error = name == null ? 'Δεν διαβάστηκαν οι μετρήσεις.' : 'Το αρχείο των μετρήσεων δεν διαβαζόταν· κρατήθηκε ($name).';
      notifyListeners();
      return;
    }
    final ok = <Vital>[], bad = <Object?>[];
    final ids = <String>{};
    for (final x in list) {
      final v = Vital.fromJson(x);
      if (v == null || !ids.add(v.id)) {
        bad.add(x);
      } else {
        ok.add(v);
      }
    }
    _all = ok..sort((a, b) => b.at.compareTo(a.at));
    _bad = bad;
    read = true;
    notifyListeners();
  }

  String _json(List<Vital> list) => jsonEncode({
        'v': 1,
        'items': [for (final v in list) v.toJson(), ..._bad],
      });

  Future<bool> _save(List<Vital> next) async {
    if (!read) return false;
    final before = _all;
    final after = _all = [...next]..sort((a, b) => b.at.compareTo(a.at));
    notifyListeners();
    if (await _io.write(_json(after))) {
      error = null;
      return true;
    }
    // Μόνο αν δεν άλλαξε κάτι άλλο στο μεταξύ (16/11, έλεγχος: αλλιώς σβηνόταν μια νεότερη αλλαγή που γράφτηκε).
    if (identical(_all, after)) _all = before;
    error = 'Δεν αποθηκεύτηκε. Δοκίμασε ξανά.';
    notifyListeners();
    return false;
  }

  Future<bool> add(Vital v) => _save([..._all.where((x) => x.id != v.id), v]);
  Future<bool> remove(Vital v) => _save([..._all.where((x) => x.id != v.id)]);

  /// Για την «Εξαγωγή αντιγράφου».
  /// Και οι γραμμές που δεν διαβάστηκαν, όπως είναι (16/11, έλεγχος: αλλιώς χάνονταν μετά από «Διαγραφή όλων»).
  List<Object?> forBackup() => [for (final v in _all) v.toJson(), ..._bad];

  /// Επαναφορά: μπαίνουν όσες λείπουν (ίδιο id = ίδια μέτρηση). Πόσες μπήκαν, ή -1 αν δεν γράφτηκε.
  Future<int> importItems(Object? j) async {
    if (j is! List || j.isEmpty) return 0;
    await ensureLoaded();
    if (!read) return -1;
    final have = {for (final v in _all) v.id};
    final add = [for (final x in j) if (Vital.fromJson(x) case final v? when have.add(v.id)) v];
    if (add.isEmpty) return 0;
    return await _save([..._all, ...add]) ? add.length : -1;
  }

  static String newId() => 'v${DateTime.now().microsecondsSinceEpoch}';
}
