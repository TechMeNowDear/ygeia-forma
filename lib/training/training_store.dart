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
}

class ChannelTrainingIO implements TrainingIO {
  const ChannelTrainingIO();
  static const channel = MethodChannel('ygeia/training');

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
}

/// Για δοκιμές: στη μνήμη.
class MemoryTrainingIO implements TrainingIO {
  MemoryTrainingIO([this.json]);
  String? json;
  int writes = 0;

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
  String? saveError;

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

  /// Μετά από πόσο χωρίς κίνηση μια ανοιχτή προπόνηση είναι «ξεχασμένη» (V-A-09).
  static const staleAfter = Duration(hours: 3);

  /// Όριο παλμών από τον γιατρό (bpm), αν έδωσε: το ρολόι δονεί όταν το ξεπεράσεις. Κενό = τίποτα.
  int? hrLimit;

  /// Όλες οι εκδόσεις όλων των προγραμμάτων (η πιο πρόσφατη στο τέλος).
  final List<Program> programs = [];
  String? activeId;
  final List<Session> sessions = [];

  /// Προπονήσεις που σβήστηκαν (ids): να μην ξαναγυρίσουν από το ρολόι ή από παλιό αντίγραφο (9/11).
  final Set<String> deleted = {};
  Session? current;

  Future<void>? _loading;
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final r = await _io.read();
    if (r.state == 'ok' && r.json != null) {
      try {
        final j = jsonDecode(r.json!);
        if (j is! Map) throw const FormatException();
        final m = Map<String, dynamic>.from(j);
        final v = m['v'];
        if (v is num && v > fileVersion) {
          newerFile = true;
          readError = true;
        } else {
          _fromJson(m);
        }
      } catch (_) {
        readError = true;
      }
    } else if (r.state == 'error') {
      readError = true;
    }
    ready = true;
    notifyListeners();
    if (!readError) {
      // Μεταφορά (μία φορά): οι παλμοί που ήταν μέσα στο training.json πάνε στα δικά τους αρχεία και φεύγουν από τη
      // μνήμη (φορτώνονται μόνο όταν τους χρειαστεί μια σύνοψη).
      _release.addAll([for (final s in sessions) if (s.hrNeedsWrite) s.id]);
      if (_release.isNotEmpty) save();
      _queue = _queue.then((_) => _purgeDeletedHr());
    }
  }

  static const _knownTop = {'v', 'hrLimit', 'programs', 'active', 'sessions', 'del', 'current', 'bad', 'hrz'};

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
    sessions.clear();
    for (final x in (j['sessions'] is List ? j['sessions'] as List : const [])) {
      try {
        sessions.add(Session.fromJson(Map<String, dynamic>.from(x as Map)));
      } catch (_) {
        quarantine.add({'in': 'sessions', 'j': x});
      }
    }
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
    _segments.clear();
    _release.clear();
  }

  Map<String, dynamic> toJson() => {
        ..._extra,
        'v': fileVersion,
        if (hrLimit != null) 'hrLimit': hrLimit,
        'programs': [for (final p in programs) p.toJson()],
        if (activeId != null) 'active': activeId,
        // Οι παλμοί κάθε τελειωμένης προπόνησης στο δικό της αρχείο, μόλις γραφτεί αυτό· ως τότε μέσα (καμία απώλεια).
        'sessions': [for (final s in sessions) s.toJson(hrInline: !s.hrInFile)],
        if (deleted.isNotEmpty) 'del': deleted.toList(),
        if (current != null) 'current': current!.toJson(),
        if (quarantine.isNotEmpty) 'bad': quarantine,
      };

  Future<void> _queue = Future.value();

  /// Ό,τι είναι στη μνήμη έχει γραφτεί στο αρχείο: καμία εγγραφή σε αναμονή και η τελευταία πέτυχε (V-A-01).
  bool _written = true;

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
            s.hr
              ..clear()
              ..addAll(decodeHr(r.json));
            s.hrLoaded = true;
            s.hrInFile = true;
          }
        }
        for (final seg in _segments.remove(s.id) ?? const <(List<List<int>>, int?, int?)>[]) {
          mergeHrSegment(s, seg.$1, watchAvg: seg.$2, watchMax: seg.$3);
        }
        if (!s.hrNeedsWrite) continue;
        if (await _io.writeHr(s.id, encodeHr(s.hr))) {
          s.hrInFile = true;
          s.hrCount = s.hr.length;
          if (_release.remove(s.id)) {
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
    _written = ok && hrOk && _segments.isEmpty && gen == _gen;
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
    s.hr
      ..clear()
      ..addAll(decodeHr(r.json));
    s.hrLoaded = true;
    s.hrInFile = true;
    notifyListeners();
  }

  /// Αρχεία παλμών προπονήσεων που σβήστηκαν (V-A-02): σβήνονται στο επόμενο άνοιγμα (ως τότε η «Αναίρεση» τα βρίσκει).
  Future<void> _purgeDeletedHr() async {
    try {
      final ids = await _io.listHr();
      for (final id in ids) {
        if (deleted.contains(id) && !sessions.any((x) => x.id == id)) await _io.deleteHr(id);
      }
    } catch (_) {}
  }

  /// Το αντίγραφο ασφαλείας (V-A-02): όπως το training.json, και οι παλμοί όσων είναι στα αρχεία τους («hrz»).
  Future<Map<String, dynamic>> backupJson() async {
    await _queue;
    final j = toJson();
    final hrz = <String, String>{};
    for (final s in sessions) {
      if (!s.hrInFile) continue; // ήδη μέσα («hr»)
      if (s.hrLoaded) {
        if (s.hr.isNotEmpty) hrz[s.id] = encodeHr(s.hr);
      } else if (s.hrCount > 0) {
        final r = await _io.readHr(s.id);
        if (r.state == 'ok' && r.json != null) hrz[s.id] = r.json!;
      }
    }
    if (hrz.isNotEmpty) j['hrz'] = hrz;
    return j;
  }

  // ---------------------------------------------------------------- όριο παλμών
  /// Όριο παλμών από τον γιατρό (null = κανένα).
  void setHrLimit(int? hr) {
    hrLimit = hr;
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
      rir: item.rir < 2 ? 2 : item.rir,
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
    if (end != null) {
      final last = end.difference(s.start).inSeconds + 60;
      s.hr.removeWhere((p) => p[0] > last);
    }
    s.hrInFile = false;
    if (s.hr.isEmpty) return;
    var max = 0, sum = 0;
    for (final p in s.hr) {
      sum += p[1];
      if (p[1] > max) max = p[1];
    }
    s.hrAvg = other.isEmpty && watchAvg != null ? watchAvg : (sum / s.hr.length).round();
    // Ο υψηλότερος μόνο ανεβαίνει (και του ρολογιού, που μετρά και τιμές μέσα στο ίδιο δευτερόλεπτο).
    s.hrMax = [max, s.hrMax ?? 0, watchMax ?? 0].reduce((a, b) => a > b ? a : b);
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
      if (s == null) return false;
      final aligned = alignHr(samples, j['hrT0'], s.start);
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
      _mergeWatchSets(s, j['items']);
      // «Τέλος» στο ρολόι (V-A-09): τέλος και εδώ, με την ώρα του ρολογιού (αν δεν συνέχισε στο κινητό στο μεταξύ).
      final fin = j['fin'];
      if (fin is num && sid != null) endFromWatch(sid, fin.toInt());
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
    _watchHrInfo(s, j);
    if (cardio != null) {
      final sec = (cardio['sec'] as num?)?.toInt() ?? end.difference(start).inSeconds;
      s.cardioMinutes = (sec / 60).round();
      s.meters = (cardio['m'] as num?)?.toDouble();
      s.steps = (cardio['steps'] as num?)?.toInt();
      // 9/11: ενεργός χρόνος, GPS, χιλιόμετρα, παύσεις, πτώση παλμών στο 1′ (ρολόι από #89).
      s.cardioSec = (cardio['sec'] as num?)?.toInt();
      if (cardio['gps'] is bool) s.gps = cardio['gps'] as bool;
      if (cardio['activity'] is String) s.activity = cardio['activity'] as String;
      s.splits.addAll(Session.pairs(cardio['km']));
      s.pauses.addAll(Session.pairs(cardio['pz']));
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
  /// εκείνη την ώρα. Όχι αν δεν έγινε κανένα σετ (μένει ανοιχτή, για να αποφασίσεις), ούτε αν συνέχισες στο κινητό μετά.
  bool endFromWatch(String sid, int at) {
    final s = current;
    if (s == null || s.id != sid || s.setsDone == 0) return false;
    if (at < s.lastActivity.millisecondsSinceEpoch - 60000) return false;
    final lo = s.start.millisecondsSinceEpoch;
    final n = now.millisecondsSinceEpoch;
    final end = at < lo ? lo : (at > n ? (n < lo ? lo : n) : at);
    finish(end: DateTime.fromMillisecondsSinceEpoch(end));
    endedByWatch = s;
    return true;
  }

  /// Ανοιχτή προπόνηση χωρίς καμία κίνηση εδώ και [staleAfter] (V-A-09): «Ξεχασμένη προπόνηση;».
  bool isStale(Session s) => now.difference(s.lastActivity) >= staleAfter;

  static void _watchHrInfo(Session s, Map<String, dynamic> j) {
    if (j['hrMode'] is String) s.hrMode = j['hrMode'] as String;
    if (j['hrGap'] is num) s.hrGap = (j['hrGap'] as num).toInt();
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

  /// Πρώτη φορά για αυτή την άσκηση (χωρίς ιστορικό): μετά το 1ο σετ ρωτάμε για βαθμονόμηση.
  bool isFirstTime(String ex) => historyOf(ex).isEmpty;

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

  /// Τέλος της προπόνησης. Χωρίς [end]: τώρα — εκτός αν είναι «ξεχασμένη» ([isStale]): τότε στο τελευταίο ✓, ποτέ
  /// διάρκεια 20 ωρών (V-A-09).
  void finish({int? feel, DateTime? end}) {
    final s = current;
    if (s == null) return;
    s
      ..end = end ?? (isStale(s) ? s.lastActivity : now)
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

  /// Επαναφορά από αντίγραφο: προσθέτει μόνο ό,τι λείπει (προγράμματα, προπονήσεις, με τους παλμούς τους). Ποτέ το όριο
  /// παλμών: αυτό το ξαναλές (έλεγχος 8/11, TRN-17). Επιστρέφει πόσες προπονήσεις μπήκαν· ό,τι δεν πήγε καλά το λέει το
  /// [mergeProblem] (έλεγχος 9/11, V-A-10: ποτέ σιωπηλή άρνηση).
  int mergeBackup(Map<String, dynamic> j) {
    mergeProblem = null;
    if (readError || !ready) {
      mergeProblem = newerFile
          ? 'Οι προπονήσεις δεν μπήκαν: το αρχείο προπονήσεων του κινητού είναι από νεότερη έκδοση. Ενημέρωσε την εφαρμογή.'
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
            ..addAll(text is String ? decodeHr(text) : const <List<int>>[]);
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
