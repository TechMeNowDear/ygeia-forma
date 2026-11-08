import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../exercise/ex_data.dart';
import 'equipment.dart';
import 'program.dart';
import 'session.dart';
import 'training_store.dart';

/// Τι στέλνει το κινητό στο ρολόι: το πρόγραμμα με έτοιμους στόχους ανά σετ (ίδιοι με του κινητού) και το όριο παλμών.
/// Καθαρή συνάρτηση, για να ελέγχεται. Μορφή: android/wear/…/Protocol.kt (Plan).
Map<String, dynamic> watchPlan(TrainingStore t, DateTime now, String Function(String) name) {
  final p = t.program;
  Map<String, dynamic> item(PlanItem i) {
    final tg = t.targetFor(i);
    return {
      'ex': i.ex,
      'name': name(i.ex),
      'rest': i.rest,
      'lo': i.lo,
      'hi': i.hi,
      'rir': i.rir,
      'sets': [
        for (final r in tg.reps)
          {
            if (tg.load != null) 'load': tg.load,
            'label': hasLoad(i.kind) ? loadLabel(i.kind, tg.load) : '',
            'reps': r,
          },
      ],
    };
  }

  return {
    'v': 1,
    'approved': t.approved,
    if (t.hrLimit != null) 'hrLimit': t.hrLimit,
    if (p?.forDay(now) != null) 'today': p!.forDay(now)!.id,
    // Οι μέρες, για να βρίσκει το ρολόι μόνο του τη σημερινή (και αν το κινητό δεν άνοιξε σήμερα).
    if (p != null) 'days': {for (final e in p.days.entries) '${e.key}': e.value},
    'day': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
    'workouts': [
      for (final w in p?.workouts ?? const <Workout>[])
        {
          'id': w.id,
          'name': w.name,
          'minutes': w.minutes,
          if (w.cardio != null)
            'cardio': {'activity': w.cardio!.activity, 'name': w.cardio!.name, 'minutes': w.cardio!.minutes, if (w.cardio!.note != null) 'note': w.cardio!.note},
          'items': [for (final i in w.items) item(i)],
        },
    ],
  };
}

/// Η προπόνηση που τρέχει στο κινητό, για το ρολόι (Protocol.kt: LiveSession.parsePhone).
Map<String, dynamic> watchSession(TrainingStore t, String Function(String) name) {
  final s = t.current;
  if (s == null) return {'active': false};
  return {
    'active': true,
    'id': s.id,
    'w': s.workout,
    'name': s.name,
    'start': s.start.millisecondsSinceEpoch,
    'idx': t.focus.clamp(0, s.items.isEmpty ? 0 : s.items.length - 1),
    'restEnd': t.restEnd?.millisecondsSinceEpoch ?? 0,
    'items': [
      for (final e in s.items)
        {
          'ex': e.ex,
          'name': name(e.ex),
          'rest': e.rest,
          'lo': e.lo,
          'hi': e.hi,
          'rir': e.rir,
          if (e.rirAnswer != null) 'ra': e.rirAnswer,
          'sets': [
            for (final x in e.log)
              {
                if (x.load != null) 'load': x.load,
                'label': hasLoad(e.kind) ? loadLabel(e.kind, x.load) : '',
                'reps': x.reps,
                if (x.done) 'done': true,
              },
          ],
        },
    ],
  };
}

/// Εντολή από το ρολόι στην προπόνηση του κινητού (✓, ρεζέρβα, επαναλήψεις, άσκηση, διάλειμμα).
class WatchCmd {
  WatchCmd(this.op, this.j);
  final String op;
  final Map<String, dynamic> j;
  int get i => (j['i'] as num?)?.toInt() ?? -1;
  int get s => (j['s'] as num?)?.toInt() ?? -1;
  Object? get v => j['v'];
  String get sid => j['sid'] as String? ?? '';
}

/// Σύνδεση με την εφαρμογή του ρολογιού. Δουλεύει μόνο όσο είναι ανοιχτή η εφαρμογή· τίποτα στο παρασκήνιο.
class WearLink with WidgetsBindingObserver {
  WearLink({MethodChannel? channel, EventChannel? events})
      : _m = channel ?? const MethodChannel('ygeia/wear'),
        _e = events ?? const EventChannel('ygeia/wear/events');

  static WearLink main = WearLink();

  final MethodChannel _m;
  final EventChannel _e;

  /// Υπάρχει ρολόι κοντά με την εφαρμογή μας.
  final ready = ValueNotifier<bool>(false);

  /// Τελευταίοι παλμοί από το ρολόι (και πότε ήρθαν).
  final hr = ValueNotifier<(int, DateTime)?>(null);

  /// Περπάτημα που τρέχει στο ρολόι (για την κάρτα), ή null.
  final live = ValueNotifier<Map<String, dynamic>?>(null);

  final _cmds = StreamController<WatchCmd>.broadcast();
  Stream<WatchCmd> get commands => _cmds.stream;

  TrainingStore? _t;
  StreamSubscription<dynamic>? _sub;
  String? _lastPlan;
  String? _lastSession;
  bool _started = false;

  /// Παλμοί «φρέσκοι» (τελευταία 15″).
  int? bpmAt(DateTime now) {
    final v = hr.value;
    if (v == null || now.difference(v.$2).inSeconds > 15) return null;
    return v.$1;
  }

  void start(TrainingStore t) {
    if (_started) return;
    _started = true;
    _t = t;
    WidgetsBinding.instance.addObserver(this);
    try {
      _sub = _e.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
    } catch (_) {}
    t.addListener(_publish);
    ready.addListener(_publish);
    refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  /// Κατάσταση ρολογιού, πρόγραμμα προς το ρολόι, ό,τι έγινε στο ρολόι προς το κινητό.
  Future<void> refresh() async {
    final t = _t;
    if (t == null) return;
    try {
      final st = await _m.invokeMapMethod<String, dynamic>('status');
      ready.value = ((st?['app'] as num?) ?? 0) > 0;
    } catch (_) {
      ready.value = false;
    }
    _lastPlan = null;
    _publish();
    await importResults();
  }

  Future<void> importResults() async {
    final t = _t;
    if (t == null) return;
    try {
      final list = await _m.invokeListMethod<dynamic>('takeResults') ?? const [];
      for (final r in list) {
        final m = (r as Map).cast<String, dynamic>();
        final path = m['path'] as String? ?? '';
        try {
          final j = jsonDecode(m['json'] as String) as Map<String, dynamic>;
          t.importWatch(j);
        } catch (_) {
          // Χαλασμένο: σβήνεται κι αυτό, για να μην έρχεται ξανά και ξανά.
        }
        await _m.invokeMethod<bool>('ackResult', {'path': path});
      }
    } catch (_) {}
  }

  String _name(String id) => ExLibrary.loaded?.byId(id)?.name ?? id;

  /// Στέλνει πρόγραμμα/προπόνηση μόνο όταν αλλάζουν (σύγκριση κειμένου).
  void _publish() {
    final t = _t;
    // Χωρίς ρολόι με την εφαρμογή μας: τίποτα (ούτε κλήσεις στις υπηρεσίες της Google).
    if (t == null || !t.ready || !ready.value) return;
    try {
      final plan = jsonEncode(watchPlan(t, t.now, _name));
      if (plan != _lastPlan) {
        _lastPlan = plan;
        _m.invokeMethod<bool>('putPlan', {'json': plan}).catchError((_) => false);
      }
      final sess = jsonEncode(watchSession(t, _name));
      if (sess != _lastSession) {
        // Η πρώτη φορά «όχι ενεργή» δεν χρειάζεται (δεν άλλαξε κάτι για το ρολόι).
        final skip = _lastSession == null && t.current == null;
        _lastSession = sess;
        if (!skip) _m.invokeMethod<bool>('putSession', {'json': sess}).catchError((_) => false);
      }
    } catch (_) {}
  }

  /// Ανοίγει την εφαρμογή στο ρολόι (μόλις ξεκίνησε προπόνηση στο κινητό).
  Future<bool> openWatch() async {
    if (!ready.value) return false;
    try {
      return await _m.invokeMethod<bool>('openWatch') ?? false;
    } catch (_) {
      return false;
    }
  }

  void _onEvent(dynamic e) {
    if (e is! Map) return;
    final path = e['path'] as String? ?? '';
    final text = e['json'] as String? ?? '';
    if (path == '/ygeia/result/') {
      importResults();
      return;
    }
    Map<String, dynamic> j;
    try {
      j = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    handle(path, j);
  }

  /// Ένα μήνυμα από το ρολόι (δημόσιο για τις δοκιμές).
  @visibleForTesting
  void handle(String path, Map<String, dynamic> j) {
    final t = _t;
    switch (path) {
      case '/ygeia/hr':
        final bpm = (j['bpm'] as num?)?.toInt() ?? 0;
        final at = DateTime.fromMillisecondsSinceEpoch((j['t'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch);
        if (bpm > 0) {
          hr.value = (bpm, at);
          t?.addHr(bpm, at, sid: j['sid'] as String?);
        }
        ready.value = true;
      case '/ygeia/live':
        live.value = {...j, 'at': DateTime.now().millisecondsSinceEpoch};
        final bpm = (j['bpm'] as num?)?.toInt() ?? 0;
        if (bpm > 0) hr.value = (bpm, DateTime.now());
        ready.value = true;
      case '/ygeia/cmd':
        _cmds.add(WatchCmd(j['op'] as String? ?? '', j));
    }
  }

  @visibleForTesting
  void attachForTest(TrainingStore t) {
    _t = t;
  }

  void dispose() {
    _sub?.cancel();
    _t?.removeListener(_publish);
    WidgetsBinding.instance.removeObserver(this);
    _cmds.close();
  }
}

/// Παλμοί μιας προπόνησης για εμφάνιση (μέσος, υψηλότερος, πόσο ώρα πάνω από το όριο).
class HrSummary {
  HrSummary(Session s, int? limit)
      : avg = s.hrAvg ?? (s.hr.isEmpty ? null : (s.hr.fold<int>(0, (a, p) => a + p[1]) / s.hr.length).round()),
        max = s.hrMax,
        overSec = limit == null ? 0 : _over(s.hr, limit);
  final int? avg, max;
  final int overSec;

  static int _over(List<List<int>> hr, int limit) {
    var sec = 0;
    for (var i = 0; i < hr.length; i++) {
      if (hr[i][1] < limit) continue;
      final next = i + 1 < hr.length ? hr[i + 1][0] : hr[i][0] + 10;
      sec += (next - hr[i][0]).clamp(0, 60);
    }
    return sec;
  }
}
