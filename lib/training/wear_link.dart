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
    // Ζώνη περπατήματος (12/11). Νέο πεδίο: το παλιό ρολόι το αγνοεί. Το όριο γιατρού, αν υπάρχει, νικά στο ρολόι.
    if (t.zone != null) 'zone': t.zone!.toJson(),
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
          // Παραλείφθηκε εδώ (έλεγχος γ2, W2-06): το ρολόι δεν πηγαίνει εκεί. Νέο πεδίο: το παλιό ρολόι το αγνοεί.
          if (e.skipped) 'skip': 1,
          'sets': [
            for (final x in e.log)
              {
                if (x.load != null) 'load': x.load,
                'label': hasLoad(e.kind) ? loadLabel(e.kind, x.load) : '',
                'reps': x.reps,
                if (x.done) 'done': true,
                // Η ώρα του ✓ (έλεγχος του γ2, S3): το ρολόι δείχνει «έκανες × 8» στο διάλειμμα και για ✓ του κινητού.
                // Νέο πεδίο: το παλιό ρολόι το αγνοεί.
                if (x.done && x.at != null) 'at': x.at,
              },
          ],
        },
    ],
  };
}

/// Οι επαναλήψεις που κουβαλά ένα ✓ του ρολογιού («r», τελικός έλεγχος, Συμβούλιο 4, W-4), για την άσκηση [ex] του
/// κινητού: 0–99, ή null αν το ✓ δεν έχει επαναλήψεις (δεν τις άλλαξες στο ρολόι, ή ρολόι παλιότερης έκδοσης), ή αν
/// αφορούν άλλη άσκηση (στο μεταξύ την άλλαξες στο κινητό).
/// Ακέραιος από μήνυμα του ρολογιού (τελικός έλεγχος, Συμβούλιο 6): μόνο πεπερασμένος αριθμός. Κείμενο, null ή 1e999
/// (στο JSON γίνεται «άπειρο») μετρούν ως «λείπει». Πριν, το `as num` ή το `toInt()` πετούσαν σφάλμα στη μέση της
/// εντολής: το μήνυμα χανόταν, και στο ✓ μπορούσαν να έχουν ήδη γραφτεί οι επαναλήψεις χωρίς το ✓.
int? wearInt(Object? v) => v is num && v.isFinite ? v.toInt() : null;

/// Ώρα από μήνυμα του ρολογιού (ms από το 1970), ή null αν δεν είναι αριθμός που χωρά σε ημερομηνία.
DateTime? wearTime(Object? v) {
  final ms = wearInt(v);
  return ms == null || ms.abs() > 8640000000000000 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

int? watchTickReps(Map<String, dynamic> j, String ex) {
  final r = j['r'];
  final forEx = j['ex'];
  if (r is! num || !r.isFinite) return null;
  if (forEx is String && forEx != ex) return null;
  return r.toInt().clamp(0, 99);
}

/// Εντολή από το ρολόι στην προπόνηση του κινητού (✓, ρεζέρβα, επαναλήψεις, άσκηση, διάλειμμα).
class WatchCmd {
  WatchCmd(this.op, this.j);
  final String op;
  final Map<String, dynamic> j;
  int get i => wearInt(j['i']) ?? -1;
  int get s => wearInt(j['s']) ?? -1;
  Object? get v => j['v'];
  String get sid => j['sid'] is String ? j['sid'] as String : '';
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

  /// Το ρολόι είπε ότι με σβηστή οθόνη στέλνει παλμούς αργά (ούτε ανά 5″ ούτε αισθητήρας αφύπνισης· έλεγχος του γ2,
  /// S1): η κάρτα ορίου το λέει πριν από την άσκηση. false = δεν το είπε (ή ρολόι παλιότερης έκδοσης).
  final watchSlow = ValueNotifier<bool>(false);

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

  /// Ο τελευταίος αύξων αριθμός («q») που εφαρμόστηκε για τις επαναλήψεις κάθε σετ (έλεγχος γ2, W2-19): μια παλιότερη
  /// εντολή που φτάνει αργότερα δεν σβήνει τη νεότερη. Ρολόι παλιότερης έκδοσης δεν στέλνει «q»: όπως πριν.
  final _repsQ = <String, int>{};

  /// «Κοιτάζω» προς το ρολόι ανά [watchingEvery] όσο η εφαρμογή είναι μπροστά (έλεγχος γ2, W3-15): μόνο τότε το ρολόι
  /// στέλνει «ζωντανά» το περπάτημα (πριν: ανά 10″ για όλο το περπάτημα, ακόμα και με την εφαρμογή κλειστή).
  Timer? _watchTimer;
  static const watchingEvery = Duration(seconds: 45);
  static const watchingTtl = Duration(seconds: 60);

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
    _watching(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
      _watching(true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) {
      _watching(false);
    }
  }

  void _watching(bool on) {
    _watchTimer?.cancel();
    _watchTimer = null;
    // Ανά 45″ μόνο όσο τρέχει περπάτημα στο ρολόι (NIT 8)· στο άνοιγμα μία φορά, για να ξεκινήσουν τα «ζωντανά».
    if (on) _watchTimer = Timer.periodic(watchingEvery, (_) => liveFresh() ? sendWatching(watchingTtl) : null);
    sendWatching(on ? watchingTtl : Duration.zero);
  }

  DateTime? _watchingSent;

  /// Περπάτημα στο ρολόι που έστειλε «ζωντανά» το τελευταίο λεπτό.
  bool liveFresh() {
    final at = (live.value?['at'] as num?)?.toInt();
    return at != null && DateTime.now().millisecondsSinceEpoch - at < 60000;
  }

  /// «Κοιτάζω» ([ttl] > 0) ή «έκλεισα» (0) προς το ρολόι. Χωρίς κανένα γνωστό ρολόι: καμία κλήση.
  @visibleForTesting
  Future<void> sendWatching(Duration ttl) async {
    if (!(ready.value || _known)) return;
    _watchingSent = ttl > Duration.zero ? DateTime.now() : null;
    try {
      await _m.invokeMethod<bool>('watching', {'json': jsonEncode({'v': 1, 'ttl': ttl.inMilliseconds})});
    } catch (_) {}
  }

  @visibleForTesting
  set knownForTest(bool v) => _known = v;

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
    // Η εφαρμογή είναι μπροστά (ο χρονομετρητής τρέχει): «κοιτάζω» μόλις μάθουμε ότι υπάρχει ρολόι (W3-15).
    if (_watchTimer != null) await sendWatching(watchingTtl);
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
      watchSlow.value = j['slow'] == 1;
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
        final bpm = wearInt(j['bpm']) ?? 0;
        final at = wearTime(j['t']) ?? DateTime.now();
        if (bpm > 0) {
          hr.value = (bpm, at);
          t?.addHr(bpm, at, sid: j['sid'] is String ? j['sid'] as String : null);
        }
        ready.value = true;
      case '/ygeia/live':
        live.value = {...j, 'at': DateTime.now().millisecondsSinceEpoch};
        // Ξεκίνησε περπάτημα και η εφαρμογή είναι μπροστά: «κοιτάζω» αμέσως, όχι στα επόμενα 45″.
        final sent = _watchingSent;
        if (_watchTimer != null && (sent == null || DateTime.now().difference(sent) > const Duration(seconds: 40))) {
          sendWatching(watchingTtl);
        }
        final bpm = wearInt(j['bpm']) ?? 0;
        if (bpm > 0) hr.value = (bpm, DateTime.now());
        ready.value = true;
      case '/ygeia/cmd':
        // Εντολή νεότερης μορφής: δεν εκτελείται (V-A-08). Η έκδοση στο «pv»· το «v» εδώ είναι η τιμή (ρεζέρβα κ.λπ.).
        final pv = j['pv'];
        if (pv is num && pv > TrainingStore.watchMajor) return;
        final c = WatchCmd(j['op'] is String ? j['op'] as String : '', j);
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
        final at = wearInt(c.j['at']);
        if (at != null) {
          t.endFromWatch(s.id, at);
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
        // Σετ στο ρολόι σε άσκηση που παραλείφθηκε εδώ (ρολόι παλιότερης έκδοσης, W2-06): έγινε, άρα δεν είναι πια
        // «παράλειψη» — αλλιώς το σετ θα χανόταν στη σύνοψη και στην πρόοδο.
        if (e.skipped) t.skip(e, false);
        // Τελικός έλεγχος, Συμβούλιο 4 (W-4): το ✓ του ρολογιού κουβαλά και τις επαναλήψεις, όταν τις άλλαξες εκεί («r»).
        // Πριν έρχονταν μόνο με ξεχωριστή εντολή «reps»· αν εκείνη χανόταν (Bluetooth, κλειστή εφαρμογή) και το ✓ έφτανε
        // αργότερα, το σετ γραφόταν με τις προγραμματισμένες επαναλήψεις. Μόνο για την ίδια άσκηση («ex», όπως στο «reps»).
        // Ρολόι παλιότερης έκδοσης δεν στέλνει «r»: όπως πριν.
        final r = watchTickReps(c.j, e.ex);
        if (r != null) e.log[c.s].reps = r;
        t.tick(e, c.s, at: wearInt(c.j['at']));
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
        final v = wearInt(c.v);
        if (v != null && e.complete && e.rirAnswer == null) t.answer(e, v.clamp(0, 4));
      case 'reps':
        final v = wearInt(c.v);
        final q = wearInt(c.j['q']);
        if (q != null) {
          final key = '${c.sid}:${c.i}:${c.s}';
          final last = _repsQ[key] ?? 0;
          // Παλιότερη εντολή: αγνοείται. Πολύ πιο πίσω (> 10′: η ώρα του ρολογιού άλλαξε μετά από επανεκκίνηση): δεκτή (NIT 1).
          if (q <= last && last - q < 600000) return;
          _repsQ[key] = q;
        }
        if (v == null || c.s < 0 || c.s >= e.log.length) return;
        // Μόνο στο ίδιο σετ που εννοεί το ρολόι (έλεγχος του γ2, S4): αν η άσκηση άλλαξε στο μεταξύ (εναλλακτική), ή το
        // σετ έχει άλλη ώρα, αγνοείται. Ρολόι παλιότερης έκδοσης δεν στέλνει «ex»/«at»: όπως πριν.
        final ex = c.j['ex'];
        if (ex is String && ex != e.ex) return;
        final at = wearInt(c.j['at']);
        final setAt = e.log[c.s].at;
        if (at != null && (setAt == null || (setAt - at).abs() > 2000)) return;
        t.setReps(e, c.s, v);
    }
  }

  @visibleForTesting
  void attachForTest(TrainingStore t) {
    _t = t;
  }

  void dispose() {
    _watchTimer?.cancel();
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
