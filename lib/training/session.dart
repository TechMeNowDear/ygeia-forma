/// Μία προπόνηση που έγινε (ή γίνεται τώρα): ασκήσεις, σετ, απαντήσεις.
library;

import 'equipment.dart';

class SetLog {
  SetLog({this.load, required this.reps, this.done = false, this.at});

  /// kg (ή lb για λάστιχα). null για ασκήσεις σώματος.
  double? load;
  int reps;
  bool done;

  /// Πότε πατήθηκε ✓ (ms).
  int? at;

  Map<String, dynamic> toJson() => {if (load != null) 'l': load, 'r': reps, if (done) 'd': 1, if (at != null) 't': at};
  factory SetLog.fromJson(Map<String, dynamic> j) =>
      SetLog(load: (j['l'] as num?)?.toDouble(), reps: (j['r'] as num?)?.toInt() ?? 0, done: j['d'] == 1, at: (j['t'] as num?)?.toInt());
}

/// Τι έγινε σε μία άσκηση μέσα σε μία προπόνηση.
class ExLog {
  ExLog({
    required this.ex,
    required this.sets,
    required this.lo,
    required this.hi,
    required this.rir,
    required this.rest,
    List<SetLog>? log,
    this.rirAnswer,
    List<String>? pain,
    this.skipped = false,
    this.swappedFrom,
    this.reason,
  })  : log = log ?? [],
        pain = pain ?? [];

  String ex;
  final int sets, lo, hi, rir, rest;
  final List<SetLog> log;

  /// «Πόσες ακόμα θα έβγαζες» μετά το τελευταίο σετ: 0, 1, 2, 3, 4 (= 4+). null = δεν απαντήθηκε.
  int? rirAnswer;

  /// Ενοχλήσεις: «shoulderR», «shoulderL», «elbow», «back», «knee».
  final List<String> pain;
  bool skipped;
  String? swappedFrom;

  /// Γιατί αυτός ο στόχος (από την πρόοδο), για να φαίνεται.
  String? reason;

  LoadKind get kind => loadKindOf(ex);
  List<SetLog> get done => [for (final s in log) if (s.done) s];
  bool get complete => done.length >= sets;

  /// Το «κύριο» φορτίο: το μεγαλύτερο από τα σετ που έγιναν (για λάστιχο βοήθειας, το μικρότερο).
  double? get workLoad {
    double? v;
    for (final s in done) {
      if (s.load == null) continue;
      if (v == null) {
        v = s.load;
      } else if (kind == LoadKind.bandAssist ? s.load! < v : s.load! > v) {
        v = s.load;
      }
    }
    return v;
  }

  /// Όγκος σε kg (επαναλήψεις × κιλά· στο ζευγάρι αλτήρων μετράνε και οι δύο).
  double get volume {
    if (!usesKg(kind)) return 0;
    var v = 0.0;
    for (final s in done) {
      v += (s.load ?? 0) * s.reps * (kind == LoadKind.dbPair ? 2 : 1);
    }
    return v;
  }

  Map<String, dynamic> toJson() => {
        'ex': ex,
        'sets': sets,
        'lo': lo,
        'hi': hi,
        'rir': rir,
        'rest': rest,
        'log': [for (final s in log) s.toJson()],
        if (rirAnswer != null) 'ra': rirAnswer,
        if (pain.isNotEmpty) 'pain': pain,
        if (skipped) 'skip': 1,
        if (swappedFrom != null) 'from': swappedFrom,
        if (reason != null) 'why': reason,
      };

  factory ExLog.fromJson(Map<String, dynamic> j) => ExLog(
        ex: j['ex'] as String,
        sets: (j['sets'] as num).toInt(),
        lo: (j['lo'] as num).toInt(),
        hi: (j['hi'] as num).toInt(),
        rir: (j['rir'] as num?)?.toInt() ?? 2,
        rest: (j['rest'] as num?)?.toInt() ?? 90,
        log: [for (final s in (j['log'] as List? ?? const [])) SetLog.fromJson(s as Map<String, dynamic>)],
        rirAnswer: (j['ra'] as num?)?.toInt(),
        pain: [for (final p in (j['pain'] as List? ?? const [])) p as String],
        skipped: j['skip'] == 1,
        swappedFrom: j['from'] as String?,
        reason: j['why'] as String?,
      );
}

const painNames = {
  'shoulderR': 'δεξί ώμο',
  'shoulderL': 'αριστερό ώμο',
  'elbow': 'αγκώνα',
  'wrist': 'καρπό',
  'back': 'μέση',
  'knee': 'γόνατο',
};

class Session {
  Session({
    required this.id,
    required this.workout,
    required this.name,
    required this.programId,
    required this.start,
    this.end,
    List<ExLog>? items,
    this.feel,
    this.hrAvg,
    this.hrMax,
    this.cardioMinutes,
    this.note,
    List<List<int>>? hr,
    this.meters,
    this.steps,
    this.source,
    this.hrMode,
    this.hrGap,
  })  : items = items ?? [],
        hr = hr ?? [];

  final String id;
  final String workout;
  final String name;
  final String programId;
  final DateTime start;
  DateTime? end;
  final List<ExLog> items;

  /// «Πώς ένιωσες»: 1 (πολύ εύκολα) … 5 (πολύ δύσκολα).
  int? feel;
  int? hrAvg, hrMax;
  int? cardioMinutes;
  String? note;

  /// Παλμοί από το ρολόι: [δευτερόλεπτα από την αρχή, bpm] ανά ~10″.
  final List<List<int>> hr;

  /// Περπάτημα/αερόβια από το ρολόι: απόσταση (m) και βήματα.
  double? meters;
  int? steps;

  /// «watch» αν έγινε μόνο στο ρολόι.
  String? source;

  /// Πώς έφταναν οι παλμοί στο ρολόι: «5s» (ανά 5″ και με σβηστή οθόνη), «sensor» (εφεδρεία αισθητήρα),
  /// «default» (σε πακέτα όταν η οθόνη σβήνει). Και το μεγαλύτερο κενό σε δευτερόλεπτα (έλεγχος 8/11).
  String? hrMode;
  int? hrGap;

  bool get isCardio => cardioMinutes != null;

  bool get finished => end != null;
  int get setsDone => items.fold(0, (s, e) => s + e.done.length);
  double get volume => items.fold(0.0, (s, e) => s + e.volume);
  Duration get duration => (end ?? DateTime.now()).difference(start);

  Map<String, dynamic> toJson() => {
        'id': id,
        'w': workout,
        'name': name,
        'prog': programId,
        'start': start.millisecondsSinceEpoch,
        if (end != null) 'end': end!.millisecondsSinceEpoch,
        'items': [for (final e in items) e.toJson()],
        if (feel != null) 'feel': feel,
        if (hrAvg != null) 'hrAvg': hrAvg,
        if (hrMax != null) 'hrMax': hrMax,
        if (cardioMinutes != null) 'cmin': cardioMinutes,
        if (note != null) 'note': note,
        if (hr.isNotEmpty) 'hr': hr,
        if (meters != null) 'm': meters,
        if (steps != null) 'steps': steps,
        if (source != null) 'src': source,
        if (hrMode != null) 'hrm': hrMode,
        if (hrGap != null) 'hrg': hrGap,
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        workout: j['w'] as String? ?? '',
        name: j['name'] as String? ?? '',
        programId: j['prog'] as String? ?? '',
        start: DateTime.fromMillisecondsSinceEpoch((j['start'] as num).toInt()),
        end: j['end'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['end'] as num).toInt()),
        items: [for (final e in (j['items'] as List? ?? const [])) ExLog.fromJson(e as Map<String, dynamic>)],
        feel: (j['feel'] as num?)?.toInt(),
        hrAvg: (j['hrAvg'] as num?)?.toInt(),
        hrMax: (j['hrMax'] as num?)?.toInt(),
        cardioMinutes: (j['cmin'] as num?)?.toInt(),
        note: j['note'] as String?,
        hr: [
          for (final p in (j['hr'] as List? ?? const []))
            if (p is List && p.length == 2) [(p[0] as num).toInt(), (p[1] as num).toInt()],
        ],
        meters: (j['m'] as num?)?.toDouble(),
        steps: (j['steps'] as num?)?.toInt(),
        source: j['src'] as String?,
        hrMode: j['hrm'] as String?,
        hrGap: (j['hrg'] as num?)?.toInt(),
      );
}
