/// Μία προπόνηση που έγινε (ή γίνεται τώρα): ασκήσεις, σετ, απαντήσεις.
library;

import 'equipment.dart';

/// Τα κλειδιά που δεν ξέρει αυτή η έκδοση (από νεότερη ή παλιότερη), για να ξαναγραφτούν αυτούσια (έλεγχος 9/11,
/// V-A-07): μια αποθήκευση δεν σβήνει ποτέ κάτι που δεν καταλαβαίνει.
Map<String, dynamic> unknownKeys(Map<String, dynamic> j, Set<String> known) => {
      for (final e in j.entries)
        if (!known.contains(e.key)) e.key: e.value,
    };

class SetLog {
  SetLog({this.load, required this.reps, this.done = false, this.at, Map<String, dynamic>? extra}) : extra = extra ?? {};

  /// kg (ή lb για λάστιχα). null για ασκήσεις σώματος.
  double? load;
  int reps;
  bool done;

  /// Πότε πατήθηκε ✓ (ms).
  int? at;

  /// Κλειδιά άλλης έκδοσης (V-A-07).
  final Map<String, dynamic> extra;

  static const _known = {'l', 'r', 'd', 't'};

  Map<String, dynamic> toJson() => {...extra, if (load != null) 'l': load, 'r': reps, if (done) 'd': 1, if (at != null) 't': at};
  factory SetLog.fromJson(Map<String, dynamic> j) => SetLog(
        load: j['l'] is num ? (j['l'] as num).toDouble() : null,
        reps: j['r'] is num ? (j['r'] as num).toInt() : 0,
        done: j['d'] == 1,
        at: j['t'] is num ? (j['t'] as num).toInt() : null,
        extra: unknownKeys(j, _known),
      );
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
    Map<String, dynamic>? extra,
  })  : log = log ?? [],
        pain = pain ?? [],
        extra = extra ?? {};

  /// Κλειδιά άλλης έκδοσης (V-A-07).
  final Map<String, dynamic> extra;

  static const _known = {'ex', 'sets', 'lo', 'hi', 'rir', 'rest', 'log', 'ra', 'pain', 'skip', 'from', 'why'};

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
        ...extra,
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
        rir: j['rir'] is num ? (j['rir'] as num).toInt() : 2,
        rest: j['rest'] is num ? (j['rest'] as num).toInt() : 90,
        log: [for (final s in (j['log'] is List ? j['log'] as List : const [])) SetLog.fromJson(Map<String, dynamic>.from(s as Map))],
        rirAnswer: j['ra'] is num ? (j['ra'] as num).toInt() : null,
        pain: [for (final p in (j['pain'] is List ? j['pain'] as List : const [])) if (p is String) p],
        skipped: j['skip'] == 1,
        swappedFrom: j['from'] is String ? j['from'] as String : null,
        reason: j['why'] is String ? j['why'] as String : null,
        extra: unknownKeys(j, _known),
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

/// Το [Session.workout] της «Ελεύθερης άσκησης». Με «_» μπροστά, για να μη συμπέσει ποτέ με προπόνηση προγράμματος.
const freeWorkoutId = '_free';

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
    this.stopped = false,
    this.cardioSec,
    this.gps,
    this.activity,
    List<List<int>>? splits,
    List<List<int>>? pauses,
    this.hrrEnd,
    this.hrr1,
    this.limit,
    this.partial = false,
    Map<String, dynamic>? extra,
  })  : items = items ?? [],
        hr = hr ?? [],
        splits = splits ?? [],
        pauses = pauses ?? [],
        extra = extra ?? {};

  /// Κλειδιά άλλης έκδοσης, ή τιμές με τύπο που δεν διαβάζεται: ξαναγράφονται αυτούσια (έλεγχος 9/11, V-A-07).
  final Map<String, dynamic> extra;

  /// Από ρολόι που έκλεισε απότομα: γράφτηκε ως το τελευταίο στιγμιότυπο (έλεγχος 9/11, V-A-03). Αν έρθει μετά το
  /// κανονικό αποτέλεσμα, αντικαθιστά αυτό («το τελικό κερδίζει», V-A-14).
  bool partial;

  /// Οι παλμοί είναι στη μνήμη ([hr]). Όχι = είναι στο δικό τους αρχείο (hr/<id>.json, V-A-02) και φορτώνονται μόνο όταν
  /// τους χρειάζεται μια σύνοψη ([TrainingStore.ensureHr]).
  bool hrLoaded = true;

  /// Πόσες τιμές έχει το αρχείο παλμών (όταν δεν είναι στη μνήμη).
  int hrCount = 0;

  /// Οι παλμοί της μνήμης είναι ήδη, ίδιοι, στο αρχείο τους (δεν αποθηκεύεται). Όσο όχι, γράφονται μέσα στο
  /// training.json: έτσι καμία προπόνηση δεν χάνει παλμούς, από όπου κι αν μπήκε.
  bool hrInFile = false;

  /// Οι παλμοί πρέπει να γραφτούν στο αρχείο τους.
  bool get hrNeedsWrite => hrLoaded && !hrInFile && hr.isNotEmpty;

  /// Μετρητής αλλαγών των παλμών στη μνήμη (δεν αποθηκεύεται): μια εγγραφή του αρχείου «πιάνει» μόνο αν οι παλμοί δεν
  /// άλλαξαν όσο γραφόταν (έλεγχος του #91, M1).
  int hrRev = 0;

  /// Το αρχείο παλμών που δεν διαβάστηκε και κρατήθηκε στην άκρη (π.χ. «s1.json.bad»), ή null. Μένει στο training.json,
  /// για να μη χαθεί ποτέ η σύνδεση με αυτό (έλεγχος του #91, S1).
  String? hrBad;

  /// Υπάρχουν παλμοί (στη μνήμη ή στο αρχείο τους).
  bool get hasHr => hr.isNotEmpty || (!hrLoaded && hrCount > 0);

  /// «Παλμοί σταθερού βαδίσματος» (έλεγχος 9/11, V-B-11 / 03-M2α / 08-N-03): ο μέσος όρος από το 5ο λεπτό ενεργού
  /// χρόνου ως το «Τέλος», χωρίς τις παύσεις. Τα πρώτα λεπτά οι παλμοί ακόμα ανεβαίνουν (σταθερή κατάσταση μετά από
  /// 3–4′, Buchheit 2014), οπότε ο μέσος όλου του περπατήματος εξαρτάται από τη διάρκεια. Αποθηκεύεται («hrs»), γιατί
  /// οι παλμοί ζουν στο δικό τους αρχείο και δεν είναι πάντα στη μνήμη. null με λιγότερες από [steadyMinSamples] τιμές.
  int? hrSteady;

  static const steadyFromSec = 5 * 60;
  static const steadyMinSamples = 30;

  /// Η τιμή από τους παλμούς της μνήμης (όταν υπάρχουν), αλλιώς η αποθηκευμένη.
  int? get steadyHr => hrLoaded && hr.isNotEmpty ? (hrSteady = steadyFrom(hr, pauses)) : hrSteady;

  /// Υπολογισμός από [samples] ([δευτερόλεπτα από την αρχή, bpm]) και [pauses] ([αρχή, τέλος] σε δευτερόλεπτα).
  static int? steadyFrom(List<List<int>> samples, List<List<int>> pauses) {
    int pausedBefore(int t) {
      var p = 0;
      for (final x in pauses) {
        if (x[0] >= t) continue;
        p += (x[1] < t ? x[1] : t) - x[0];
      }
      return p;
    }

    var sum = 0, n = 0;
    for (final s in samples) {
      final t = s[0];
      if (pauses.any((x) => t >= x[0] && t <= x[1])) continue;
      if (t - pausedBefore(t) < steadyFromSec) continue;
      sum += s[1];
      n++;
    }
    return n < steadyMinSamples ? null : (sum / n).round();
  }

  /// Η τελευταία κίνηση στην προπόνηση: το τελευταίο ✓ (ή η αρχή, αν δεν έγινε κανένα). Για την «ξεχασμένη» προπόνηση
  /// (έλεγχος 9/11, V-A-09): το τέλος της δεν είναι «τώρα», 20 ώρες μετά.
  DateTime get lastActivity {
    var t = start.millisecondsSinceEpoch;
    for (final e in items) {
      for (final x in e.log) {
        if (x.done && x.at != null && x.at! > t) t = x.at!;
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(t);
  }

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

  /// Παλμοί από το ρολόι: [δευτερόλεπτα από την αρχή, bpm] (ανά 1″ από το ρολόι, ανά ~10″ ζωντανά).
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

  /// Σταμάτησε από σύμπτωμα (παλιές καταγραφές ως #84): δεν μετρά για την πρόοδο.
  bool stopped;

  /// Περπάτημα (9/11): ενεργός χρόνος σε δευτερόλεπτα (χωρίς τις παύσεις) και αν μετρούσε το GPS.
  int? cardioSec;
  bool? gps;

  /// Είδος αερόβιας από το ρολόι («walk»· στο μέλλον ίσως τρέξιμο, ποδήλατο). null σε παλιές καταγραφές, που ήταν
  /// όλες περπάτημα. Η «Πρόοδος» του περπατήματος δεν ανακατεύει άλλα είδη.
  String? activity;

  /// Κάθε ολόκληρο km: [ενεργός χρόνος ως εκεί (″), ώρα από την αρχή (″)].
  final List<List<int>> splits;

  /// Παύσεις: [αρχή, τέλος] σε δευτερόλεπτα από την αρχή.
  final List<List<int>> pauses;

  /// Πτώση παλμών στο 1′ μετά το «Τέλος»: παλμοί στο τέλος και στο 1′ (μετρημένα στο ρολόι), ή null.
  int? hrrEnd, hrr1;

  /// Το όριο παλμών του γιατρού που ίσχυε σε αυτή την προπόνηση (έλεγχος 9/11, V-B-04), ώστε η σύνοψη να την κρίνει με
  /// το δικό της όριο και όχι με το σημερινό. 0 = δεν υπήρχε όριο. null = δεν καταγράφηκε (προπονήσεις πριν από την #90).
  int? limit;

  /// Το όριο της προπόνησης, αν υπήρχε (null και όταν δεν καταγράφηκε).
  int? get limitUsed => (limit ?? 0) > 0 ? limit : null;

  bool get isCardio => cardioMinutes != null;

  /// «Ελεύθερη άσκηση»: χωρίς πρόγραμμα, οι ασκήσεις μπαίνουν μία-μία.
  bool get isFree => workout == freeWorkoutId;

  bool get finished => end != null;
  int get setsDone => items.fold(0, (s, e) => s + e.done.length);
  double get volume => items.fold(0.0, (s, e) => s + e.volume);
  Duration get duration => (end ?? DateTime.now()).difference(start);

  static const _known = {
    'id', 'w', 'name', 'prog', 'start', 'end', 'items', 'feel', 'hrAvg', 'hrMax', 'cmin', 'note', 'hr', 'hrf', 'm', 'steps', 'src',
    'hrm', 'hrg', 'stop', 'csec', 'gps', 'act', 'km', 'pz', 'hrrE', 'hrr1', 'lim', 'part', 'hrbad', 'hrs',
  };

  /// [hrInline]: οι παλμοί μέσα (όπως ως #90)· αλλιώς μόνο πόσοι είναι («hrf»), γιατί είναι στο δικό τους αρχείο.
  Map<String, dynamic> toJson({bool hrInline = true}) {
    final n = hrLoaded ? hr.length : hrCount;
    return {
      ...extra,
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
      if (hrInline && hrLoaded && hr.isNotEmpty) 'hr': hr,
      if ((!hrInline || !hrLoaded) && n > 0) 'hrf': n,
      if (meters != null) 'm': meters,
      if (steps != null) 'steps': steps,
      if (source != null) 'src': source,
      if (hrMode != null) 'hrm': hrMode,
      if (hrGap != null) 'hrg': hrGap,
      if (stopped) 'stop': 1,
      if (cardioSec != null) 'csec': cardioSec,
      if (gps != null) 'gps': gps,
      if (activity != null) 'act': activity,
      if (splits.isNotEmpty) 'km': splits,
      if (pauses.isNotEmpty) 'pz': pauses,
      if (hrrEnd != null) 'hrrE': hrrEnd,
      if (hrr1 != null) 'hrr1': hrr1,
      if (limit != null) 'lim': limit,
      if (partial) 'part': 1,
      if (hrBad != null) 'hrbad': hrBad,
      if (steadyHr case final v?) 'hrs': v,
    };
  }

  /// Λίστα από ζεύγη ακεραίων (π.χ. «km», «pz»), χωρίς ό,τι δεν είναι ζεύγος.
  static List<List<int>> pairs(Object? v) => [
        for (final p in (v is List ? v : const []))
          if (p is List && p.length == 2 && p[0] is num && p[1] is num) [(p[0] as num).toInt(), (p[1] as num).toInt()],
      ];

  /// Ανάγνωση με ανοχή (έλεγχος 9/11, V-A-10): μόνο το id και η αρχή είναι υποχρεωτικά (αλλιώς σφάλμα και η προπόνηση
  /// μπαίνει σε καραντίνα, όχι όλο το αρχείο)· ένα προαιρετικό αριθμητικό/λογικό πεδίο με λάθος τύπο μένει όπως ήταν
  /// στο [extra] (όχι τα «w», «name», «prog», που γράφονται πάντα).
  factory Session.fromJson(Map<String, dynamic> j) {
    final extra = unknownKeys(j, _known);
    T? opt<T>(String k) {
      final v = j[k];
      if (v == null) return null;
      if (v is T) return v;
      extra[k] = v;
      return null;
    }

    int? optInt(String k) => opt<num>(k)?.toInt();
    for (final k in const ['km', 'pz', 'hr']) {
      if (j[k] != null && j[k] is! List) extra[k] = j[k];
    }
    final hrRaw = j['hr'];
    final hr = <List<int>>[
      if (hrRaw is List)
        for (final p in hrRaw)
          if (p is List && p.length == 2 && p[0] is num && p[1] is num) [(p[0] as num).toInt(), (p[1] as num).toInt()],
    ];
    final hrf = optInt('hrf') ?? 0;
    final note = opt<String>('note');
    final s = Session(
      id: j['id'] as String,
      workout: opt<String>('w') ?? '',
      name: opt<String>('name') ?? '',
      programId: opt<String>('prog') ?? '',
      start: DateTime.fromMillisecondsSinceEpoch((j['start'] as num).toInt()),
      end: optInt('end') == null ? null : DateTime.fromMillisecondsSinceEpoch(optInt('end')!),
      items: [for (final e in (j['items'] is List ? j['items'] as List : const [])) ExLog.fromJson(Map<String, dynamic>.from(e as Map))],
      feel: optInt('feel'),
      hrAvg: optInt('hrAvg'),
      hrMax: optInt('hrMax'),
      cardioMinutes: optInt('cmin'),
      note: note,
      hr: hr,
      meters: opt<num>('m')?.toDouble(),
      steps: optInt('steps'),
      source: opt<String>('src'),
      hrMode: opt<String>('hrm'),
      hrGap: optInt('hrg'),
      // Παλιές καταγραφές (#81–#83): μόνο η σημείωση έδειχνε τη διακοπή από σύμπτωμα.
      stopped: j['stop'] == 1 || (note?.startsWith('Σταμάτησε: ') ?? false),
      cardioSec: optInt('csec'),
      gps: opt<bool>('gps'),
      activity: opt<String>('act'),
      splits: pairs(j['km']),
      pauses: pairs(j['pz']),
      hrrEnd: optInt('hrrE'),
      hrr1: optInt('hrr1'),
      limit: _limit(j['lim']),
      partial: j['part'] == 1,
      extra: extra,
    );
    s.hrBad = opt<String>('hrbad');
    s.hrSteady = optInt('hrs');
    // Οι παλμοί στο δικό τους αρχείο (V-A-02): δεν φορτώνονται τώρα.
    if (hr.isEmpty && hrf > 0) {
      s.hrLoaded = false;
      s.hrInFile = true;
      s.hrCount = hrf;
    }
    return s;
  }

  /// Όριο από αρχείο ή ρολόι: αριθμός ≥ 0· οτιδήποτε άλλο = δεν καταγράφηκε.
  static int? _limit(Object? v) => v is num && v >= 0 ? v.toInt() : null;

  /// Όριο που έστειλε το ρολόι (#90 και μετά), ή null για ρολόι παλιότερης έκδοσης.
  static int? watchLimit(Object? v) => _limit(v);
}
