import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../exercise/ex_data.dart';
import 'equipment.dart';
import 'hr_file.dart';
import 'progression.dart';
import 'program.dart';
import 'session.dart';
import 'zone.dart';

/// Διόρθωση επαναλήψεων του ρολογιού που έρχεται μέσα στο αποτέλεσμά του (τελικός έλεγχος, Συμβούλιο 4, W-4): το σετ
/// είναι ✓ και στις δύο πλευρές, το ρολόι λέει ποιες τιμές είχε το κινητό πριν ([before], το «rb») και το κινητό δείχνει
/// ακόμα μία από αυτές ([phoneReps]) — δηλαδή η εντολή «reps» δεν έφτασε ποτέ και στο κινητό δεν άλλαξε τίποτα στο
/// μεταξύ. Μόνο για το ίδιο ✓ (ώρες ως 2″ μακριά, όπως στο «reps»). Αλλιώς null: μένει ό,τι έχει το κινητό.
int? watchResultReps({required int phoneReps, required int? phoneAt, required int watchReps, required int? watchAt, required Object? before}) {
  if (before is! List || !before.contains(phoneReps)) return null;
  if (phoneAt == null || watchAt == null || (phoneAt - watchAt).abs() > 2000) return null;
  final r = watchReps.clamp(0, 99);
  return r == phoneReps ? null : r;
}

/// Ανάγνωση/εγγραφή του training.json (μέσω Kotlin, ατομική εγγραφή· μπαίνει στο κρυπτογραφημένο αντίγραφο) και των
/// αρχείων παλμών ανά προπόνηση (hr/<id>.json, έλεγχος 9/11, V-A-02).
abstract class TrainingIO {
  Future<({String state, String? json})> read();
  Future<bool> write(String json);

  /// Οι παλμοί μιας προπόνησης: «ok» με κείμενο, «missing», ή «error» (τότε δεν γράφεται τίποτα πάνω του).
  Future<({String state, String? json})> readHr(String id);

  /// false αν δεν γράφτηκε: τότε οι παλμοί μένουν μέσα στο training.json (όπως ως #90), τίποτα δεν χάνεται.
  Future<bool> writeHr(String id, String json);
  Future<bool> deleteHr(String id);
  Future<List<String>> listHr();

  /// Αρχείο παλμών που δεν διαβάζεται: μετονομάζεται (π.χ. «id.json.bad»), ποτέ δεν σβήνεται και ποτέ δεν γράφεται από
  /// πάνω. Επιστρέφει το νέο όνομα, ή null αν δεν έγινε (τότε δεν αλλάζει τίποτα).
  Future<String?> markHrBad(String id);
}

/// Προαιρετικό (round1, S9-9): το training.json που δεν διαβάζεται μπαίνει στην άκρη (μετονομασία, ποτέ σβήσιμο), για
/// να ξαναρχίσει η αποθήκευση. Χωριστό από το [TrainingIO], ώστε ό,τι το υλοποιεί ήδη να μη χρειάζεται αλλαγή.
abstract class TrainingBadIO {
  /// Το νέο όνομα του αρχείου (π.χ. «training.json.bad»), ή null αν δεν έγινε (τότε δεν αλλάζει τίποτα).
  Future<String?> markBad();
}

class ChannelTrainingIO implements TrainingIO, TrainingBadIO {
  const ChannelTrainingIO();
  static const channel = MethodChannel('ygeia/training');

  @override
  Future<String?> markBad() async {
    try {
      return await channel.invokeMethod<String>('bad');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<({String state, String? json})> read() async {
    try {
      final raw = await channel.invokeMethod<Object?>('read');
      // Από το #91 το κείμενο έρχεται ως έχει (χάρτης)· παλιότερα μέσα σε άλλο JSON.
      if (raw is Map) return (state: raw['state'] as String? ?? 'error', json: raw['json'] as String?);
      if (raw is! String) return (state: 'error', json: null);
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

  @override
  Future<({String state, String? json})> readHr(String id) async {
    try {
      final raw = await channel.invokeMethod<Object?>('hrRead', {'id': id});
      if (raw is Map) return (state: raw['state'] as String? ?? 'error', json: raw['json'] as String?);
      return (state: 'error', json: null);
    } on MissingPluginException {
      return (state: 'missing', json: null);
    } catch (_) {
      return (state: 'error', json: null);
    }
  }

  @override
  Future<bool> writeHr(String id, String json) async {
    try {
      return await channel.invokeMethod<bool>('hrWrite', {'id': id, 'json': json}) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> deleteHr(String id) async {
    try {
      return await channel.invokeMethod<bool>('hrDelete', {'id': id}) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> listHr() async {
    try {
      return (await channel.invokeListMethod<String>('hrList')) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<String?> markHrBad(String id) async {
    try {
      return await channel.invokeMethod<String>('hrBad', {'id': id});
    } catch (_) {
      return null;
    }
  }
}

/// Για δοκιμές: στη μνήμη.
class MemoryTrainingIO implements TrainingIO, TrainingBadIO {
  MemoryTrainingIO([this.json]);
  String? json;
  int writes = 0;

  /// Το training.json που μπήκε στην άκρη (S9-9), ή null.
  String? badJson;

  @override
  Future<String?> markBad() async {
    final text = json;
    if (text == null) return null;
    badJson = text;
    json = null;
    return 'training.json.bad';
  }

  /// Τα αρχεία παλμών (id → κείμενο).
  final Map<String, String> hrFiles = {};
  int hrWrites = 0;

  @override
  Future<({String state, String? json})> read() async => (state: json == null ? 'missing' : 'ok', json: json);
  @override
  Future<bool> write(String j) async {
    json = j;
    writes++;
    return true;
  }

  @override
  Future<({String state, String? json})> readHr(String id) async =>
      hrFiles.containsKey(id) ? (state: 'ok', json: hrFiles[id]) : (state: 'missing', json: null);
  @override
  Future<bool> writeHr(String id, String j) async {
    hrFiles[id] = j;
    hrWrites++;
    return true;
  }

  @override
  Future<bool> deleteHr(String id) async {
    hrFiles.remove(id);
    return true;
  }

  @override
  Future<List<String>> listHr() async => hrFiles.keys.toList()..sort();

  /// Αρχεία παλμών που μπήκαν στην άκρη (όνομα → κείμενο).
  final Map<String, String> badHrFiles = {};

  @override
  Future<String?> markHrBad(String id) async {
    final text = hrFiles.remove(id);
    if (text == null) return null;
    final name = '$id.json.bad';
    badHrFiles[name] = text;
    return name;
  }
}

/// Όνομα που μπορεί να γίνει αρχείο παλμών (ίδιος κανόνας με το HrFiles.kt).
bool hrFileId(String id) => id.isNotEmpty && id.length <= 120 && RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(id) && id != '.' && id != '..';

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

  /// Το αρχείο είναι από νεότερη έκδοση της εφαρμογής ([fileVersion]): δεν γράφεται τίποτα (V-A-08).
  bool newerFile = false;

  /// Το αρχείο διαβάστηκε αλλά το περιεχόμενό του δεν είναι προπονήσεις (χαλασμένο): όσες φορές κι αν ξανανοίξει η
  /// εφαρμογή θα βγαίνει το ίδιο. Μόνο τότε προσφέρεται το «Κράτα το στην άκρη» ([setAsideUnreadable], S9-9).
  bool damaged = false;
  String? saveError;

  /// Το μήνυμα όταν μια αλλαγή δεν γράφεται επειδή το αρχείο δεν διαβάστηκε (S6-5).
  static const notSavedUnreadable = 'Οι αλλαγές δεν αποθηκεύονται: το αρχείο προπονήσεων δεν διαβάστηκε.';

  /// Έγκυρος παλμός άσκησης: 26…249 (ίδιος κανόνας με το ρολόι, Protocol.kt «bpm <= 25 || bpm >= 250», S12-16).
  static const hrValidMin = 26, hrValidMax = 249;

  /// Δευτερόλεπτα ανά επανάληψη όταν η βιβλιοθήκη δεν έχει ρυθμό για την άσκηση (S6-8).
  static const defaultRepSeconds = 4.5;

  /// Πόσο κρατά μία επανάληψη της άσκησης [ex] με τον ρυθμό της βιβλιοθήκης (S6-8), για τους παλμούς ανά σετ.
  static double repSeconds(String ex) {
    final c = ExLibrary.loaded?.byId(ex)?.cycle;
    return c != null && c > 0 ? c : defaultRepSeconds;
  }

  /// Η βιβλιοθήκη ασκήσεων φόρτωσε (S6-2): όσες οθόνες δείχνουν προπόνηση ξαναζωγραφίζονται («Πώς γίνεται»).
  void libraryReady() => notifyListeners();

  /// Η μορφή του training.json: 2 = οι παλμοί μπορεί να είναι στα αρχεία hr/ (#91). Νεότερη = μόνο ανάγνωση.
  static const fileVersion = 2;

  /// Η μορφή των αποτελεσμάτων/εντολών του ρολογιού που ξέρει αυτή η έκδοση (πεδίο «v», Protocol.kt: Proto.MAJOR).
  static const watchMajor = 1;

  /// Κλειδιά του αρχείου που δεν ξέρει αυτή η έκδοση: ξαναγράφονται αυτούσια (έλεγχος 9/11, V-A-07).
  final Map<String, dynamic> _extra = {};

  /// Προπονήσεις/προγράμματα που δεν διαβάστηκαν (V-A-10): κρατιούνται στο αρχείο όπως ήταν («bad»), δεν δείχνονται.
  final List<Map<String, dynamic>> quarantine = [];

  /// Τι δεν πήγε καλά στην τελευταία επαναφορά από αντίγραφο (null = τίποτα), για να το πει η οθόνη (V-A-10).
  String? mergeProblem;

  /// Η τελευταία προπόνηση του κινητού που έκλεισε με «Τέλος» στο ρολόι (V-A-09): η οθόνη της προπόνησης πάει στη σύνοψη.
  Session? endedByWatch;

  /// Η τελευταία προπόνηση του κινητού σβήστηκε με «Τέλος» στο ρολόι, γιατί δεν είχε κανένα σετ (S7): το λέει η οθόνη της.
  bool discardedByWatch = false;

  /// Μετά από πόσο χωρίς κίνηση μια ανοιχτή προπόνηση είναι «ξεχασμένη» (V-A-09).
  static const staleAfter = Duration(hours: 3);

  /// Όριο παλμών από τον γιατρό (bpm), αν έδωσε: το ρολόι δονεί όταν το ξεπεράσεις. Κενό = τίποτα.
  int? hrLimit;

  /// Ζώνη περπατήματος (12/11) όπως τη στέλνουμε στο ρολόι. Την υπολογίζει η εφαρμογή (HealthStore.zoneOn) και την
  /// περνά εδώ ([setZone]), ώστε να υπάρχει και πριν διαβαστεί το ιστορικό και να φτάνει στο ρολόι με το πρόγραμμα.
  WalkZone? zone;

  /// Φωνή στην άσκηση από το ρολόι (14/11, Ρυθμίσεις): «Πρώτο χιλιόμετρο», «Εκτός εύρους», «Επόμενο σετ». Ανοιχτή από
  /// προεπιλογή (αίτημα χρήστη). Στέλνεται στο ρολόι με το πρόγραμμα.
  bool voice = true;

  /// Το μήκος του βήματος (m) για την απόσταση χωρίς GPS (14/11, [strideFor]): από τα περπατήματα με GPS, αλλιώς από το
  /// ύψος. Το υπολογίζει η εφαρμογή ([setStride]) και πάει στο ρολόι με το πρόγραμμα.
  double? stride;

  /// Όλες οι εκδόσεις όλων των προγραμμάτων (η πιο πρόσφατη στο τέλος).
  final List<Program> programs = [];
  String? activeId;
  final List<Session> sessions = [];

  /// Προπονήσεις που σβήστηκαν (ids): να μην ξαναγυρίσουν από το ρολόι ή από παλιό αντίγραφο (9/11).
  final Set<String> deleted = {};
  Session? current;

  /// Προπονήσεις του κινητού που έκλεισαν με «Σβήσιμο» χωρίς κανένα σετ εδώ ([discard]), για [dropKeep] (round1, U6-01,
  /// αίτημα του f6b): αν μετά φτάσει το αποτέλεσμα του ρολογιού με σετ ή παλμούς (τα ✓ έμειναν στο ρολόι, π.χ. χωρίς
  /// Bluetooth), η προπόνηση ξαναμπαίνει αντί να χαθεί. Κλειδί «drop» στο training.json: νέο, προαιρετικό (το παλιό
  /// κινητό το κρατά ως άγνωστο κλειδί, V-A-07). Ως [dropMax] προπονήσεις.
  final List<Map<String, dynamic>> _dropped = [];
  static const dropKeep = Duration(days: 7);
  static const dropMax = 5;

  Future<void>? _loading;
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final r = await _io.read();
    // Οι σημαίες αλλάζουν ΜΑΖΙ, αφού διαβαστεί το αρχείο (S9-9): σε μια νέα προσπάθεια ([retryLoad]) το `readError` μένει
    // ως τότε, ώστε καμία εγγραφή να μη γράψει άδειες προπονήσεις πάνω στο αρχείο όσο αυτό διαβάζεται.
    var error = false, newer = false, broken = false;
    if (r.state == 'ok' && r.json != null) {
      try {
        final j = jsonDecode(r.json!);
        if (j is! Map) throw const FormatException();
        final m = Map<String, dynamic>.from(j);
        final v = m['v'];
        if (v is num && v > fileVersion) {
          newer = true;
          error = true;
        } else {
          _fromJson(m);
        }
      } catch (_) {
        error = true;
        broken = true;
        // Ό,τι πρόλαβε να διαβαστεί από ένα χαλασμένο αρχείο δεν μένει στη μνήμη.
        _fromJson(const {});
      }
    } else if (r.state == 'error') {
      error = true;
    } else if (readError) {
      // Νέα προσπάθεια και το αρχείο δεν υπάρχει πια (μπήκε στην άκρη): άδεια αποθήκη.
      _fromJson(const {});
    }
    readError = error;
    newerFile = newer;
    damaged = broken;
    if (!error && saveError == notSavedUnreadable) saveError = null;
    ready = true;
    notifyListeners();
    if (!readError) {
      // Μεταφορά (μία φορά): οι παλμοί που ήταν μέσα στο training.json πάνε στα δικά τους αρχεία και φεύγουν από τη
      // μνήμη (φορτώνονται μόνο όταν τους χρειαστεί μια σύνοψη).
      _release.addAll([for (final s in sessions) if (s.hrNeedsWrite) s.id]);
      if (_release.isNotEmpty) save();
      _queue = _queue.then((_) => _purgeDeletedHr());
      if (!_steadyDone) _queue = _queue.then((_) => _migrateSteady());
    }
  }

  /// «Δοκίμασε ξανά» (round1, S6-5 / S9-9): ξαναδιαβάζει το αρχείο. Μόνο όταν η ανάγνωση είχε αποτύχει: τότε τίποτα δεν
  /// έχει γραφτεί και τίποτα δεν περιμένει να γραφτεί.
  Future<void> retryLoad() {
    if (!readError) return Future.value();
    return _loading = _load();
  }

  /// «Κράτα το στην άκρη και συνέχισε» (S9-9): το χαλασμένο training.json μετονομάζεται (δεν σβήνεται, δεν γράφεται ποτέ
  /// από πάνω) και η αποθήκη ξεκινά άδεια· μετά δουλεύουν ξανά η αποθήκευση, η επαναφορά από αντίγραφο και ό,τι
  /// περιμένει στο ρολόι. true αν έγινε.
  Future<bool> setAsideUnreadable() async {
    final Object io = _io;
    if (!damaged || io is! TrainingBadIO) return false;
    final name = await io.markBad();
    if (name == null) return false;
    await retryLoad();
    return !readError;
  }

  /// Οι «παλμοί σταθερού βαδίσματος» ([Session.hrSteady]) έχουν σωθεί και για τα παλιά περπατήματα ([_migrateSteady]).
  bool _steadyDone = false;

  /// Μεταφορά, μία φορά (έλεγχος του fix-accuracy, S6): τα περπατήματα από πριν από τη V-B-11 έχουν τους παλμούς στο
  /// αρχείο τους αλλά όχι «hrs», οπότε η Πρόοδος δεν θα τα έβλεπε για μήνες. Ένα-ένα, χωρίς να μένουν στη μνήμη.
  /// Αν κάποιο αρχείο δεν διαβαστεί τώρα, ξαναδοκιμάζει στο επόμενο άνοιγμα.
  Future<void> _migrateSteady() async {
    var changed = false;
    var complete = true;
    for (final s in sessions.toList()) {
      if (s.hrSteady != null || s.hrLoaded || !s.hrInFile || !s.isCardio || !s.finished) continue;
      try {
        final r = await _io.readHr(s.id);
        if (r.state == 'missing') continue;
        final hr = r.state == 'ok' ? decodeHr(r.json) : null;
        if (hr == null) {
          complete = false;
          continue;
        }
        if (s.hrLoaded || s.hrSteady != null) continue;
        final v = Session.steadyFrom(hr, s.pauses);
        if (v != null) {
          s.hrSteady = v;
          changed = true;
        }
      } catch (_) {
        complete = false;
      }
    }
    // Η σημαία γράφεται με την επόμενη εγγραφή (καμία εγγραφή μόνο γι' αυτήν, όταν δεν άλλαξε τίποτα).
    if (complete) _steadyDone = true;
    if (changed) save();
  }

  static const _knownTop = {
    'v', 'hrLimit', 'zone', 'programs', 'active', 'sessions', 'del', 'current', 'bad', 'hrz', 'hrsDone', 'drop', 'voice', 'stride',
  };

  /// Ανάγνωση με ανοχή (έλεγχος 9/11, V-A-10): μία χαλασμένη προπόνηση ή πρόγραμμα πάει σε καραντίνα, όχι όλο το
  /// αρχείο σε «δεν διαβάζεται». Τα άγνωστα κλειδιά κρατιούνται (V-A-07).
  void _fromJson(Map<String, dynamic> j) {
    _extra
      ..clear()
      ..addAll({
        for (final e in j.entries)
          if (!_knownTop.contains(e.key)) e.key: e.value,
      });
    final hl = j['hrLimit'];
    hrLimit = hl is num ? hl.toInt() : null;
    if (hl != null && hl is! num) _extra['hrLimit'] = hl;
    zone = WalkZone.fromJson(j['zone']);
    if (j['zone'] != null && zone == null) _extra['zone'] = j['zone'];
    voice = j['voice'] != false;
    final st = j['stride'];
    stride = st is num && st >= 0.4 && st <= 1.2 ? st.toDouble() : null;
    quarantine
      ..clear()
      ..addAll([
        for (final x in (j['bad'] is List ? j['bad'] as List : const []))
          if (x is Map) Map<String, dynamic>.from(x),
      ]);
    programs.clear();
    for (final p in (j['programs'] is List ? j['programs'] as List : const [])) {
      try {
        programs.add(Program.fromJson(Map<String, dynamic>.from(p as Map)));
      } catch (_) {
        quarantine.add({'in': 'programs', 'j': p});
      }
    }
    activeId = j['active'] is String ? j['active'] as String : null;
    _steadyDone = j['hrsDone'] == 1;
    sessions.clear();
    for (final x in (j['sessions'] is List ? j['sessions'] as List : const [])) {
      try {
        sessions.add(Session.fromJson(Map<String, dynamic>.from(x as Map)));
      } catch (_) {
        quarantine.add({'in': 'sessions', 'j': x});
      }
    }
    _sortByStart();
    current = null;
    if (j['current'] is Map) {
      try {
        current = Session.fromJson(Map<String, dynamic>.from(j['current'] as Map));
      } catch (_) {
        quarantine.add({'in': 'current', 'j': j['current']});
      }
    }
    deleted
      ..clear()
      ..addAll([for (final x in (j['del'] is List ? j['del'] as List : const [])) if (x is String) x]);
    _dropped
      ..clear()
      ..addAll([for (final x in (j['drop'] is List ? j['drop'] as List : const [])) if (x is Map) Map<String, dynamic>.from(x)]);
    _segments.clear();
    _release.clear();
  }

  /// Οι προπονήσεις με τη σειρά που ξεκίνησαν (S6-15): έτσι τις διαβάζουν το ιστορικό, η «τελευταία φορά» και οι
  /// στόχοι. Αρχείο που γράφτηκε πριν από τη διόρθωση μπορεί να έχει μία εκτός σειράς· όσες ξεκίνησαν την ίδια στιγμή
  /// κρατούν τη σειρά που είχαν.
  void _sortByStart() {
    var sorted = true;
    for (var i = 1; i < sessions.length; i++) {
      if (sessions[i].start.isBefore(sessions[i - 1].start)) sorted = false;
    }
    if (sorted) return;
    final at = {for (var i = 0; i < sessions.length; i++) sessions[i]: i};
    sessions.sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : at[a]!.compareTo(at[b]!);
    });
  }

  /// Μια τελειωμένη προπόνηση στη θέση της, με τη σειρά της ώρας που ξεκίνησε (S6-15).
  void _insertByStart(Session s) {
    var at = sessions.length;
    while (at > 0 && sessions[at - 1].start.isAfter(s.start)) {
      at--;
    }
    sessions.insert(at, s);
  }

  Map<String, dynamic> toJson() => {
        ..._extra,
        'v': fileVersion,
        if (hrLimit != null) 'hrLimit': hrLimit,
        if (zone != null) 'zone': zone!.toJson(),
        if (!voice) 'voice': false,
        if (stride != null) 'stride': stride,
        'programs': [for (final p in programs) p.toJson()],
        if (activeId != null) 'active': activeId,
        // Οι παλμοί κάθε τελειωμένης προπόνησης στο δικό της αρχείο, μόλις γραφτεί αυτό· ως τότε μέσα (καμία απώλεια).
        'sessions': [for (final s in sessions) s.toJson(hrInline: !s.hrInFile)],
        if (deleted.isNotEmpty) 'del': deleted.toList(),
        if (current != null) 'current': current!.toJson(),
        if (quarantine.isNotEmpty) 'bad': quarantine,
        if (_steadyDone) 'hrsDone': 1,
        if (_dropped.isNotEmpty) 'drop': _dropped,
      };

  Future<void> _queue = Future.value();

  /// Ό,τι είναι στη μνήμη έχει γραφτεί στο αρχείο: καμία εγγραφή σε αναμονή και η τελευταία πέτυχε (V-A-01).
  bool _written = true;

  /// Πόσων προπονήσεων οι παλμοί δεν μπήκαν στο τελευταίο αντίγραφο ([backupJson]): το λέει η εξαγωγή (S5).
  int backupHrMissing = 0;

  /// Μετρητής αλλαγών: μια εγγραφή «πιάνει» μόνο αν δεν άλλαξε τίποτα από τότε που κωδικοποιήθηκε.
  int _gen = 0;

  /// Μια εγγραφή περιμένει στη σειρά και δεν έχει ξεκινήσει: νέες αλλαγές μπαίνουν σε αυτήν (καμία διπλή κωδικοποίηση).
  bool _queued = false;

  /// Παλμοί που μεταφέρθηκαν από το training.json: φεύγουν από τη μνήμη μόλις γραφτούν (φορτώνονται όταν χρειαστούν).
  final Set<String> _release = {};

  /// Κομμάτια παλμών από το ρολόι για προπόνηση της οποίας οι παλμοί δεν είναι στη μνήμη: ενώνονται στην εγγραφή.
  final Map<String, List<(List<List<int>>, int?, int?)>> _segments = {};

  /// Κάθε αλλαγή γράφεται αμέσως (με σειρά): αν κλείσει η εφαρμογή στη μέση της προπόνησης, δεν χάνεται σετ. Πολλές
  /// αλλαγές μαζί (π.χ. 7 αποτελέσματα του ρολογιού) γίνονται μία εγγραφή.
  Future<void> save() {
    // S6-5: με αρχείο που δεν διαβάστηκε τίποτα δεν γράφεται (για να μη χαθεί)· να φαίνεται, όχι σιωπηλά.
    if (readError) saveError = notSavedUnreadable;
    notifyListeners();
    if (readError) return Future.value();
    _gen++;
    _written = false;
    if (_queued) return _queue;
    _queued = true;
    _queue = _queue.then((_) => _writeJob());
    return _queue;
  }

  Session? _finishedById(String id) {
    for (final s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> _writeJob() async {
    _queued = false;
    var hrOk = true;
    // Παλμοί που άλλαξαν όσο γραφόταν το αρχείο τους (π.χ. ένα δεύτερο κομμάτι από το ρολόι): ΟΧΙ «γραμμένο» (M1).
    var stale = false;
    // 1) Οι παλμοί στα αρχεία τους (πριν από το training.json που τα αναφέρει).
    for (final id in _segments.keys.toList()) {
      if (_finishedById(id) == null) _segments.remove(id);
    }
    for (final s in sessions.toList()) {
      if (!hrFileId(s.id)) continue;
      final segs = _segments[s.id];
      if (!s.hrNeedsWrite && segs == null) continue;
      try {
        if (!s.hrLoaded) {
          final r = await _io.readHr(s.id);
          if (r.state == 'error') {
            hrOk = false;
            continue;
          }
          if (!s.hrLoaded) {
            final hr = decodeHr(r.json);
            if (hr == null) {
              // Το αρχείο δεν διαβάζεται: στην άκρη, όχι από πάνω (S1). Αν δεν γίνει, τίποτα δεν αλλάζει (κανένα ack).
              if (!await _setAsideHr(s)) {
                hrOk = false;
                continue;
              }
            } else if (!s.hrLoaded) {
              s.hr
                ..clear()
                ..addAll(hr);
              s.hrLoaded = true;
              s.hrInFile = true;
              s.hrRev++;
            }
          }
        }
        for (final seg in _segments.remove(s.id) ?? const <(List<List<int>>, int?, int?)>[]) {
          mergeHrSegment(s, seg.$1, watchAvg: seg.$2, watchMax: seg.$3);
        }
        if (!s.hrNeedsWrite) continue;
        final rev = s.hrRev;
        final text = encodeHr(s.hr);
        if (await _io.writeHr(s.id, text)) {
          if (s.hrRev != rev) {
            // Άλλαξαν όσο γραφόταν: το αρχείο έχει τα παλιά· η επόμενη εγγραφή τα γράφει όλα.
            stale = true;
            continue;
          }
          s.hrInFile = true;
          s.hrCount = s.hr.length;
          if (_release.remove(s.id)) {
            // Οι «παλμοί σταθερού βαδίσματος» κρατιούνται πριν φύγουν οι παλμοί από τη μνήμη (έλεγχος 9/11, V-B-11).
            s.hrSteady = s.steadyHr;
            s.hr.clear();
            s.hrLoaded = false;
          }
        }
      } catch (_) {
        hrOk = false;
      }
    }
    // 2) Το training.json.
    final gen = _gen;
    bool ok;
    try {
      ok = await _io.write(jsonEncode(toJson()));
    } catch (_) {
      // Ποτέ σπασμένη σειρά: μια εξαίρεση εδώ θα σταματούσε όλες τις επόμενες εγγραφές.
      ok = false;
    }
    // Κομμάτια παλμών που δεν ενώθηκαν ακόμα (το αρχείο δεν διαβάστηκε) = όχι γραμμένα: κανένα ack.
    _written = ok && hrOk && !stale && _segments.isEmpty && gen == _gen;
    final err = ok ? null : 'Δεν αποθηκεύτηκε η τελευταία αλλαγή στο κινητό.';
    if (err != saveError) {
      saveError = err;
      notifyListeners();
    }
  }

  /// Περιμένει τις εγγραφές· αν η τελευταία απέτυχε, ξαναγράφει μία φορά. true μόνο αν ό,τι είναι στη μνήμη είναι
  /// γραμμένο στο αρχείο. Έλεγχος 9/11 (V-A-01): μόνο τότε σβήνεται ένα αποτέλεσμα από το ρολόι.
  Future<bool> flush() async {
    if (readError || !ready) return false;
    await _queue;
    if (!_written) await save();
    return !readError && _written;
  }

  /// Οι παλμοί μιας προπόνησης στη μνήμη (από το αρχείο τους), για τη σύνοψη. Μία ανάγνωση, μόνο όταν χρειάζεται.
  Future<void> ensureHr(Session s) async {
    if (s.hrLoaded) return;
    _release.remove(s.id);
    await _queue;
    if (s.hrLoaded) return;
    final r = await _io.readHr(s.id);
    if (s.hrLoaded || r.state == 'error') return;
    final hr = decodeHr(r.json);
    if (hr == null) {
      // Δεν διαβάζεται: στην άκρη (όχι σβήσιμο), και η προπόνηση το θυμάται (S1).
      if (await _setAsideHr(s)) save();
      return;
    }
    s.hr
      ..clear()
      ..addAll(hr);
    s.hrLoaded = true;
    s.hrInFile = true;
    s.hrRev++;
    notifyListeners();
  }

  /// Αρχείο παλμών που δεν διαβάζεται (S1): μετονομάζεται και κρατιέται, η προπόνηση γράφει το όνομά του («hrbad»), και
  /// από εκεί και πέρα νέοι παλμοί πάνε σε καινούριο αρχείο. Ποτέ δεν γράφεται τίποτα πάνω του. false αν δεν έγινε.
  Future<bool> _setAsideHr(Session s) async {
    final name = await _io.markHrBad(s.id);
    if (name == null) return false;
    s.hrBad = name;
    s.hr.clear();
    s.hrLoaded = true;
    s.hrInFile = false;
    s.hrCount = 0;
    s.hrRev++;
    notifyListeners();
    return true;
  }

  /// Αρχεία παλμών προπονήσεων που σβήστηκαν (V-A-02): σβήνονται στο επόμενο άνοιγμα (ως τότε η «Αναίρεση» τα βρίσκει).
  Future<void> _purgeDeletedHr() async {
    try {
      final ids = await _io.listHr();
      for (final id in ids) {
        if (deleted.contains(id) && !sessions.toList().any((x) => x.id == id)) await _io.deleteHr(id);
      }
    } catch (_) {}
  }

  /// Το αντίγραφο ασφαλείας (V-A-02): όπως το training.json, και οι παλμοί όσων είναι στα αρχεία τους («hrz»).
  Future<Map<String, dynamic>> backupJson() async {
    await _queue;
    final j = toJson();
    final hrz = <String, String>{};
    var missing = 0;
    // Αντίγραφο της λίστας: όσο διαβάζονται τα αρχεία μπορεί να έρθει προπόνηση από το ρολόι (S5).
    for (final s in sessions.toList()) {
      if (!s.hrInFile) continue; // ήδη μέσα («hr»)
      if (s.hrLoaded) {
        if (s.hr.isNotEmpty) hrz[s.id] = encodeHr(s.hr);
      } else if (s.hrCount > 0) {
        final r = await _io.readHr(s.id);
        if (r.state == 'ok' && r.json != null && decodeHr(r.json) != null) {
          hrz[s.id] = r.json!;
        } else {
          missing++;
        }
      }
    }
    backupHrMissing = missing;
    if (hrz.isNotEmpty) j['hrz'] = hrz;
    return j;
  }

  // ---------------------------------------------------------------- όριο παλμών
  /// Όριο παλμών από τον γιατρό (null = κανένα).
  void setHrLimit(int? hr) {
    hrLimit = hr;
    save();
  }

  /// Ζώνη περπατήματος: γράφεται (και στέλνεται στο ρολόι) μόνο αν άλλαξε.
  void setZone(WalkZone? z) {
    if (z == zone) return;
    zone = z;
    save();
  }

  /// Φωνή στην άσκηση (14/11): γράφεται και πάει στο ρολόι.
  void setVoice(bool on) {
    if (on == voice) return;
    voice = on;
    save();
  }

  /// Μήκος βήματος (14/11): γράφεται (και πάει στο ρολόι) μόνο αν άλλαξε πάνω από 1 cm (όχι σε κάθε άνοιγμα).
  void setStride(double? m) {
    final v = m == null ? null : (m * 100).round() / 100;
    if (v == stride || (v != null && stride != null && (v - stride!).abs() < 0.01)) return;
    stride = v;
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
      if (!s.finished || s.stopped) continue;
      for (final e in s.items) {
        if (e.ex == ex) out.add((s.start, e));
      }
    }
    return out;
  }

  Target targetFor(PlanItem item) => nextTarget(item, historyOf(item.ex), now, caution: isCaution(item.ex));

  /// Οι ασκήσεις «με προσοχή» της βιβλιοθήκης, για όταν αυτή δεν έχει φορτώσει ακόμα (round1, S6-2 / S7-01). Πριν, χωρίς
  /// βιβλιοθήκη ΟΛΕΣ μετρούσαν «με προσοχή»: η ίδια προπόνηση έβγαζε άλλους στόχους από τη Σήμερα και άλλους από την
  /// Άσκηση. Η δοκιμή test/r1_f6a_test.dart ελέγχει ότι ταιριάζει ένα προς ένα με το assets/exercises/exercises.json.
  static const cautionIds = <String>{'dips', 'overhead_ext', 'shoulder_press'};

  /// Άσκηση με προσοχή στη βιβλιοθήκη (ή, πριν φορτώσει, στο [cautionIds]).
  static bool isCaution(String ex) {
    final lib = ExLibrary.loaded;
    return lib == null ? cautionIds.contains(ex) : lib.byId(ex)?.caution != null;
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
      lo: loFor(item, t),
      hi: item.hi,
      rir: item.rir < 2 ? 2 : item.rir,
      rest: item.rest,
      log: [for (final r in t.reps) SetLog(load: t.load, reps: r)],
      reason: t.reason,
    );
  }

  /// Το κάτω όριο που γράφεται στην προπόνηση (round1, S6-1): του προγράμματος, ή ο στόχος της μέρας όταν αυτός είναι
  /// πιο κάτω (π.χ. ίδιο βάρος, 9 επαναλήψεις, σε μέρα με εύρος 10–15). Έτσι όποιος βγάλει τον στόχο του δεν κρίνεται
  /// την επόμενη φορά «κάτω από το εύρος».
  static int loFor(PlanItem item, Target t) {
    var lo = item.lo;
    for (final r in t.reps) {
      if (r < lo) lo = r;
    }
    return lo;
  }

  /// Η άσκηση που γίνεται σήμερα στη θέση του [item] (round1, S7-03): αν έχει πιο δύσκολη παραλλαγή ([PlanItem.next])
  /// και την τελευταία φορά έκανες εκείνη στη θέση της (⋮ › «Αλλαγή άσκησης»), συνεχίζεις με εκείνη· αν γύρισες πίσω,
  /// με την αρχική. Πριν, η παραλλαγή δεν έμπαινε ποτέ μόνη της και η πρόταση ξαναερχόταν κάθε εβδομάδα.
  PlanItem itemToday(PlanItem item) {
    final next = item.next;
    if (next == null) return item;
    for (final s in sessions.reversed) {
      if (!s.finished || s.stopped) continue;
      for (final e in s.items) {
        if (e.skipped || e.done.isEmpty) continue;
        if (e.ex == next && e.swappedFrom == item.ex) {
          return PlanItem(ex: next, sets: item.sets, lo: item.lo, hi: item.hi, rir: item.rir, rest: item.rest, note: item.note);
        }
        if (e.ex == item.ex) return item;
      }
    }
    return item;
  }

  /// Η άσκηση του προγράμματος όπως μπαίνει στην προπόνηση που ξεκινά ([itemToday]).
  ExLog _startLog(PlanItem item) {
    final it = itemToday(item);
    final e = _logFor(it);
    if (it.ex != item.ex) e.swappedFrom = item.ex;
    return e;
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

  // ---------------------------------------------------------------- διαγραφή
  /// Σβήνει μια τελειωμένη προπόνηση (ή περπάτημα) από παντού: ιστορικό, πρόοδο, σύνοψη, αντίγραφα. Επιστρέφει ό,τι
  /// σβήστηκε, για «Αναίρεση». Η προπόνηση σε εξέλιξη δεν σβήνεται από εδώ.
  Session? deleteSession(String id) {
    final i = sessions.indexWhere((x) => x.id == id);
    if (i < 0) return null;
    final s = sessions.removeAt(i);
    deleted.add(id);
    save();
    return s;
  }

  /// «Αναίρεση»: η προπόνηση γυρίζει στη θέση της (με τη σειρά της ώρας).
  void undoDelete(Session s) {
    deleted.remove(s.id);
    if (!sessions.any((x) => x.id == s.id)) {
      var at = sessions.length;
      while (at > 0 && sessions[at - 1].start.isAfter(s.start)) {
        at--;
      }
      sessions.insert(at, s);
    }
    save();
  }

  /// Οι παλμοί του ρολογιού έχουν χρόνο από τη στιγμή που ξεκίνησε η μέτρηση εκεί («hrT0», ms)· εδώ μετρούν από την
  /// αρχή της προπόνησης. Χωρίς «hrT0» (ρολόι ως #87): όπως ήρθαν.
  static List<List<int>> alignHr(List<List<int>> samples, Object? hrT0, DateTime start) {
    if (hrT0 is! num) return samples;
    final off = ((hrT0.toInt() - start.millisecondsSinceEpoch) / 1000).round();
    if (off == 0) return samples;
    return [
      for (final p in samples)
        if (p[0] + off >= 0) [p[0] + off, p[1]],
    ];
  }

  DateTime? _hrSaved;

  /// Παλμοί από το ρολόι για την προπόνηση που τρέχει (δείγμα ανά ~10″, αποθήκευση ανά λεπτό).
  void addHr(int bpm, DateTime at, {String? sid}) {
    final s = current;
    if (s == null || bpm < hrValidMin || bpm > hrValidMax) return;
    if (sid != null && sid.isNotEmpty && sid != s.id) return;
    // R7-A8-3: παλμοί ώρες μετά την τελευταία κίνηση (ρολόι που «μπήκε» σε ξεχασμένη προπόνηση) δεν είναι δικοί της.
    if (!belongs(s, at.millisecondsSinceEpoch)) return;
    final sec = at.difference(s.start).inSeconds;
    if (sec < 0) return;
    if (s.hr.isEmpty || sec - s.hr.last[0] >= 10) {
      s.hr.add([sec, bpm]);
      s.hrRev++;
    }
    if (s.hrMax == null || bpm > s.hrMax!) s.hrMax = bpm;
    if (_hrSaved == null || at.difference(_hrSaved!).inSeconds >= 60) {
      _hrSaved = at;
      save();
    }
  }

  /// Ένα κομμάτι παλμών του ρολογιού ([seg], ήδη στον χρόνο της προπόνησης) στην προπόνηση [s] (έλεγχος 9/11, V-A-11):
  /// ΕΝΩΝΕΤΑΙ με ό,τι υπάρχει (πριν: η μεγαλύτερη λίστα κέρδιζε και χανόταν το άλλο κομμάτι). Ό,τι υπήρχε μέσα στο
  /// διάστημα του κομματιού (π.χ. οι ζωντανοί παλμοί ανά 10″, ή το ίδιο κομμάτι ξανά) δίνει τη θέση του στις τιμές ανά
  /// 1″· ό,τι είναι έξω μένει. Μέσος και υψηλότερος ξαναϋπολογίζονται από όλες τις τιμές (ένα κομμάτι μόνο: ο μέσος
  /// του ρολογιού, που ξέρει τις παύσεις). Σε τελειωμένη προπόνηση, όχι τιμές πολύ μετά το τέλος (DP-09).
  static void mergeHrSegment(Session s, List<List<int>> seg, {int? watchAvg, int? watchMax}) {
    if (seg.isEmpty) {
      if (watchMax != null && (s.hrMax == null || watchMax > s.hrMax!)) s.hrMax = watchMax;
      return;
    }
    final sorted = sortedHr(seg);
    final from = sorted.first[0], to = sorted.last[0];
    final other = s.hr.where((p) => p[0] < from || p[0] > to).toList();
    s.hr
      ..clear()
      ..addAll(other)
      ..addAll(sorted)
      ..sort((a, b) => a[0].compareTo(b[0]));
    final end = s.end;
    var cut = false;
    if (end != null) {
      final last = end.difference(s.start).inSeconds + 60;
      final n0 = s.hr.length;
      s.hr.removeWhere((p) => p[0] > last);
      cut = s.hr.length < n0;
    }
    s.hrInFile = false;
    s.hrRev++;
    if (s.hr.isEmpty) return;
    var max = 0, sum = 0;
    for (final p in s.hr) {
      sum += p[1];
      if (p[1] > max) max = p[1];
    }
    // R9-A8-2: ο μέσος και ο υψηλότερος του ρολογιού είναι όλης της μέτρησης· αν κόπηκαν τιμές μετά το τέλος (ξεχασμένη
    // προπόνηση, το ρολόι μετρούσε ώρες ακόμα), είναι και αυτών: τότε μόνο από τις τιμές που έμειναν (πριν: μέσος 85 της
    // καθημερινότητας για προπόνηση με 114).
    s.hrAvg = other.isEmpty && watchAvg != null && !cut ? watchAvg : (sum / s.hr.length).round();
    // Ο υψηλότερος μόνο ανεβαίνει (και του ρολογιού, όπως τον μέτρησε εκείνο) — εκτός αν κόπηκαν τιμές (R9-A8-2).
    s.hrMax = cut ? max : [max, s.hrMax ?? 0, watchMax ?? 0].reduce((a, b) => a > b ? a : b);
  }

  /// Ό,τι έγινε μόνο στο ρολόι (προπόνηση, περπάτημα) ή οι παλμοί μιας προπόνησης του κινητού. true αν άλλαξε κάτι.
  bool importWatch(Map<String, dynamic> j) {
    final kind = j['kind'] as String? ?? 'strength';
    final samples = [
      for (final p in (j['hr'] is List ? j['hr'] as List : const []))
        if (p is List && p.length == 2 && p[0] is num && p[1] is num) [(p[0] as num).toInt(), (p[1] as num).toInt()],
    ];
    final hrAvg = j['hrAvg'] is num ? (j['hrAvg'] as num).toInt() : null;
    final hrMax = j['hrMax'] is num ? (j['hrMax'] as num).toInt() : null;
    // Παλιό «Νιώθω κάτι» από ρολόι ως #84: δεν υπάρχει πια.
    if (kind == 'sym') return false;
    if (kind == 'hr') {
      final sid = j['sid'] as String?;
      if (sid != null && deleted.contains(sid)) return false;
      Session? s;
      for (final x in [...sessions, if (current != null) current!]) {
        if (x.id == sid) s = x;
      }
      // round1, U6-01: προπόνηση που σβήστηκε εδώ χωρίς σετ, ενώ στο ρολόι έγιναν σετ (round2, R2-C-1: μόνο με ✓).
      s ??= _fromDropped(sid, j, samples);
      if (s == null) return false;
      // Πρώτα τα σετ του ρολογιού, μετά το τέλος, μετά οι παλμοί (round1, S11-4): αν η προπόνηση έκλεισε στο κινητό
      // νωρίτερα απ' ό,τι τελείωσε πράγματι στο ρολόι, οι παλμοί της συνέχειας δεν πρέπει να κοπούν ως «μετά το τέλος».
      _mergeWatchSets(s, j['items']);
      if (!identical(s, current)) _extendEndFromWatch(s, j['fin']);
      // R7-A8-3: όπως τα ✓ ([_mergeWatchSets]), όχι παλμοί [staleAfter] ή περισσότερο μετά την τελευταία κίνηση.
      final upTo = (s.lastActivity.millisecondsSinceEpoch + staleAfter.inMilliseconds - s.start.millisecondsSinceEpoch) ~/ 1000;
      final aligned = [for (final p in alignHr(samples, j['hrT0'], s.start)) if (p[0] < upTo) p];
      if (s.hrLoaded) {
        mergeHrSegment(s, aligned, watchAvg: hrAvg, watchMax: hrMax);
      } else {
        // Οι παλμοί της είναι στο αρχείο τους: η ένωση γίνεται στην εγγραφή, αφού διαβαστεί (καμία απώλεια).
        (_segments[s.id] ??= []).add((aligned, hrAvg, hrMax));
        if (hrMax != null && (s.hrMax == null || hrMax > s.hrMax!)) s.hrMax = hrMax;
      }
      // Προπόνηση του κινητού που ξεκίνησε πριν από την #90 (χωρίς όριο μέσα): το όριο που είχε το ρολόι.
      s.limit ??= Session.watchLimit(j['lim']);
      _watchHrInfo(s, j);
      // «Τέλος» στο ρολόι (V-A-09): τέλος και εδώ, με την ώρα του ρολογιού (αν δεν συνέχισε στο κινητό στο μεταξύ).
      final fin = j['fin'];
      if (fin is num && sid != null) endFromWatch(sid, fin.toInt(), fromResult: true);
      save();
      return true;
    }
    final id = 'w-${j['id']}';
    if (deleted.contains(id)) return false;
    final start = DateTime.fromMillisecondsSinceEpoch((j['start'] as num).toInt());
    final end = DateTime.fromMillisecondsSinceEpoch((j['end'] as num? ?? j['start'] as num).toInt());
    final partial = j['partial'] == 1;
    // Ίδιο αποτέλεσμα ξανά: τίποτα. Μερικό (η εφαρμογή του ρολογιού έκλεισε απότομα) και μετά το κανονικό ή ένα
    // πληρέστερο: «το τελικό κερδίζει» (έλεγχος 9/11, V-A-14).
    final old = sessions.indexWhere((x) => x.id == id);
    if (old >= 0) {
      final o = sessions[old];
      final better = o.partial && (!partial || end.isAfter(o.end ?? o.start));
      if (!better) return false;
    }
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
      hr: alignHr(samples, j['hrT0'], start),
      source: 'watch',
      // «Σταμάτησα» από ρολόι με παλιά έκδοση (ως #84): δεν μετρά για την πρόοδο.
      stopped: j['stop'] == 1,
      // Το όριο που είχε το ρολόι σε αυτή την άσκηση (ρολόι #90 και μετά· 0 = χωρίς όριο). Ρολόι παλιότερης έκδοσης δεν
      // το στέλνει: τότε το όριο του κινητού τη στιγμή της εισαγωγής. Είναι το ίδιο που είχε σταλεί στο ρολόι, εκτός αν
      // άλλαξε στο κινητό ανάμεσα στην άσκηση και στη μεταφορά της (σπάνιο).
      limit: Session.watchLimit(j['lim']) ?? hrLimit ?? 0,
      partial: partial,
    );
    if (s.stopped) s.note = 'Σταμάτησε: «Σταμάτησα» στο ρολόι';
    // R9-A8-3: η απάντηση «Πρώτο σετ» του ρολογιού («fr»), όπου δεν υπάρχει ήδη («fa»).
    for (final e in s.items) {
      e.firstAnswer ??= watchFirstAnswer(e);
    }
    _watchHrInfo(s, j);
    if (cardio != null) {
      // Ρολόι παλιότερης έκδοσης έστελνε 0 όταν το Health Services δεν έδωσε χρόνο (έλεγχος γ2, W2-11): τότε από τις ώρες.
      final raw = (cardio['sec'] as num?)?.toInt();
      final watchSec = raw != null && raw > 0 ? raw : null;
      final sec = watchSec ?? end.difference(start).inSeconds;
      s.cardioMinutes = (sec / 60).round();
      s.meters = (cardio['m'] as num?)?.toDouble();
      // 14/11: η απόσταση από τα βήματα (ρολόι από #114). Παλιό ρολόι: τίποτα.
      final mest = cardio['mest'];
      s.metersEst = mest is num && mest.isFinite && mest > 0 ? mest.toDouble() : null;
      s.steps = (cardio['steps'] as num?)?.toInt();
      // 9/11: ενεργός χρόνος, GPS, χιλιόμετρα, παύσεις, πτώση παλμών στο 1′ (ρολόι από #89).
      s.cardioSec = watchSec;
      if (cardio['gps'] is bool) s.gps = cardio['gps'] as bool;
      if (cardio['activity'] is String) s.activity = cardio['activity'] as String;
      // Η ζώνη που είχε το ρολόι (ρολόι από 12/11), αλλιώς η ζώνη του κινητού τη στιγμή της εισαγωγής.
      final wz = WalkZone.fromJson(cardio['zone']) ?? zone;
      if (wz != null && (s.activity == null || s.activity == 'walk')) {
        s.zoneLo = wz.lo;
        s.zoneHi = wz.hi;
      }
      s.splits.addAll(Session.pairs(cardio['km']));
      s.pauses.addAll(Session.pairs(cardio['pz']));
      final zlo = s.zoneLo, zhi = s.zoneHi;
      if (zlo != null && zhi != null && s.hr.isNotEmpty) {
        final z = zoneTimes(s.hr, s.pauses, zlo, zhi, endSec: end.difference(start).inSeconds);
        if (z.measured > 0) s.zoneTimes = [z.below, z.inZone, z.above];
      }
      final hrr = cardio['hrr'];
      if (hrr is Map && hrr['e'] is num && hrr['m'] is num) {
        final e = (hrr['e'] as num).toInt(), m = (hrr['m'] as num).toInt();
        // Μόνο λογικές τιμές (παλμοί 30–230): αλλιώς τίποτα.
        if (e >= 30 && e <= 230 && m >= 30 && m <= 230) {
          s.hrrEnd = e;
          s.hrr1 = m;
        }
      }
    }
    if (old >= 0) {
      // Ό,τι έγραψε ο χρήστης στο μερικό μένει.
      final o = sessions[old];
      s.feel ??= o.feel;
      if (o.note != null && s.note == null) s.note = o.note;
      sessions[old] = s;
      save();
      return true;
    }
    var at = sessions.length;
    while (at > 0 && sessions[at - 1].start.isAfter(start)) {
      at--;
    }
    sessions.insert(at, s);
    save();
    return true;
  }

  /// «Τέλος» στο ρολόι για την προπόνηση του κινητού [sid] τη στιγμή [at] (ms, έλεγχος 9/11, V-A-09): τέλος και εδώ, με
  /// εκείνη την ώρα. Χωρίς κανένα σετ: σβήνεται (όπως το «Κανένα σετ → Σβήσιμο» του κινητού· το ρολόι το λέει πριν από
  /// το δεύτερο πάτημα), ώστε να μη μένει ανοιχτή. Όχι αν συνέχισες στο κινητό μετά.
  ///
  /// [fromResult]: ήρθε με το αποτέλεσμα του ρολογιού («fin»), ΑΦΟΥ ενώθηκαν τα σετ και οι παλμοί του. Μόνο τότε μια
  /// προπόνηση χωρίς σετ σβήνεται — και μόνο αν δεν έφτασε κανένας παλμός· η εντολή «end» μόνη της (μήνυμα) δεν σβήνει
  /// τίποτα, γιατί ✓ και παλμοί μπορεί να έρχονται ακόμα (έλεγχος του #91, N-M1).
  bool endFromWatch(String sid, int at, {bool fromResult = false}) {
    final s = current;
    if (s == null || s.id != sid) return false;
    if (at < s.lastActivity.millisecondsSinceEpoch - 60000) return false;
    if (s.setsDone == 0) {
      if (!fromResult) return false;
      if (s.hr.isEmpty) {
        endedByWatch = null;
        discardedByWatch = true;
        discard();
        return true;
      }
    }
    final lo = s.start.millisecondsSinceEpoch;
    final n = now.millisecondsSinceEpoch;
    // R7-A8-3: «Τέλος» στο ρολόι ώρες μετά την τελευταία κίνηση (ξεχασμένη προπόνηση): τέλος στο τελευταίο ✓, όπως το
    // [finish] και η «Ξεχασμένη προπόνηση;», ποτέ διάρκεια 25 ωρών. R9-A8-1: το τελευταίο ✓ ([Session.lastTick]), όχι η
    // «Συνέχεια» ([Session.resumedAt]): αυτή κρατά την προπόνηση ανοιχτή, αλλά δεν είναι κίνηση μέσα της.
    final last = s.lastTick.millisecondsSinceEpoch;
    final t = at - last < staleAfter.inMilliseconds ? at : last;
    final end = t < lo ? lo : (t > n ? (n < lo ? lo : n) : t);
    finish(end: DateTime.fromMillisecondsSinceEpoch(end));
    endedByWatch = s;
    return true;
  }

  /// Προπόνηση του κινητού που έκλεισε ΕΔΩ πριν τελειώσει πράγματι (round1, S11-4): το κινητό έσβησε στη μέση, η
  /// άσκηση συνεχίστηκε στο ρολόι, και την επομένη πατήθηκε «Τέλος (στις 18:05)» στην «Ξεχασμένη προπόνηση;» πριν φτάσει
  /// το αποτέλεσμα του ρολογιού. Αν το ρολόι έχει ✓ πάνω από 1′ ΜΕΤΑ το τέλος που γράφτηκε, η προπόνηση συνεχίστηκε εκεί:
  /// τέλος γίνεται το «Τέλος» του ρολογιού ([fin]) — ή το τελευταίο ✓, αν το [fin] λείπει ή είναι πάνω από
  /// [staleAfter] μετά από αυτό (ξεχασμένο ρολόι). Ποτέ νωρίτερα από πριν, ποτέ στο μέλλον. Χωρίς τέτοιο ✓ δεν αλλάζει
  /// τίποτα: το ρολόι απλώς μετρούσε ακόμα (DP-09).
  void _extendEndFromWatch(Session s, Object? fin) {
    final end = s.end;
    if (end == null) return;
    // R9-A8-1: μόνο ✓ ([Session.lastTick]) μεταφέρει το τέλος· η «Συνέχεια» μόνη της όχι (πριν: «Τέλος (στις 19:00)» και
    // μετά το αποτέλεσμα του ρολογιού → τέλος την ώρα της «Συνέχειας», την επομένη).
    final last = s.lastTick.millisecondsSinceEpoch;
    if (last <= end.millisecondsSinceEpoch + 60000) return;
    var to = last;
    if (fin is num && fin.isFinite) {
      final f = fin.toInt();
      if (f > last && f - last <= staleAfter.inMilliseconds) to = f;
    }
    final n = now.millisecondsSinceEpoch;
    if (to > n) to = n;
    if (to <= end.millisecondsSinceEpoch) return;
    s.end = DateTime.fromMillisecondsSinceEpoch(to);
  }

  /// Ανοιχτή προπόνηση χωρίς καμία κίνηση εδώ και [staleAfter] (V-A-09): «Ξεχασμένη προπόνηση;».
  bool isStale(Session s) => now.difference(s.lastActivity) >= staleAfter;

  /// R7-A8-3: κάτι από το ρολόι τη στιγμή [atMs] (✓, παλμός, εντολή) ανήκει στην ανοιχτή προπόνηση [s] μόνο αν απέχει
  /// λιγότερο από [staleAfter] από την τελευταία της κίνηση (αρχή ή ✓). Αλλιώς είναι από άλλη μέρα (π.χ. την επομένη, σε
  /// ρολόι που «μπήκε» σε ξεχασμένη προπόνηση): δεν γράφεται μέσα της και δεν την κάνει πάλι «ενεργή». Ένα ✓ του
  /// ρολογιού που άργησε να φτάσει (ίδια ώρα με τα υπόλοιπα) γράφεται κανονικά. Από το κινητό αποφασίζει ο χρήστης στην
  /// «Ξεχασμένη προπόνηση;» (εκεί το «Συνέχισε» δέχεται κάθε ✓).
  bool belongs(Session s, int atMs) => atMs - s.lastActivity.millisecondsSinceEpoch < staleAfter.inMilliseconds;

  /// R8-A8-3: «Συνέχεια» στην «Ξεχασμένη προπόνηση;»: η προπόνηση ξαναγίνεται ενεργή από τώρα ([Session.resumedAt]), και
  /// για το ρολόι (παλμοί, ✓, ρεζέρβα γράφονται ξανά μέσα της, [belongs]). Πριν, ως το πρώτο ✓ στο κινητό, όλα πετιούνταν.
  void resume(Session s) {
    if (!identical(current, s)) return;
    s.resumedAt = now.millisecondsSinceEpoch;
    save();
  }

  static void _watchHrInfo(Session s, Map<String, dynamic> j) {
    if (j['hrMode'] is String) s.hrMode = j['hrMode'] as String;
    if (j['hrGap'] is num) s.hrGap = (j['hrGap'] as num).toInt();
    // Έλεγχος γ2 (W2-08/W2-14): νέα πεδία του ρολογιού (το παλιό ρολόι δεν τα στέλνει).
    if (j['hrDel'] is num) s.hrDel = (j['hrDel'] as num).toInt();
    if (j['err'] is String) s.watchErr = (j['err'] as String).length > 120 ? (j['err'] as String).substring(0, 120) : j['err'] as String;
    if (j['diag'] is String) s.watchDiag = (j['diag'] as String).length > 40 ? (j['diag'] as String).substring(0, 40) : j['diag'] as String;
  }

  /// R8-A8-2: στο αποτέλεσμα «hr» το ρολόι σημειώνει με «c»: 1 τα ✓ που το κινητό είχε ήδη δει (ρολόι από τον γύρο 8·
  /// το παλιό δεν το στέλνει, και τότε όπως πριν).
  static bool _phoneSaw(SetLog ws) => ws.extra['c'] == 1 || ws.extra['c'] == true;

  /// R9-A8-3 (συμβόλαιο με το ρολόι, f3, CROSS.md): η απάντηση του ρολογιού στο «Πρώτο σετ» μέσα στο αποτέλεσμα («fr» στην
  /// άσκηση: 0–4, −1 = «Δεν ξέρω»), αντίγραφο της εντολής «rir1» για όταν εκείνη χάθηκε (κινητό που δεν άκουγε). null αν
  /// λείπει ή δεν είναι αριθμός. Ρολόι παλιότερης έκδοσης δεν το στέλνει: όπως πριν.
  static int? watchFirstAnswer(ExLog w) {
    final v = w.extra['fr'];
    if (v is! num || !v.isFinite) return null;
    final a = v.toInt();
    return a < 0 ? -1 : (a > 4 ? 4 : a);
  }

  /// Σετ που πατήθηκαν ✓ στο ρολόι αλλά δεν έφτασαν στο κινητό (π.χ. η εφαρμογή ήταν κλειστή): προστίθενται.
  /// Ποτέ δεν σβήνει ή αλλάζει ό,τι έχει ήδη γραφτεί στο κινητό — με μία εξαίρεση (τελικός έλεγχος, Συμβούλιο 4, W-4):
  /// επαναλήψεις που διόρθωσες στο ρολόι και η διόρθωση δεν έφτασε ποτέ, ενώ στο κινητό δεν άλλαξε τίποτα στο μεταξύ
  /// ([watchResultReps]).
  void _mergeWatchSets(Session s, Object? items) {
    if (items is! List) return;
    final n = items.length < s.items.length ? items.length : s.items.length;
    final parsed = List<ExLog?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      final raw = items[i];
      if (raw is! Map) continue;
      try {
        parsed[i] = ExLog.fromJson(raw.cast<String, dynamic>());
      } catch (_) {
        continue;
      }
    }
    // R7-A8-3: τα ✓ του ρολογιού με τη σειρά της ώρας· όποιο απέχει [staleAfter] ή περισσότερο από την προηγούμενη
    // κίνηση της προπόνησης (και ό,τι ακολουθεί) είναι άλλης μέρας ([belongs]) και δεν γράφεται εδώ.
    final ats = <int>[];
    for (var i = 0; i < n; i++) {
      final w = parsed[i];
      final e = s.items[i];
      if (w == null || w.ex != e.ex || e.skipped) continue;
      for (var k = 0; k < w.log.length && k < e.log.length; k++) {
        final a = w.log[k].at;
        if (w.log[k].done && !e.log[k].done && !_phoneSaw(w.log[k]) && a != null) ats.add(a);
      }
    }
    ats.sort();
    var ref = s.lastActivity.millisecondsSinceEpoch;
    for (final a in ats) {
      if (a - ref >= staleAfter.inMilliseconds) break;
      if (a > ref) ref = a;
    }
    final cutoff = ref + staleAfter.inMilliseconds;
    for (var i = 0; i < n; i++) {
      final w = parsed[i];
      if (w == null) continue;
      final e = s.items[i];
      if (w.ex != e.ex || e.skipped) continue;
      for (var k = 0; k < w.log.length && k < e.log.length; k++) {
        final ws = w.log[k], ps = e.log[k];
        if (ws.done && ps.done) {
          final r = watchResultReps(phoneReps: ps.reps, phoneAt: ps.at, watchReps: ws.reps, watchAt: ws.at, before: ws.extra['rb']);
          if (r != null) ps.reps = r;
          continue;
        }
        if (!ws.done || ps.done) continue;
        // R8-A8-2: ✓ που το κινητό είχε ήδη δει («c»: το ρολόι το έχει «επιβεβαιωμένο») και δεν το έχει πια: το έσβησες
        // εδώ και το ρολόι δεν έμαθε την αναίρεση (π.χ. χωρίς Bluetooth). Δεν ξαναμπαίνει.
        if (_phoneSaw(ws)) continue;
        final at = ws.at;
        if (at != null && at >= cutoff) continue;
        ps
          ..done = true
          ..reps = ws.reps
          ..at = at;
        if (ws.load != null) ps.load = ws.load;
      }
      if (e.rirAnswer == null && w.rirAnswer != null && e.complete) e.rirAnswer = w.rirAnswer!.clamp(0, 4);
      // R9-A8-3: η απάντηση «Πρώτο σετ» του ρολογιού, αν η «rir1» δεν έφτασε. Η πρώτη απάντηση κερδίζει: μόνο αν εδώ δεν
      // υπάρχει καμία (ίδιο αποτέλεσμα ξανά: τίποτα). Αν η ερώτηση εκκρεμεί ακόμα, όπως η «rir1» (βάρος για τα επόμενα
      // σετ)· αλλιώς μόνο για το αρχείο (τη διαβάζει η πρόοδος, R9-A6-4).
      final fr = watchFirstAnswer(w);
      if (fr != null && e.firstAnswer == null) {
        if (firstPending(e)) {
          answerFirst(e, fr);
        } else {
          e.firstAnswer = fr;
        }
      }
    }
  }

  /// R9-U3-06: η προπόνηση που διάλεξες από τις τρεις τελείες της «Άσκησης» για σήμερα (id) και ποια μέρα. Μόνο στη μνήμη,
  /// όχι στο αρχείο: ισχύει μόνο εκείνη τη μέρα και ως να ξεκινήσει μια προπόνηση (R8-U3-05). Εδώ, και όχι στη σελίδα, για
  /// να λέει (και να ξεκινά) την ίδια προπόνηση και η κάρτα «Άσκηση σήμερα» της Σήμερα.
  (String, DateTime)? _chosen;

  /// Η προπόνηση που διάλεξες για τη μέρα [day] (id), αν η επιλογή είναι εκείνης της μέρας.
  String? chosenOn(DateTime day) {
    final ch = _chosen;
    if (ch == null) return null;
    final d = ch.$2;
    return d.year == day.year && d.month == day.month && d.day == day.day ? ch.$1 : null;
  }

  /// Διαλέγει ([id]) ή καθαρίζει (null) την προπόνηση της μέρας [day]· μόνο στη μνήμη.
  void choose(String? id, DateTime day) {
    _chosen = id == null ? null : (id, day);
    notifyListeners();
  }

  Session start(Workout w) {
    final p = program!;
    // R8-U3-05 / R9-U3-06: η επιλογή «για σήμερα» τελειώνει με την προπόνηση που ξεκινά.
    _chosen = null;
    endedByWatch = null;
    discardedByWatch = false;
    _focus = 0;
    _restEnd = null;
    final s = Session(
      id: 's${now.millisecondsSinceEpoch}',
      workout: w.id,
      name: w.name,
      programId: p.id,
      start: now,
      items: [for (final i in w.items) _startLog(i)],
      // Το όριο που ισχύει τώρα μένει μέσα στην προπόνηση (V-B-04): 0 = χωρίς όριο.
      limit: hrLimit ?? 0,
    );
    current = s;
    save();
    return s;
  }

  /// «Ελεύθερη άσκηση» (9/11): χωρίς πρόγραμμα· οι ασκήσεις μπαίνουν μία-μία από τη βιβλιοθήκη. Το ρολόι ακολουθεί
  /// όπως σε κάθε προπόνηση του κινητού (παλμοί, ✓, διάλειμμα).
  Session startFree() {
    endedByWatch = null;
    discardedByWatch = false;
    _focus = 0;
    _restEnd = null;
    final s = Session(
      id: 's${now.millisecondsSinceEpoch}',
      workout: freeWorkoutId,
      name: 'Ελεύθερη άσκηση',
      programId: program?.id ?? '',
      start: now,
      items: [],
      limit: hrLimit ?? 0,
    );
    current = s;
    save();
    return s;
  }

  /// Νέα άσκηση στην προπόνηση που τρέχει. Σετ, επαναλήψεις και διάλειμμα όπως στο πρόγραμμα, αν η άσκηση είναι μέσα·
  /// αλλιώς 3 σετ, 8–12, διάλειμμα 90″. Τα κιλά από το ιστορικό της άσκησης (όπως σε κάθε προπόνηση).
  /// Γίνεται η τρέχουσα άσκηση. null χωρίς προπόνηση.
  ExLog? addExercise(String ex) {
    final cur = current;
    if (cur == null) return null;
    PlanItem? plan;
    for (final w in program?.workouts ?? const <Workout>[]) {
      for (final i in w.items) {
        if (i.ex == ex) plan ??= i;
      }
    }
    final e = _logFor(plan ?? PlanItem(ex: ex));
    cur.items.add(e);
    _focus = cur.items.length - 1;
    save();
    return e;
  }

  PlanItem? itemOf(ExLog e) {
    final w = program?.workout(current?.workout);
    if (w == null) return null;
    for (final i in w.items) {
      if (i.ex == e.ex || i.ex == e.swappedFrom) return i;
    }
    return null;
  }

  /// Πρώτη φορά για αυτή την άσκηση: κανένα σετ της σε προηγούμενη προπόνηση. Μετά το 1ο σετ ρωτάμε για βαθμονόμηση.
  /// round2, R2-E-1: ίδιος κανόνας με τον στόχο ([nextTarget]: όχι παραλειμμένη, τουλάχιστον ένα σετ). Πριν μετρούσε
  /// και μια προπόνηση χωρίς σετ (π.χ. «Τέλος» στο ρολόι με παλμούς αλλά χωρίς ✓) ή με την άσκηση παραλειμμένη: ο
  /// στόχος έλεγε «πρώτη φορά, θα σε ρωτήσει πώς πήγε» και η ερώτηση δεν ερχόταν ποτέ.
  /// R7-A6-2: και μια φορά με ενόχληση (ίσως χωρίς κανένα σετ) μετρά: μετά από πόνο δεν ρωτάμε για «βαθμονόμηση» προς τα
  /// πάνω, ο στόχος βγαίνει από τον κανόνα της ενόχλησης.
  bool isFirstTime(String ex) => !historyOf(ex).any((h) => (!h.$2.skipped && h.$2.done.isNotEmpty) || h.$2.pain.isNotEmpty);

  /// ✓ σε ένα σετ. [at]: η ώρα του ✓ στο ρολόι (ms), αν ήρθε από εκεί· κρατιέται μόνο αν είναι μέσα στην προπόνηση
  /// (από την αρχή της ως τώρα + 1′, για μικρές διαφορές ρολογιού), αλλιώς η ώρα του κινητού (9/11).
  void tick(ExLog e, int i, {int? at}) {
    final s = e.log[i];
    final n = now.millisecondsSinceEpoch;
    final start = current?.start.millisecondsSinceEpoch;
    s.done = true;
    s.at = at != null && start != null && at >= start && at <= n + 60000 ? at : n;
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

  /// R10-B4-1: «− Σετ»: βγάζει την τελευταία γραμμή, μόνο αν την πρόσθεσε το «+ Σετ» και δεν έγινε ([ExLog.canRemoveRow]).
  /// Ποτέ σετ του προγράμματος ή σετ με ✓. Το ρολόι παίρνει τη νέα κατάσταση με την αποθήκευση. true αν βγήκε.
  bool removeSet(ExLog e) {
    if (!e.canRemoveRow) return false;
    e.log.removeLast();
    save();
    return true;
  }

  void answer(ExLog e, int rir) {
    e.rirAnswer = rir;
    save();
  }

  /// Βαθμονόμηση πρώτης φοράς: μετά το 1ο σετ, πρόταση για τα επόμενα. Επιστρέφει το νέο βάρος ή null.
  double? calibrateAfterFirst(ExLog e, int rir) {
    if (e.log.isEmpty) return null;
    final item = _calibrationItem(e);
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

  /// Η άσκηση του προγράμματος με την οποία κρίνεται το 1ο σετ ([calibrateAfterFirst], [firstSetNote]).
  PlanItem _calibrationItem(ExLog e) {
    // round1, U6-02 (f6b): και στην «Ελεύθερη άσκηση», που δεν έχει άσκηση προγράμματος: το εύρος της ίδιας της άσκησης.
    final base = itemOf(e) ?? PlanItem(ex: e.ex, sets: e.sets, lo: e.lo, hi: e.hi, rir: e.rir, rest: e.rest);
    // Άσκηση που μπήκε στη θέση άλλης (εναλλακτική, ή η πιο δύσκολη παραλλαγή, round1 S7-03): με τον δικό της εξοπλισμό,
    // όχι με του προγράμματος (αλλιώς τα σκαλιά θα ήταν π.χ. λάστιχου σε αλτήρα).
    return base.ex == e.ex ? base : PlanItem(ex: e.ex, sets: e.sets, lo: base.lo, hi: e.hi, rir: e.rir, rest: e.rest);
  }

  /// R8-A6-5: το μήνυμα όταν το «4+» του 1ου σετ δεν αλλάζει το βάρος ([calibrateNote]), ή null.
  String? firstSetNote(ExLog e, int rir) {
    if (e.log.isEmpty) return null;
    final first = e.log.first;
    return calibrateNote(_calibrationItem(e), first.load, first.reps, rir);
  }

  /// R8-U3-01: το 1ο σετ μιας άσκησης «πρώτης φοράς» έγινε ✓ στο ρολόι (όχι στο κινητό, όπου ρωτά αμέσως): η οθόνη της
  /// προπόνησης, αν είναι ανοιχτή, κάνει την ίδια ερώτηση «Πρώτο σετ: πόσες ακόμα θα έβγαζες;». Μόνο στη μνήμη.
  ExLog? firstAsk;

  /// Ίδιος κανόνας με την ερώτηση του κινητού (session_page `_done`): η ερώτηση εκκρεμεί ([firstPending]) και το [i]
  /// είναι το 1ο σετ ενώ κανένα σετ δεν έχει γίνει.
  bool asksFirstSet(ExLog e, int i) => i == 0 && e.done.isEmpty && firstPending(e);

  /// R8-U3-01 (συμβόλαιο με το ρολόι, «f» στο /ygeia/session): η ερώτηση «Πρώτο σετ: πόσες ακόμα θα έβγαζες;» εκκρεμεί
  /// για την [e]: πρώτη φορά, με φορτίο, πάνω από ένα σετ, δεν απαντήθηκε σε αυτή την προπόνηση, δεν παραλείφθηκε, και
  /// κανένα σετ μετά το 1ο δεν έχει γίνει (τότε η βαθμονόμηση δεν έχει πια νόημα).
  bool firstPending(ExLog e) {
    if (e.firstAnswer != null || e.skipped || !hasLoad(e.kind) || e.sets <= 1 || e.log.isEmpty || e.log.first.load == null) return false;
    for (var k = 1; k < e.log.length; k++) {
      if (e.log[k].done) return false;
    }
    return isFirstTime(e.ex);
  }

  /// R8-U3-01: η απάντηση στο «Πρώτο σετ», από όποια συσκευή έρθει πρώτη: [rir] 0–4 (βαθμονόμηση, [calibrateAfterFirst]) ή
  /// −1 για «Δεν ξέρω» (καμία αλλαγή). Μόνο όσο η ερώτηση εκκρεμεί: μια δεύτερη απάντηση δεν αλλάζει τίποτα ([applied]
  /// false). [load]: το νέο φορτίο των επόμενων σετ, ή null αν δεν άλλαξε.
  ({bool applied, double? load}) answerFirst(ExLog e, int rir) {
    if (!firstPending(e)) return (applied: false, load: null);
    final a = rir < 0 ? -1 : rir.clamp(0, 4);
    e.firstAnswer = a;
    final v = a < 0 ? null : calibrateAfterFirst(e, a);
    save();
    return (applied: true, load: v);
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
    // Το εύρος του προγράμματος, όχι το (ίσως χαμηλωμένο για σήμερα) κάτω όριο της άσκησης που φεύγει ([loFor]).
    final item = PlanItem(ex: ex, sets: e.sets, lo: base?.lo ?? e.lo, hi: e.hi, rir: e.rir, rest: e.rest, load: base?.ex == ex ? base?.load : null);
    final n = _logFor(item)..swappedFrom = e.swappedFrom ?? e.ex;
    cur.items[idx] = n;
    // R7-A8-4: ό,τι έγινε ήδη (σετ με ✓, ενόχληση) δεν χάνεται. Η άσκηση που φεύγει μένει στην προπόνηση με μόνο τα σετ
    // που έγιναν, ΣΤΟ ΤΕΛΟΣ (οι θέσεις των άλλων ασκήσεων δεν αλλάζουν: τα ✓ του ρολογιού πάνε με τη θέση), και κρατά τα
    // σετ του προγράμματος ([ExLog.plannedSets]) ώστε η πρόοδος να ξέρει ότι δεν έγιναν όλα. Ενόχληση χωρίς κανένα σετ:
    // μένει ως «παράλειψη» με την ενόχληση, που μετρά στον επόμενο στόχο.
    final done = e.done;
    if (done.isNotEmpty || e.pain.isNotEmpty) {
      cur.items.add(ExLog(
        ex: e.ex,
        sets: done.isEmpty ? e.sets : done.length,
        lo: e.lo,
        hi: e.hi,
        rir: e.rir,
        rest: e.rest,
        log: done.isEmpty ? e.log : done,
        rirAnswer: e.rirAnswer,
        pain: [...e.pain],
        skipped: done.isEmpty,
        swappedFrom: e.swappedFrom,
        reason: e.reason,
        plannedSets: done.isEmpty ? null : e.sets,
        // R10 (σημείωση του B5): η απάντηση στο «Πρώτο σετ» μένει με το 1ο σετ που έγινε (το διαβάζει η πρόοδος, R9-A6-4·
        // «fa» είναι πεδίο, όχι μέσα στο [ExLog.extra]). Μόνο αν το 1ο σετ είναι μέσα στα σετ που κρατήθηκαν.
        firstAnswer: e.log.isNotEmpty && e.log.first.done ? e.firstAnswer : null,
        extra: {...e.extra},
      ));
    }
    save();
  }

  /// Τέλος της προπόνησης. Χωρίς [end]: τώρα — εκτός αν είναι «ξεχασμένη» ([isStale]): τότε στο τελευταίο ✓, ποτέ
  /// διάρκεια 20 ωρών (V-A-09). R9-A8-1: «ξεχασμένη» εδώ μετρά από το τελευταίο ✓ ([Session.lastTick]), όχι από τη
  /// «Συνέχεια»: «Συνέχεια» στις 08:00 χωρίς κανένα ✓ μετά, και «Τέλος» στις 09:00, δεν δίνει διάρκεια 14 ωρών.
  void finish({int? feel, DateTime? end}) {
    final s = current;
    if (s == null) {
      // round1, S6-9: το ρολόι έκλεισε την προπόνηση όσο το κινητό έδειχνε το «Μπράβο, τελείωσες»· η «Αποθήκευση»
      // έρχεται μετά. Το «Πώς ένιωσες;» που διάλεξες δεν χάνεται: γράφεται στην προπόνηση που μόλις έκλεισε.
      final w = endedByWatch;
      if (feel != null && w != null) setFeel(w, feel);
      return;
    }
    s
      ..end = end ?? (now.difference(s.lastTick) >= staleAfter ? s.lastTick : now)
      ..feel = feel;
    // R9-A8-2: οι παλμοί μετά το τέλος (+1′, ο ίδιος κανόνας με το [mergeHrSegment], DP-09) δεν είναι της προπόνησης:
    // ξεχασμένη προπόνηση με το ρολόι να μετρά ώρες ακόμα έδινε μέσο (και υψηλότερο) της καθημερινότητας. Κόβονται, και
    // ο υψηλότερος ξαναβγαίνει από όσες έμειναν.
    // R10-B4-4: ο κανόνας ζει στο [Session.hrUpTo], ίδιος με τη σύνοψη πριν από την «Αποθήκευση».
    final cut = s.hrUpTo(s.end!);
    if (cut.hr.length < s.hr.length) {
      s.hr
        ..clear()
        ..addAll(cut.hr);
      s.hrRev++;
      s.hrInFile = false;
      s.hrMax = cut.max;
    }
    if (s.hr.isNotEmpty) s.hrAvg = cut.avg;
    // Στη θέση της με τη σειρά της ώρας (S6-15): μια «ξεχασμένη» προπόνηση που κλείνει μέρες μετά δεν μπαίνει πάνω
    // από ό,τι έγινε στο μεταξύ (π.χ. περπάτημα από το ρολόι).
    _insertByStart(s);
    current = null;
    _restEnd = null;
    save();
  }

  /// «Πώς ένιωσες;» για προπόνηση που έχει ήδη τελειώσει (round1, S6-9: «Τέλος» από το ρολόι) ή για την τρέχουσα.
  /// [feel] 1–5, ή null για να σβηστεί. Για προπόνηση που δεν είναι στην αποθήκη δεν κάνει τίποτα.
  void setFeel(Session s, int? feel) {
    if (!identical(s, current) && !sessions.contains(s)) return;
    s.feel = feel == null ? null : feel.clamp(1, 5);
    save();
  }

  void discard() {
    final s = current;
    if (s != null) _remember(s);
    current = null;
    _restEnd = null;
    save();
  }

  /// Μια προπόνηση που σβήνεται κρατιέται για λίγο ([_dropped], U6-01). Οι παλιότερες από [dropKeep] φεύγουν.
  void _remember(Session s) {
    final n = now.millisecondsSinceEpoch;
    _dropped
      ..removeWhere((x) => x['id'] == s.id || n - ((x['dropAt'] as num?)?.toInt() ?? 0) > dropKeep.inMilliseconds)
      ..add({...s.toJson(), 'dropAt': n});
    while (_dropped.length > dropMax) {
      _dropped.removeAt(0);
    }
  }

  /// Το αποτέλεσμα του ρολογιού για προπόνηση που σβήστηκε εδώ ([_remember]): αν φέρνει σετ που το κινητό δεν είδε
  /// ποτέ, η προπόνηση ξαναμπαίνει ως τελειωμένη, στη θέση της ώρας της, με τέλος τον τελευταίο παλμό ή το «Τέλος» του
  /// ρολογιού (τα σετ το μεγαλώνουν μετά, [_extendEndFromWatch]). Αλλιώς τίποτα (null): το αποτέλεσμα επιβεβαιώνεται
  /// στο ρολόι (wear_link.dart, `importDurably`) και δεν ξαναγυρίζει.
  ///
  /// round2, R2-C-1 = R2-E-1: ΜΟΝΟ με νέο ✓. Πριν έφτανε και ένας παλμός: όποιος πατούσε «Σβήσιμο» στο ζέσταμα με το
  /// «Παλμοί εδώ» ανοιχτό έβρισκε μια «τελειωμένη» προπόνηση 0 σετ — η «Σήμερα» έκρυβε το «Ξεκίνα» και, αφού η άσκηση
  /// είχε πια «ιστορικό», η πρώτη πραγματική προπόνηση δεν ρωτούσε για βαθμονόμηση. Η προπόνηση που σβήστηκε μένει
  /// κρατημένη ως τη λήξη της ([dropKeep], [dropMax]) και όχι στα [deleted]: ένα δεύτερο «Παλμοί εδώ» της ίδιας
  /// προπόνησης είναι άλλο αποτέλεσμα («hr<sid>-<αρχή>», Results.kt) και μπορεί να φέρει τα ✓ αργότερα — να μη χαθούν.
  /// Αρχείο παλμών (hr/) δεν γράφεται ποτέ για προπόνηση που δεν ξαναμπαίνει (μόνο για τις [sessions]).
  Session? _fromDropped(String? sid, Map<String, dynamic> j, List<List<int>> samples) {
    if (sid == null) return null;
    final at = _dropped.indexWhere((x) => x['id'] == sid);
    if (at < 0) return null;
    final Session s;
    try {
      s = Session.fromJson(Map<String, dynamic>.from(_dropped[at])..remove('dropAt'));
    } catch (_) {
      return null;
    }
    // Τα σετ του ρολογιού σε ένα αντίγραφο (δεν είναι ακόμα στην αποθήκη): με τον ίδιο κανόνα που θα τα ένωνε μετά
    // ([_mergeWatchSets]: ίδια άσκηση, όχι παραλειμμένη, σετ που δεν είχε γίνει). Ξανά στο [importWatch]: δεν αλλάζει τίποτα.
    final before = s.setsDone;
    _mergeWatchSets(s, j['items']);
    if (s.setsDone <= before) return null;
    _dropped.removeAt(at);
    final start = s.start.millisecondsSinceEpoch;
    var end = start;
    for (final p in alignHr(samples, j['hrT0'], s.start)) {
      if (start + p[0] * 1000 > end) end = start + p[0] * 1000;
    }
    final fin = j['fin'];
    if (fin is num && fin.isFinite && fin > end && fin - end <= staleAfter.inMilliseconds) end = fin.toInt();
    final n = now.millisecondsSinceEpoch;
    s.end = DateTime.fromMillisecondsSinceEpoch(end > n ? (n < start ? start : n) : end);
    _insertByStart(s);
    return s;
  }

  // ---------------------------------------------------------------- για τον Claude
  /// Σύνοψη για επικόλληση στη συζήτηση: πρόγραμμα, πρόοδος ανά άσκηση, ενοχλήσεις, παλμοί, πώς ένιωσες.
  String exportForClaude({int weeks = 8, Map<String, String> names = const {}}) {
    // Ημερολογιακές μέρες, όχι ώρες (round1, S11-11): 56 × 24 ώρες πάνω από μια αλλαγή ώρας έπεφταν μία ώρα έξω, και
    // κοντά στα μεσάνυχτα η πρώτη μέρα της σύνοψης έβγαινε λάθος (και οι προπονήσεις της έμεναν απέξω).
    final since = DateTime(now.year, now.month, now.day - weeks * 7);
    final list = [for (final s in sessions) if (s.finished && !s.start.isBefore(since)) s];
    final b = StringBuffer();
    final p = program;
    b.writeln('Υγεία & Φόρμα · σύνοψη προπόνησης (${_d(since)}–${_d(now)})');
    if (p != null) b.writeln('Πρόγραμμα: ${p.name} (έκδοση ${p.version}, ${p.author == 'claude' ? 'από τον Claude' : 'δικό μου'}), id ${p.id}');
    if (hrLimit != null) b.writeln('Όριο παλμών γιατρού: $hrLimit');
    final walks = [for (final s in list) if (s.isCardio) s];
    b.writeln('Προπονήσεις με βάρη: ${list.length - walks.length}');
    if (walks.isNotEmpty) {
      final km = walks.fold<double>(0, (a, s) => a + (s.meters ?? 0)) / 1000;
      final mins = walks.fold<int>(0, (a, s) => a + (s.cardioMinutes ?? 0));
      // R7-U4-14 θ: ενικός με το 1 και δεκαδικό κόμμα (το κείμενο επικολλάται στη συζήτηση): «1 φορά, 31 λεπτά, 2,2 km».
      b.writeln('Περπάτημα: ${walks.length == 1 ? '1 φορά' : '${walks.length} φορές'}, ${mins == 1 ? '1 λεπτό' : '$mins λεπτά'}'
          '${km > 0 ? ', ${km.toStringAsFixed(1).replaceAll('.', ',')} km' : ''}');
    }
    final hrAvgs = [for (final s in list) if (s.hrAvg != null) s.hrAvg!];
    if (hrAvgs.isNotEmpty) b.writeln('Μέσοι παλμοί ανά προπόνηση: ${hrAvgs.join(', ')}');
    final feels = [for (final s in list) if (s.feel != null) s.feel!];
    if (feels.isNotEmpty) b.writeln('Πώς ένιωσα (1 πολύ εύκολα – 5 πολύ δύσκολα): μέσος ${(feels.reduce((a, c) => a + c) / feels.length).toStringAsFixed(1).replaceAll('.', ',')}');
    final hrs = [for (final s in list) if (s.hrMax != null) s.hrMax!];
    if (hrs.isNotEmpty) b.writeln('Υψηλότεροι παλμοί: ${hrs.reduce((a, c) => a > c ? a : c)}');
    final byEx = <String, List<(DateTime, ExLog)>>{};
    for (final s in list) {
      for (final e in s.items) {
        // R7-A6-2: και η ενόχληση χωρίς κανένα σετ (σταμάτησες από πόνο) μετρά.
        if ((!e.skipped && e.done.isNotEmpty) || e.pain.isNotEmpty) (byEx[e.ex] ??= []).add((s.start, e));
      }
    }
    for (final entry in byEx.entries) {
      final logs = entry.value;
      final withSets = [for (final l in logs) if (l.$2.done.isNotEmpty) l];
      final k = loadKindOf(entry.key);
      final painN = logs.where((l) => l.$2.pain.isNotEmpty).length;
      b.write('- ${names[entry.key] ?? entry.key} [${entry.key}]: ${logs.length}×, ');
      if (withSets.isEmpty) {
        b.write('κανένα σετ');
      } else {
        final first = withSets.first.$2, last = withSets.last.$2;
        // R7-A6-11: το φορτίο που κατέληξε κάθε φορά (όπως η πρόοδος), και κάθε σετ με το δικό του όταν άλλαξε μέσα στην άσκηση.
        if (hasLoad(k)) b.write('${loadLabel(k, first.endLoad)} → ${loadLabel(k, last.endLoad)}, ');
        b.write('τελευταία ${_d(withSets.last.$1)}: ${last.mixedLoads ? last.doneText() : last.done.map((s) => s.reps).join(', ')}');
        if (last.rirAnswer != null) b.write(', ρεζέρβα ${last.rirAnswer == 4 ? '4+' : last.rirAnswer}');
      }
      if (painN > 0) b.write(', ενόχληση ${painN == 1 ? '1 φορά' : '$painN φορές'} (${{for (final l in logs) ...l.$2.pain}.map((x) => painNames[x] ?? x).join(', ')})');
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

  /// Επαναφορά από αντίγραφο: προσθέτει μόνο ό,τι λείπει (προγράμματα, προπονήσεις, με τους παλμούς τους). Ποτέ το όριο
  /// παλμών: αυτό το ξαναλές (έλεγχος 8/11, TRN-17). Επιστρέφει πόσες προπονήσεις μπήκαν· ό,τι δεν πήγε καλά το λέει το
  /// [mergeProblem] (έλεγχος 9/11, V-A-10: ποτέ σιωπηλή άρνηση).
  int mergeBackup(Map<String, dynamic> j) {
    mergeProblem = null;
    if (readError || !ready) {
      mergeProblem = newerFile
          ? 'Οι προπονήσεις δεν μπήκαν: το αρχείο προπονήσεων του κινητού είναι από νεότερη έκδοση. Ενημέρωσε την εφαρμογή.'
          : damaged
              // round1, S9-9: η έξοδος υπάρχει πια· να λέγεται εδώ, όχι μόνο στην Άσκηση.
              ? 'Οι προπονήσεις δεν μπήκαν: το αρχείο προπονήσεων του κινητού δεν διαβάζεται, οπότε δεν γράφεται τίποτα. Στην '
                  'Άσκηση › Προπόνηση πάτα «Κράτα το στην άκρη και συνέχισε» και κάνε ξανά την επαναφορά.'
              : 'Οι προπονήσεις δεν μπήκαν: το αρχείο προπονήσεων του κινητού δεν διαβάζεται, οπότε δεν γράφεται τίποτα.';
      return 0;
    }
    final v = j['v'];
    if (v is num && v > fileVersion) {
      mergeProblem = 'Οι προπονήσεις του αντιγράφου είναι από νεότερη έκδοση της εφαρμογής. Ενημέρωσε πρώτα την εφαρμογή.';
      return 0;
    }
    final other = TrainingStore(io: _io, clock: _clock);
    try {
      other._fromJson(j);
    } catch (_) {
      mergeProblem = 'Οι προπονήσεις του αντιγράφου δεν διαβάστηκαν.';
      return 0;
    }
    final hrz = j['hrz'] is Map ? Map<String, dynamic>.from(j['hrz'] as Map) : const <String, dynamic>{};
    final have = {for (final p in programs) '${p.id}#${p.version}'};
    for (final p in other.programs) {
      if (have.add('${p.id}#${p.version}')) programs.add(p);
    }
    activeId ??= other.activeId;
    // Ό,τι σβήστηκε (εδώ ή στο αντίγραφο) μένει σβησμένο.
    deleted.addAll(other.deleted);
    sessions.removeWhere((x) => deleted.contains(x.id));
    final ids = {for (final s in sessions) s.id};
    var added = 0;
    for (final s in other.sessions) {
      if (deleted.contains(s.id)) continue;
      if (ids.add(s.id)) {
        // Οι παλμοί της: μέσα στην προπόνηση (αντίγραφο ως #90) ή στο «hrz» (#91): γράφονται στο αρχείο τους εδώ.
        if (!s.hrLoaded) {
          final text = hrz[s.id];
          s.hr
            ..clear()
            ..addAll(text is String ? decodeHr(text) ?? const <List<int>>[] : const <List<int>>[]);
          s.hrLoaded = true;
          s.hrCount = 0;
        }
        s.hrInFile = false;
        sessions.add(s);
        added++;
      }
    }
    // Ό,τι δεν διαβάστηκε στο αντίγραφο κρατιέται κι αυτό (σε καραντίνα), και λέγεται.
    final known = {for (final q in quarantine) jsonEncode(q)};
    var bad = 0;
    for (final q in other.quarantine) {
      if (known.add(jsonEncode(q))) {
        quarantine.add(q);
        bad++;
      }
    }
    if (bad > 0) {
      mergeProblem = bad == 1
          ? '1 προπόνηση του αντιγράφου δεν διαβάστηκε· κρατήθηκε στο αρχείο.'
          : '$bad προπονήσεις του αντιγράφου δεν διαβάστηκαν· κρατήθηκαν στο αρχείο.';
    }
    sessions.sort((a, b) => a.start.compareTo(b.start));
    save();
    return added;
  }
}
