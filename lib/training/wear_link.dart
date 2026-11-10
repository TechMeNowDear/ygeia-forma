import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../exercise/ex_data.dart';
import 'equipment.dart';
import 'program.dart';
import 'session.dart';
import 'training_device.dart';
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
      'rir': i.rir < 2 ? 2 : i.rir,
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
    // Πάντα ανοιχτό (δεν υπάρχει πια κλείδωμα· το κλειδί μένει για ρολόι με παλιά έκδοση).
    'approved': true,
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
  // «v»: η μορφή (Protocol.kt: Proto.MAJOR). Το παλιό ρολόι το αγνοεί· το νέο δεν διαβάζει νεότερη (V-A-08).
  if (s == null) return {'v': TrainingStore.watchMajor, 'active': false};
  return {
    'v': TrainingStore.watchMajor,
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

  /// Το όριο παλμών που στάλθηκε στο ρολόι σε αυτό το άνοιγμα της εφαρμογής («140», «null» = χωρίς όριο), ή null αν
  /// δεν στάλθηκε ακόμα. Για την κάρτα ορίου (έλεγχος 9/11, V-A-05): να φαίνεται αν το ρολόι το πήρε.
  final sentLimit = ValueNotifier<String?>(null);

  /// Το όριο που ΕΠΙΒΕΒΑΙΩΣΕ το ρολόι ότι έχει («140», «null» = χωρίς όριο), ή null αν δεν έχει πει τίποτα (ρολόι
  /// παλιότερης έκδοσης, ή η εφαρμογή του ρολογιού δεν άνοιξε ακόμα). Έλεγχος 9/11, V-A-06: «Στο ρολόι ✓ όριο 140».
  final watchLimit = ValueNotifier<String?>(null);

  /// Το ρολόι έστειλε αποτέλεσμα νεότερης μορφής (V-A-08): «Ενημέρωσε την εφαρμογή στο κινητό»· περιμένει εκεί.
  final watchNewer = ValueNotifier<bool>(false);

  /// Υπάρχει (γνωστό) ρολόι με την εφαρμογή, κι ας μην είναι κοντά τώρα: το πρόγραμμα/όριο γράφεται και φτάνει μόλις
  /// συνδεθούν (DataItem). Χωρίς κανένα ρολόι: καμία κλήση.
  bool _known = false;

  final _cmds = StreamController<WatchCmd>.broadcast();
  Stream<WatchCmd> get commands => _cmds.stream;

  TrainingStore? _t;
  StreamSubscription<dynamic>? _sub;
  String? _lastPlan;
  String? _lastSafety;
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
      _known = ready.value || ((st?['known'] as num?) ?? 0) > 0;
    } catch (_) {
      ready.value = false;
    }
    await readWatchState();
    _lastPlan = null;
    _publish();
    await importResults();
  }

  /// Τι λέει το ρολόι για τον εαυτό του (DataItem του ρολογιού).
  Future<void> readWatchState() async {
    try {
      final text = await _m.invokeMethod<String>('watchState');
      if (text != null) applyWatchState(text);
    } catch (_) {}
  }

  /// Το όριο που έχει το ρολόι (0 = χωρίς όριο).
  @visibleForTesting
  void applyWatchState(String text) {
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      final lim = (j['lim'] as num?)?.toInt();
      if (lim == null) return;
      watchLimit.value = lim > 0 ? '$lim' : 'null';
    } catch (_) {}
  }

  /// Ό,τι έγινε στο ρολόι, προς το κινητό. Το ρολόι σβήνει το αποτέλεσμα (ack) ΜΟΝΟ αφού γραφτεί με ασφάλεια εδώ
  /// ([importDurably]): αλλιώς μένει στο ρολόι και ξαναδοκιμάζεται στο επόμενο άνοιγμα (έλεγχος 9/11, V-A-01).
  Future<void> importResults() async {
    final t = _t;
    if (t == null) return;
    try {
      final list = await _m.invokeListMethod<dynamic>('takeResults') ?? const [];
      for (final r in list) {
        final m = (r as Map).cast<String, dynamic>();
        final path = m['path'] as String? ?? '';
        if (path.isEmpty) continue;
        if (await importDurably(t, m['json'], onNewer: () => watchNewer.value = true)) {
          await _m.invokeMethod<bool>('ackResult', {'path': path});
        }
      }
    } catch (_) {}
  }

  /// Ένα αποτέλεσμα του ρολογιού στην αποθήκη. true μόνο όταν είναι γραμμένο στο αρχείο του κινητού (ή ήταν ήδη)·
  /// ποτέ με `readError`, με αποτέλεσμα που δεν διαβάζεται (π.χ. νεότερη μορφή από ρολόι νεότερης έκδοσης) ή με
  /// αποτυχημένη εγγραφή. Ό,τι δεν διαβάζεται μένει στο ρολόι (λίγα KB) ώσπου να το διαβάσει νεότερη έκδοση.
  /// Αποτέλεσμα νεότερης μορφής («v» μεγαλύτερο από [TrainingStore.watchMajor], V-A-08): ούτε εισάγεται ούτε σβήνεται
  /// από το ρολόι· [onNewer] για το «Ενημέρωσε την εφαρμογή στο κινητό».
  @visibleForTesting
  static Future<bool> importDurably(TrainingStore t, Object? raw, {void Function()? onNewer}) async {
    if (t.readError || !t.ready || raw is! String) return false;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final v = j['v'];
      if (v is num && v > TrainingStore.watchMajor) {
        onNewer?.call();
        return false;
      }
      t.importWatch(j);
    } catch (_) {
      return false;
    }
    return t.flush();
  }

  String _name(String id) => ExLibrary.loaded?.byId(id)?.name ?? id;

  /// Στέλνει πρόγραμμα/προπόνηση μόνο όταν αλλάζουν (σύγκριση κειμένου).
  void _publish() {
    final t = _t;
    // Χωρίς κανένα ρολόι με την εφαρμογή μας: τίποτα (ούτε κλήσεις στις υπηρεσίες της Google). Με ρολόι που δεν είναι
    // κοντά τώρα: γράφεται, και φτάνει μόλις συνδεθούν (έλεγχος 9/11, V-A-06· πριν: δεν γραφόταν καθόλου).
    if (t == null || !t.ready || !(ready.value || _known)) return;
    try {
      final plan = jsonEncode(watchPlan(t, t.now, _name));
      if (plan != _lastPlan) {
        _lastPlan = plan;
        // Το όριο παλμών άλλαξε: να φτάσει αμέσως, όχι όποτε βολέψει το σύστημα.
        final safety = '${t.hrLimit}';
        final urgent = safety != _lastSafety;
        _lastSafety = safety;
        void failed() {
          // Δεν στάλθηκε: ξανά με την επόμενη αλλαγή ή επιστροφή στην εφαρμογή (όχι «Στέλνεται…» για πάντα).
          if (_lastPlan == plan) {
            _lastPlan = null;
            _lastSafety = null;
          }
        }

        _m.invokeMethod<bool>('putPlan', {'json': plan, 'urgent': urgent}).then((ok) {
          if (ok != true) {
            failed();
          } else if ('${_t?.hrLimit}' == safety) {
            sentLimit.value = safety;
          }
        }).catchError((Object _) {
          failed();
        });
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
    if (path == '/ygeia/wstate') {
      applyWatchState(text);
      return;
    }
    // Το ρολόι ήρθε κοντά ή έφυγε: ξανά κατάσταση, όριο, αποτελέσματα (μόνο όσο είναι ανοιχτή η εφαρμογή).
    if (path == 'cap') {
      refresh();
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
        // Εντολή νεότερης μορφής: δεν εκτελείται (V-A-08). Η έκδοση στο «pv»· το «v» εδώ είναι η τιμή (ρεζέρβα κ.λπ.).
        final pv = j['pv'];
        if (pv is num && pv > TrainingStore.watchMajor) return;
        final c = WatchCmd(j['op'] as String? ?? '', j);
        if (t != null) apply(t, c);
        _cmds.add(c);
    }
  }

  /// Εντολή από το ρολόι, κατευθείαν στην αποθήκη: γράφεται ακόμα κι αν η οθόνη της προπόνησης
  /// δεν είναι ανοιχτή (έλεγχος 8/11). Ίδια αποτελέσματα με τα πατήματα στο κινητό, χωρίς φύλλα ερωτήσεων.
  void apply(TrainingStore t, WatchCmd c) {
    final s = t.current;
    if (s == null || (c.sid.isNotEmpty && c.sid != s.id)) return;
    switch (c.op) {
      case 'end':
        // «Τέλος» στο ρολόι (V-A-09): τέλος και εδώ, με την ώρα του ρολογιού.
        final at = c.j['at'];
        if (at is num) {
          t.endFromWatch(s.id, at.toInt());
          TrainingDevice.restCancel();
        }
        return;
      case 'goto':
        if (c.i >= 0 && c.i < s.items.length) t.focus = c.i;
        return;
      case 'rest':
        if (c.v == 'plus') {
          final end = (t.restEnd ?? t.now).add(const Duration(seconds: 30));
          t.restEnd = end;
          TrainingDevice.rest(end, title: 'Διάλειμμα', text: 'Συνέχισε όταν τελειώσει', doneTitle: 'Τέλος διαλείμματος', doneText: 'Επόμενο σετ');
        } else {
          t.restEnd = null;
          TrainingDevice.restCancel();
        }
        return;
    }
    if (c.i < 0 || c.i >= s.items.length) return;
    final e = s.items[c.i];
    switch (c.op) {
      case 'tick':
        if (c.s < 0 || c.s >= e.log.length || e.log[c.s].done) return;
        t.tick(e, c.s, at: (c.j['at'] as num?)?.toInt());
        String? next;
        if (e.complete) {
          final n = s.items.indexWhere((x) => !x.skipped && !x.complete);
          if (n >= 0) {
            if (c.j['late'] != true) t.focus = n;
            next = _name(s.items[n].ex);
          } else if (s.isFree) {
            // Ελεύθερη άσκηση: η επόμενη θα διαλεχτεί στο κινητό· διάλειμμα όπως στο κινητό (session_page._done).
            next = 'νέα άσκηση';
          }
        } else {
          next = '${_name(e.ex)} · σετ ${e.done.length + 1}';
        }
        // Ξανασταλμένο ✓ που είχε χαθεί (έλεγχος #2): γράφεται, χωρίς νέο διάλειμμα για ένα σετ του παρελθόντος.
        if (next != null && e.rest > 0 && c.j['late'] != true) {
          final end = t.now.add(Duration(seconds: e.rest));
          t.restEnd = end;
          TrainingDevice.rest(end, title: 'Διάλειμμα', text: 'Επόμενο: $next', doneTitle: 'Τέλος διαλείμματος', doneText: 'Επόμενο: $next');
        }
      case 'rir':
        // Μόνο για άσκηση που τελείωσε και δεν έχει ήδη απάντηση (να μη γραφτεί σε λάθος άσκηση).
        final v = c.v;
        if (v is num && e.complete && e.rirAnswer == null) t.answer(e, v.toInt().clamp(0, 4));
      case 'reps':
        final v = c.v;
        if (v is num && c.s >= 0 && c.s < e.log.length) t.setReps(e, c.s, v.toInt());
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
