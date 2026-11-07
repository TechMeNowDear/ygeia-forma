import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'equipment.dart';
import 'progression.dart';
import 'program.dart';
import 'session.dart';

/// Ανάγνωση/εγγραφή του training.json (μέσω Kotlin, ατομική εγγραφή· μπαίνει στο κρυπτογραφημένο αντίγραφο).
abstract class TrainingIO {
  Future<({String state, String? json})> read();
  Future<bool> write(String json);
}

class ChannelTrainingIO implements TrainingIO {
  const ChannelTrainingIO();
  static const channel = MethodChannel('ygeia/training');

  @override
  Future<({String state, String? json})> read() async {
    try {
      final raw = await channel.invokeMethod<String>('read');
      if (raw == null) return (state: 'error', json: null);
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return (state: j['state'] as String? ?? 'error', json: j['json'] as String?);
    } on MissingPluginException {
      return (state: 'missing', json: null);
    } catch (_) {
      return (state: 'error', json: null);
    }
  }

  @override
  Future<bool> write(String json) async {
    try {
      return await channel.invokeMethod<bool>('write', {'json': json}) ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Για δοκιμές: στη μνήμη.
class MemoryTrainingIO implements TrainingIO {
  MemoryTrainingIO([this.json]);
  String? json;
  int writes = 0;
  @override
  Future<({String state, String? json})> read() async => (state: json == null ? 'missing' : 'ok', json: json);
  @override
  Future<bool> write(String j) async {
    json = j;
    writes++;
    return true;
  }
}

/// Όλη η προπόνηση: έγκριση γιατρού, προγράμματα (με εκδόσεις), προπονήσεις που έγιναν, η τρέχουσα.
class TrainingStore extends ChangeNotifier {
  TrainingStore({TrainingIO? io, DateTime Function()? clock})
      : _io = io ?? const ChannelTrainingIO(),
        _clock = clock ?? DateTime.now;

  /// Η κοινή αποθήκη της εφαρμογής (ορίζεται στο main· οι δοκιμές βάζουν δική τους).
  static TrainingStore main = TrainingStore();

  final TrainingIO _io;
  final DateTime Function() _clock;
  DateTime get now => _clock();

  bool ready = false;

  /// Η ανάγνωση απέτυχε (το αρχείο υπάρχει αλλά δεν διαβάστηκε): τίποτα δεν γράφεται, για να μη χαθεί.
  bool readError = false;
  String? saveError;

  bool approved = false;
  DateTime? approvedAt;

  /// Όριο παλμών από τον καρδιολόγο (bpm), αν έδωσε.
  int? hrLimit;

  /// Περιορισμοί από τον γιατρό, όπως τους έγραψε ο χρήστης.
  String? limits;

  /// Όλες οι εκδόσεις όλων των προγραμμάτων (η πιο πρόσφατη στο τέλος).
  final List<Program> programs = [];
  String? activeId;
  final List<Session> sessions = [];
  Session? current;

  Future<void>? _loading;
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final r = await _io.read();
    if (r.state == 'ok' && r.json != null) {
      try {
        _fromJson(jsonDecode(r.json!) as Map<String, dynamic>);
      } catch (_) {
        readError = true;
      }
    } else if (r.state == 'error') {
      readError = true;
    }
    ready = true;
    notifyListeners();
  }

  void _fromJson(Map<String, dynamic> j) {
    approved = j['approved'] == true;
    approvedAt = j['approvedAt'] is num ? DateTime.fromMillisecondsSinceEpoch((j['approvedAt'] as num).toInt()) : null;
    hrLimit = (j['hrLimit'] as num?)?.toInt();
    limits = j['limits'] as String?;
    programs
      ..clear()
      ..addAll([for (final p in (j['programs'] as List? ?? const [])) Program.fromJson(p as Map<String, dynamic>)]);
    activeId = j['active'] as String?;
    sessions
      ..clear()
      ..addAll([for (final s in (j['sessions'] as List? ?? const [])) Session.fromJson(s as Map<String, dynamic>)]);
    current = j['current'] is Map ? Session.fromJson(j['current'] as Map<String, dynamic>) : null;
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'approved': approved,
        if (approvedAt != null) 'approvedAt': approvedAt!.millisecondsSinceEpoch,
        if (hrLimit != null) 'hrLimit': hrLimit,
        if (limits != null && limits!.isNotEmpty) 'limits': limits,
        'programs': [for (final p in programs) p.toJson()],
        if (activeId != null) 'active': activeId,
        'sessions': [for (final s in sessions) s.toJson()],
        if (current != null) 'current': current!.toJson(),
      };

  Future<void> _queue = Future.value();

  /// Κάθε αλλαγή γράφεται αμέσως (με σειρά): αν κλείσει η εφαρμογή στη μέση της προπόνησης, δεν χάνεται σετ.
  Future<void> save() {
    notifyListeners();
    if (readError) return Future.value();
    final text = jsonEncode(toJson());
    _queue = _queue.then((_) async {
      final ok = await _io.write(text);
      final err = ok ? null : 'Δεν αποθηκεύτηκε η τελευταία αλλαγή στο κινητό.';
      if (err != saveError) {
        saveError = err;
        notifyListeners();
      }
    });
    return _queue;
  }

  // ---------------------------------------------------------------- έγκριση
  void approve({int? hr, String? notes}) {
    approved = true;
    approvedAt = now;
    hrLimit = hr;
    limits = notes;
    save();
  }

  void setLimits({int? hr, String? notes}) {
    hrLimit = hr;
    limits = notes;
    save();
  }

  // ---------------------------------------------------------------- προγράμματα
  /// Το ενεργό πρόγραμμα (η τελευταία έκδοση).
  Program? get program {
    if (activeId == null) return null;
    Program? p;
    for (final x in programs) {
      if (x.id == activeId) p = x;
    }
    return p;
  }

  /// Αποθηκεύει ως νέα έκδοση (ίδιο id → έκδοση +1) και το κάνει ενεργό.
  Program saveProgram(Program p, {String author = 'user'}) {
    final prev = [for (final x in programs) if (x.id == p.id) x];
    final copy = p.copy()
      ..author = author
      ..version = prev.isEmpty ? 1 : prev.last.version + 1
      ..savedAt = now;
    copy.from ??= DateTime(now.year, now.month, now.day);
    programs.add(copy);
    activeId = copy.id;
    save();
    return copy;
  }

  // ---------------------------------------------------------------- ιστορικό
  /// Οι προηγούμενες φορές μιας άσκησης, νεότερη πρώτη.
  List<(DateTime, ExLog)> historyOf(String ex) {
    final out = <(DateTime, ExLog)>[];
    for (final s in sessions.reversed) {
      if (!s.finished) continue;
      for (final e in s.items) {
        if (e.ex == ex) out.add((s.start, e));
      }
    }
    return out;
  }

  Target targetFor(PlanItem item) => nextTarget(item, historyOf(item.ex), now);

  /// Οι προπονήσεις της εβδομάδας (Δευτέρα–Κυριακή) της μέρας [day].
  List<Session> weekOf(DateTime day) {
    final monday = DateTime(day.year, day.month, day.day - (day.weekday - 1));
    final next = DateTime(monday.year, monday.month, monday.day + 7);
    return [for (final s in sessions) if (!s.start.isBefore(monday) && s.start.isBefore(next)) s];
  }

  // ---------------------------------------------------------------- προπόνηση σε εξέλιξη
  ExLog _logFor(PlanItem item) {
    final t = targetFor(item);
    return ExLog(
      ex: item.ex,
      sets: item.sets,
      lo: item.lo,
      hi: item.hi,
      rir: item.rir,
      rest: item.rest,
      log: [for (final r in t.reps) SetLog(load: t.load, reps: r)],
      reason: t.reason,
    );
  }

  Session start(Workout w) {
    final p = program!;
    final s = Session(
      id: 's${now.millisecondsSinceEpoch}',
      workout: w.id,
      name: w.name,
      programId: p.id,
      start: now,
      items: [for (final i in w.items) _logFor(i)],
    );
    current = s;
    save();
    return s;
  }

  PlanItem? itemOf(ExLog e) {
    final w = program?.workout(current?.workout);
    if (w == null) return null;
    for (final i in w.items) {
      if (i.ex == e.ex || i.ex == e.swappedFrom) return i;
    }
    return null;
  }

  /// Πρώτη φορά για αυτή την άσκηση (χωρίς ιστορικό): μετά το 1ο σετ ρωτάμε για βαθμονόμηση.
  bool isFirstTime(String ex) => historyOf(ex).isEmpty;

  void tick(ExLog e, int i) {
    final s = e.log[i];
    s.done = true;
    s.at = now.millisecondsSinceEpoch;
    save();
  }

  void untick(ExLog e, int i) {
    e.log[i]
      ..done = false
      ..at = null;
    save();
  }

  /// Αλλάζει φορτίο σε ένα σετ και σε όσα ακολουθούν και δεν έχουν γίνει.
  void setLoad(ExLog e, int i, double v) {
    for (var k = i; k < e.log.length; k++) {
      if (k == i || !e.log[k].done) e.log[k].load = v;
    }
    save();
  }

  void setReps(ExLog e, int i, int r) {
    e.log[i].reps = r.clamp(0, 99);
    save();
  }

  void addSet(ExLog e) {
    final last = e.log.isEmpty ? null : e.log.last;
    e.log.add(SetLog(load: last?.load, reps: last?.reps ?? e.lo));
    save();
  }

  void answer(ExLog e, int rir) {
    e.rirAnswer = rir;
    save();
  }

  /// Βαθμονόμηση πρώτης φοράς: μετά το 1ο σετ, πρόταση για τα επόμενα. Επιστρέφει το νέο βάρος ή null.
  double? calibrateAfterFirst(ExLog e, int rir) {
    final item = itemOf(e);
    if (item == null || e.log.isEmpty) return null;
    final first = e.log.first;
    final v = calibrate(item, first.load, first.reps, rir);
    if (v != null) {
      for (var k = 1; k < e.log.length; k++) {
        if (!e.log[k].done) e.log[k].load = v;
      }
      save();
    }
    return v;
  }

  void togglePain(ExLog e, String part) {
    e.pain.contains(part) ? e.pain.remove(part) : e.pain.add(part);
    save();
  }

  void skip(ExLog e, bool v) {
    e.skipped = v;
    save();
  }

  /// Αλλαγή άσκησης στη μέση της προπόνησης (από τις εναλλακτικές): νέος στόχος από το ιστορικό της.
  void swap(ExLog e, String ex) {
    final cur = current;
    if (cur == null) return;
    final idx = cur.items.indexOf(e);
    if (idx < 0) return;
    final base = itemOf(e);
    final item = PlanItem(ex: ex, sets: e.sets, lo: e.lo, hi: e.hi, rir: e.rir, rest: e.rest, load: base?.ex == ex ? base?.load : null);
    final n = _logFor(item)..swappedFrom = e.swappedFrom ?? e.ex;
    cur.items[idx] = n;
    save();
  }

  void finish({int? feel}) {
    final s = current;
    if (s == null) return;
    s
      ..end = now
      ..feel = feel;
    sessions.add(s);
    current = null;
    save();
  }

  void discard() {
    current = null;
    save();
  }

  // ---------------------------------------------------------------- για τον Claude
  /// Σύνοψη για επικόλληση στη συζήτηση: πρόγραμμα, πρόοδος ανά άσκηση, ενοχλήσεις, παλμοί, πώς ένιωσες.
  String exportForClaude({int weeks = 8, Map<String, String> names = const {}}) {
    final since = now.subtract(Duration(days: weeks * 7));
    final list = [for (final s in sessions) if (s.finished && s.start.isAfter(since)) s];
    final b = StringBuffer();
    final p = program;
    b.writeln('Υγεία & Φόρμα · σύνοψη προπόνησης (${_d(since)}–${_d(now)})');
    if (p != null) b.writeln('Πρόγραμμα: ${p.name} (έκδοση ${p.version}, ${p.author == 'claude' ? 'από τον Claude' : 'δικό μου'}), id ${p.id}');
    if (hrLimit != null) b.writeln('Όριο παλμών γιατρού: $hrLimit');
    if (limits != null && limits!.isNotEmpty) b.writeln('Περιορισμοί γιατρού: $limits');
    b.writeln('Προπονήσεις: ${list.length}');
    final feels = [for (final s in list) if (s.feel != null) s.feel!];
    if (feels.isNotEmpty) b.writeln('Πώς ένιωσα (1 πολύ εύκολα – 5 πολύ δύσκολα): μέσος ${(feels.reduce((a, c) => a + c) / feels.length).toStringAsFixed(1)}');
    final hrs = [for (final s in list) if (s.hrMax != null) s.hrMax!];
    if (hrs.isNotEmpty) b.writeln('Υψηλότεροι παλμοί: ${hrs.reduce((a, c) => a > c ? a : c)}');
    final byEx = <String, List<(DateTime, ExLog)>>{};
    for (final s in list) {
      for (final e in s.items) {
        if (!e.skipped && e.done.isNotEmpty) (byEx[e.ex] ??= []).add((s.start, e));
      }
    }
    for (final entry in byEx.entries) {
      final logs = entry.value;
      final first = logs.first.$2, last = logs.last.$2;
      final k = loadKindOf(entry.key);
      final reps = last.done.map((s) => s.reps).join(', ');
      final painN = logs.where((l) => l.$2.pain.isNotEmpty).length;
      b.write('- ${names[entry.key] ?? entry.key} [${entry.key}]: ${logs.length}×, ');
      if (hasLoad(k)) b.write('${loadLabel(k, first.workLoad)} → ${loadLabel(k, last.workLoad)}, ');
      b.write('τελευταία ${_d(logs.last.$1)}: $reps');
      if (last.rirAnswer != null) b.write(', ρεζέρβα ${last.rirAnswer == 4 ? '4+' : last.rirAnswer}');
      if (painN > 0) b.write(', ενόχληση $painN φορές (${{for (final l in logs) ...l.$2.pain}.map((x) => painNames[x] ?? x).join(', ')})');
      b.writeln();
    }
    if (p != null) {
      b.writeln();
      b.writeln('Το τρέχον πρόγραμμα (για αλλαγές):');
      b.writeln(jsonEncode(p.toJson()));
    }
    return b.toString();
  }

  static String _d(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @visibleForTesting
  void replaceAll(Map<String, dynamic> j) => _fromJson(j);
}
