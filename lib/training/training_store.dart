import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../exercise/ex_data.dart';
import 'equipment.dart';
import 'progression.dart';
import 'program.dart';
import 'session.dart';
import 'symptoms.dart';

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

  /// Παίρνει φάρμακο που κόβει τους παλμούς (π.χ. β-αναστολέα): τότε μετράει η κούραση, όχι οι παλμοί.
  bool hrMeds = false;

  /// «Θέλει εξετάσεις»: ο γιατρός περιμένει αποτελέσματα· μένει κλειδωμένο.
  bool waitingTests = false;

  /// Ξανακλείδωσε (σύμπτωμα, νέο φάρμακο, ή από τον χρήστη): 'red' | 'amber2' | 'meds' | 'manual'.
  String? lockReason;
  DateTime? lockedAt;

  /// «Νιώθω κάτι»: όλες οι καταγραφές.
  final List<Symptom> symptoms = [];

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
    hrMeds = j['hrMeds'] == 1;
    waitingTests = j['tests'] == 1;
    lockReason = j['lock'] as String?;
    lockedAt = j['lockedAt'] is num ? DateTime.fromMillisecondsSinceEpoch((j['lockedAt'] as num).toInt()) : null;
    symptoms
      ..clear()
      ..addAll([for (final x in (j['sym'] as List? ?? const [])) Symptom.fromJson((x as Map).cast<String, dynamic>())]);
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
        if (hrMeds) 'hrMeds': 1,
        if (waitingTests) 'tests': 1,
        if (lockReason != null) 'lock': lockReason,
        if (lockedAt != null) 'lockedAt': lockedAt!.millisecondsSinceEpoch,
        if (symptoms.isNotEmpty) 'sym': [for (final x in symptoms) x.toJson()],
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
  void approve({int? hr, String? notes, bool? meds}) {
    approved = true;
    approvedAt = now;
    hrLimit = hr;
    limits = notes;
    if (meds != null) hrMeds = meds;
    waitingTests = false;
    lockReason = null;
    lockedAt = null;
    save();
  }

  void setLimits({int? hr, String? notes, bool? meds}) {
    hrLimit = hr;
    limits = notes;
    if (meds != null) hrMeds = meds;
    save();
  }

  /// «Θέλει εξετάσεις»: τα βάρη μένουν κλειδωμένα, κρατά τις σημειώσεις.
  void waitForTests({String? notes}) {
    approved = false;
    waitingTests = true;
    if (notes != null && notes.isNotEmpty) limits = notes;
    save();
  }

  /// Ξανά κλείδωμα της προπόνησης ([reason]: 'red' | 'amber2' | 'meds' | 'manual'). Ανοίγει με νέα έγκριση.
  void relock(String reason) {
    approved = false;
    lockReason = reason;
    lockedAt = now;
    save();
  }

  // ---------------------------------------------------------------- «Νιώθω κάτι»
  /// Καταγραφή συμπτωμάτων. Σταματά την προπόνηση που τρέχει (γράφεται ό,τι έγινε).
  /// Κόκκινο, ή δεύτερο πορτοκαλί μέσα σε 14 μέρες: κλειδώνει μέχρι «Με είδε γιατρός».
  SymptomOutcome reportSymptoms(List<String> codes, {String? where}) {
    final known = [for (final c in codes) if (symptomDef(c) != null) c];
    if (known.isEmpty) return SymptomOutcome.none;
    final at = now;
    final sid = current?.id;
    // Οι λεπτομέρειες για ένα «Νιώθω κάτι» από το ρολόι ήρθαν: φεύγει η εκκρεμότητα.
    symptoms.removeWhere((x) => x.code == watchCode);
    for (final c in known) {
      symptoms.add(Symptom(at: at, code: c, sid: sid, where: where));
    }
    final red = known.any((c) => symptomDef(c)!.red);
    // Πορτοκαλί «επεισόδια» (μία καταγραφή μπορεί να έχει πολλά) τις τελευταίες 14 μέρες.
    final amberEvents = {
      for (final x in symptoms)
        if (!x.red && x.code != watchCode && at.difference(x.at).inDays < 14) x.at.millisecondsSinceEpoch,
    }.length;
    final lock = red || amberEvents >= 2;
    if (current != null) {
      current!.note = red ? 'Σταμάτησε: κόκκινο σύμπτωμα' : 'Σταμάτησε: σύμπτωμα';
      finish();
    }
    if (lock) {
      approved = false;
      lockReason = red ? 'red' : 'amber2';
      lockedAt = at;
    }
    _restEnd = null;
    save();
    return lock ? SymptomOutcome.red : SymptomOutcome.amber;
  }

  /// «Νιώθω κάτι» στο ρολόι: γράφεται και το κινητό ρωτά τι ένιωσες μόλις ανοίξει.
  bool watchSymptom(DateTime at, {String? sid}) {
    if (symptoms.any((x) => x.code == watchCode && x.at == at)) return false;
    symptoms.add(Symptom(at: at, code: watchCode, sid: sid, where: 'watch'));
    save();
    return true;
  }

  /// Εκκρεμεί «Νιώθω κάτι» από το ρολόι χωρίς λεπτομέρειες.
  Symptom? get pendingWatchSymptom {
    for (final x in symptoms.reversed) {
      if (x.code == watchCode) return x;
    }
    return null;
  }

  /// «Τελικά τίποτα»: σβήνει η εκκρεμότητα του ρολογιού.
  void clearWatchSymptom() {
    symptoms.removeWhere((x) => x.code == watchCode);
    save();
  }

  /// Ερώτηση «Πώς είσαι σήμερα;» πριν από την προπόνηση: τις πρώτες 4 εβδομάδες μετά την έγκριση
  /// και για 14 μέρες μετά από κάθε σύμπτωμα.
  bool get needsCheck {
    if (!approved) return false;
    if (approvedAt != null && now.difference(approvedAt!).inDays < 28) return true;
    return symptoms.any((x) => now.difference(x.at).inDays < 14);
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

  Target targetFor(PlanItem item) => nextTarget(item, historyOf(item.ex), now, caution: isCaution(item.ex));

  /// Άσκηση με προσοχή στη βιβλιοθήκη. Αν η βιβλιοθήκη δεν έχει φορτώσει ακόμα: ναι, για ασφάλεια.
  static bool isCaution(String ex) {
    final lib = ExLibrary.loaded;
    return lib == null || lib.byId(ex)?.caution != null;
  }

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

  // ---------------------------------------------------------------- οθόνη προπόνησης (στη μνήμη· τη βλέπει και το ρολόι)
  int _focus = 0;

  /// Η άσκηση που δείχνει τώρα η προπόνηση (κινητό και ρολόι).
  int get focus => _focus;
  set focus(int v) {
    if (v == _focus) return;
    _focus = v;
    notifyListeners();
  }

  /// Για τη σελίδα προπόνησης, μέσα στο build/initState (χωρίς ειδοποίηση).
  void setFocusQuiet(int v) => _focus = v;

  DateTime? _restEnd;

  /// Τέλος διαλείμματος, ή null.
  DateTime? get restEnd => _restEnd;
  set restEnd(DateTime? v) {
    if (v == _restEnd) return;
    _restEnd = v;
    notifyListeners();
  }

  DateTime? _hrSaved;

  /// Παλμοί από το ρολόι για την προπόνηση που τρέχει (δείγμα ανά ~10″, αποθήκευση ανά λεπτό).
  void addHr(int bpm, DateTime at, {String? sid}) {
    final s = current;
    if (s == null || bpm <= 25 || bpm >= 250) return;
    if (sid != null && sid.isNotEmpty && sid != s.id) return;
    final sec = at.difference(s.start).inSeconds;
    if (sec < 0) return;
    if (s.hr.isEmpty || sec - s.hr.last[0] >= 10) s.hr.add([sec, bpm]);
    if (s.hrMax == null || bpm > s.hrMax!) s.hrMax = bpm;
    if (_hrSaved == null || at.difference(_hrSaved!).inSeconds >= 60) {
      _hrSaved = at;
      save();
    }
  }

  /// Ό,τι έγινε μόνο στο ρολόι (προπόνηση, περπάτημα) ή οι παλμοί μιας προπόνησης του κινητού. true αν άλλαξε κάτι.
  bool importWatch(Map<String, dynamic> j) {
    final kind = j['kind'] as String? ?? 'strength';
    final samples = [
      for (final p in (j['hr'] as List? ?? const []))
        if (p is List && p.length == 2) [(p[0] as num).toInt(), (p[1] as num).toInt()],
    ];
    final hrAvg = (j['hrAvg'] as num?)?.toInt();
    final hrMax = (j['hrMax'] as num?)?.toInt();
    if (kind == 'sym') {
      final at = DateTime.fromMillisecondsSinceEpoch((j['at'] as num? ?? now.millisecondsSinceEpoch).toInt());
      return watchSymptom(at, sid: j['sid'] as String?);
    }
    if (kind == 'hr') {
      final sid = j['sid'] as String?;
      Session? s;
      for (final x in [...sessions, if (current != null) current!]) {
        if (x.id == sid) s = x;
      }
      if (s == null) return false;
      if (samples.length > s.hr.length) {
        s.hr
          ..clear()
          ..addAll(samples);
      }
      if (hrMax != null && (s.hrMax == null || hrMax > s.hrMax!)) s.hrMax = hrMax;
      if (hrAvg != null) s.hrAvg = hrAvg;
      _mergeWatchSets(s, j['items']);
      save();
      return true;
    }
    final id = 'w-${j['id']}';
    if (sessions.any((x) => x.id == id)) return false;
    final start = DateTime.fromMillisecondsSinceEpoch((j['start'] as num).toInt());
    final end = DateTime.fromMillisecondsSinceEpoch((j['end'] as num? ?? j['start'] as num).toInt());
    final cardio = kind == 'cardio' ? (j['cardio'] as Map?)?.cast<String, dynamic>() ?? const {} : null;
    final s = Session(
      id: id,
      workout: j['w'] as String? ?? '',
      name: j['name'] as String? ?? (cardio != null ? 'Περπάτημα' : 'Προπόνηση'),
      programId: program?.id ?? '',
      start: start,
      end: end,
      items: cardio != null ? [] : [for (final e in (j['items'] as List? ?? const [])) ExLog.fromJson((e as Map).cast<String, dynamic>())],
      hrAvg: hrAvg,
      hrMax: hrMax,
      hr: samples,
      source: 'watch',
    );
    if (cardio != null) {
      final sec = (cardio['sec'] as num?)?.toInt() ?? end.difference(start).inSeconds;
      s.cardioMinutes = (sec / 60).round();
      s.meters = (cardio['m'] as num?)?.toDouble();
      s.steps = (cardio['steps'] as num?)?.toInt();
    }
    var at = sessions.length;
    while (at > 0 && sessions[at - 1].start.isAfter(start)) {
      at--;
    }
    sessions.insert(at, s);
    save();
    return true;
  }

  /// Σετ που πατήθηκαν ✓ στο ρολόι αλλά δεν έφτασαν στο κινητό (π.χ. η εφαρμογή ήταν κλειστή): προστίθενται.
  /// Ποτέ δεν σβήνει ή αλλάζει ό,τι έχει ήδη γραφτεί στο κινητό.
  void _mergeWatchSets(Session s, Object? items) {
    if (items is! List) return;
    for (var i = 0; i < items.length && i < s.items.length; i++) {
      final raw = items[i];
      if (raw is! Map) continue;
      final ExLog w;
      try {
        w = ExLog.fromJson(raw.cast<String, dynamic>());
      } catch (_) {
        continue;
      }
      final e = s.items[i];
      if (w.ex != e.ex || e.skipped) continue;
      for (var k = 0; k < w.log.length && k < e.log.length; k++) {
        final ws = w.log[k], ps = e.log[k];
        if (!ws.done || ps.done) continue;
        ps
          ..done = true
          ..reps = ws.reps
          ..at = ws.at;
        if (ws.load != null) ps.load = ws.load;
      }
      if (e.rirAnswer == null && w.rirAnswer != null && e.complete) e.rirAnswer = w.rirAnswer!.clamp(0, 4);
    }
  }

  Session start(Workout w) {
    final p = program!;
    _focus = 0;
    _restEnd = null;
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
    if (s.hr.isNotEmpty) s.hrAvg = (s.hr.fold<int>(0, (a, p) => a + p[1]) / s.hr.length).round();
    sessions.add(s);
    current = null;
    _restEnd = null;
    save();
  }

  void discard() {
    current = null;
    _restEnd = null;
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
    if (hrMeds) b.writeln('Παίρνω φάρμακο που κόβει τους παλμούς: μετράει η κούραση, όχι οι παλμοί.');
    if (!approved) b.writeln('Η προπόνηση με βάρη είναι κλειδωμένη${waitingTests ? ' (περιμένω εξετάσεις)' : lockReason != null ? ' (ξανακλείδωσε ${_d(lockedAt ?? now)})' : ''}.');
    final syms = [for (final x in symptoms) if (x.at.isAfter(since) && x.code != watchCode) x];
    if (syms.isNotEmpty) {
      b.writeln('Συμπτώματα («Νιώθω κάτι»):');
      for (final x in syms) {
        b.writeln('- ${_d(x.at)}: ${x.red ? 'ΚΟΚΚΙΝΟ' : 'πορτοκαλί'}, ${x.text}');
      }
    }
    final walks = [for (final s in list) if (s.isCardio) s];
    b.writeln('Προπονήσεις με βάρη: ${list.length - walks.length}');
    if (walks.isNotEmpty) {
      final km = walks.fold<double>(0, (a, s) => a + (s.meters ?? 0)) / 1000;
      final mins = walks.fold<int>(0, (a, s) => a + (s.cardioMinutes ?? 0));
      b.writeln('Περπάτημα: ${walks.length} φορές, $mins λεπτά${km > 0 ? ', ${km.toStringAsFixed(1)} km' : ''}');
    }
    final hrAvgs = [for (final s in list) if (s.hrAvg != null) s.hrAvg!];
    if (hrAvgs.isNotEmpty) b.writeln('Μέσοι παλμοί ανά προπόνηση: ${hrAvgs.join(', ')}');
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

  /// Επαναφορά από αντίγραφο: προσθέτει μόνο ό,τι λείπει (προγράμματα, προπονήσεις, συμπτώματα). Ποτέ η έγκριση
  /// του γιατρού και το όριο παλμών: αυτά τα ξαναλές (έλεγχος 8/11, TRN-17). Επιστρέφει πόσες προπονήσεις μπήκαν.
  int mergeBackup(Map<String, dynamic> j) {
    if (readError || !ready) return 0;
    final other = TrainingStore(io: _io, clock: _clock);
    try {
      other._fromJson(j);
    } catch (_) {
      return 0;
    }
    final have = {for (final p in programs) '${p.id}#${p.version}'};
    for (final p in other.programs) {
      if (have.add('${p.id}#${p.version}')) programs.add(p);
    }
    activeId ??= other.activeId;
    final ids = {for (final s in sessions) s.id};
    var added = 0;
    for (final s in other.sessions) {
      if (ids.add(s.id)) {
        sessions.add(s);
        added++;
      }
    }
    sessions.sort((a, b) => a.start.compareTo(b.start));
    final syms = {for (final x in symptoms) '${x.at.millisecondsSinceEpoch}|${x.code}'};
    for (final x in other.symptoms) {
      if (syms.add('${x.at.millisecondsSinceEpoch}|${x.code}')) symptoms.add(x);
    }
    symptoms.sort((a, b) => a.at.compareTo(b.at));
    save();
    return added;
  }
}
