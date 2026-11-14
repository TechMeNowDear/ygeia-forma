/// Το πρόγραμμα προπόνησης: μέρες, προπονήσεις, ασκήσεις με στόχους. Το φτιάχνει ο Claude (επικόλληση)
/// ή ο ίδιος ο χρήστης (επεξεργαστής). Μορφή JSON, ίδια και για τα δύο.
library;

import 'dart:convert';

import 'equipment.dart';
import 'set_hr.dart' show perSideExercises, sideSwitchSec;

/// Μία άσκηση μέσα σε προπόνηση.
class PlanItem {
  PlanItem({
    required this.ex,
    this.sets = 3,
    this.lo = 8,
    this.hi = 12,
    this.rir = 2,
    this.rest = 90,
    this.load,
    this.next,
    this.note,
  });

  /// Το id της άσκησης στη βιβλιοθήκη.
  String ex;
  int sets, lo, hi;

  /// Πόσες επαναλήψεις «ρεζέρβα» στόχος (0–4).
  int rir;

  /// Διάλειμμα μετά από κάθε σετ (δευτερόλεπτα).
  int rest;

  /// Αρχικό φορτίο (kg ή lb για λάστιχα). null = να το βρει η εφαρμογή (πρώτη φορά, ξεκίνα ελαφριά).
  double? load;

  /// Πιο δύσκολη παραλλαγή, όταν φτάσει στο ανώτατο (π.χ. κάμψεις πάγκου → κάμψεις με λαβές).
  String? next;
  String? note;

  LoadKind get kind => loadKindOf(ex);

  PlanItem copy() => PlanItem(ex: ex, sets: sets, lo: lo, hi: hi, rir: rir, rest: rest, load: load, next: next, note: note);

  Map<String, dynamic> toJson() => {
        'ex': ex,
        'sets': sets,
        'reps': [lo, hi],
        'rir': rir,
        'rest': rest,
        if (load != null) 'load': load,
        if (next != null) 'next': next,
        if (note != null && note!.isNotEmpty) 'note': note,
      };

  factory PlanItem.fromJson(Map<String, dynamic> j) {
    final reps = j['reps'];
    int lo = 8, hi = 12;
    if (reps is List && reps.length == 2) {
      lo = (reps[0] as num).toInt();
      hi = (reps[1] as num).toInt();
    } else if (reps is num) {
      lo = hi = reps.toInt();
    }
    return PlanItem(
      ex: j['ex'] as String,
      sets: (j['sets'] as num?)?.toInt() ?? 3,
      lo: lo,
      hi: hi,
      rir: (j['rir'] as num?)?.toInt() ?? 2,
      rest: (j['rest'] as num?)?.toInt() ?? 90,
      load: (j['load'] as num?)?.toDouble(),
      next: j['next'] as String?,
      note: j['note'] as String?,
    );
  }
}

/// Αερόβια (περπάτημα κ.λπ.).
class Cardio {
  Cardio({this.activity = 'walk', this.minutes = 30, this.note, List<int>? plan}) : plan = plan ?? [];
  String activity;
  int minutes;
  String? note;

  /// Πλάνο περπατήματος (13/11): τα λεπτά ανά εβδομάδα του προγράμματος (η 1η εβδομάδα πρώτη), από την ημερομηνία
  /// έναρξης ([Program.from]). Μετά την τελευταία εβδομάδα μένει η τελευταία τιμή. Άδειο = πάντα [minutes].
  List<int> plan;

  /// Τα λεπτά την εβδομάδα [week] (0 = η πρώτη).
  int minutesInWeek(int week) => plan.isEmpty ? minutes : plan[week < 0 ? 0 : (week >= plan.length ? plan.length - 1 : week)];

  /// «εβδομάδα 2 από 4», όσο το πλάνο τρέχει· null χωρίς πλάνο ή μετά το τέλος του.
  String? planWeekText(int week) => plan.isEmpty || week < 0 || week >= plan.length ? null : 'εβδομάδα ${week + 1} από ${plan.length}';

  static const names = {'walk': 'Περπάτημα', 'brisk': 'Γρήγορο περπάτημα', 'bike': 'Ποδήλατο', 'stairs': 'Σκάλες'};
  String get name => names[activity] ?? 'Αερόβια';

  Map<String, dynamic> toJson() => {'activity': activity, 'minutes': minutes, if (note != null) 'note': note, if (plan.isNotEmpty) 'plan': plan};
  factory Cardio.fromJson(Map<String, dynamic> j) => Cardio(
        activity: j['activity'] as String? ?? 'walk',
        minutes: (j['minutes'] as num?)?.toInt() ?? 30,
        note: j['note'] as String?,
        plan: [
          if (j['plan'] is List)
            for (final v in j['plan'] as List)
              if (v is num && v.isFinite) v.toInt(),
        ],
      );
}

/// Ζέσταμα και αποθεραπεία (13/11): ως [routineMaxSteps] σύντομα βήματα, ως [routineMaxChars] χαρακτήρες το καθένα.
const routineMaxSteps = 10, routineMaxChars = 160;
const planMaxWeeks = 12;

List<String> _steps(Object? j) => [
      if (j is List)
        for (final s in j)
          if (s is String && s.trim().isNotEmpty) s.trim(),
    ];

class Workout {
  Workout({required this.id, required this.name, List<PlanItem>? items, this.cardio, this.note, List<String>? warmup, List<String>? cooldown})
      : items = items ?? [],
        warmup = warmup ?? [],
        cooldown = cooldown ?? [];
  String id, name;
  final List<PlanItem> items;
  Cardio? cardio;
  String? note;

  /// Ζέσταμα πριν και αποθεραπεία μετά (13/11): σύντομα βήματα, με τη σειρά που γίνονται. Άδειο = δεν φαίνεται τίποτα.
  final List<String> warmup, cooldown;

  bool get isCardio => cardio != null;

  /// Περίπου πόσα λεπτά: σετ × (40″ δουλειά + διάλειμμα) + 2′ στήσιμο ανά άσκηση. R7-A6-7: στις ασκήσεις μίας πλευράς
  /// τη φορά ([perSideExercises]) κάθε σετ είναι δεξιά και αριστερά: 2 × 40″ και η αλλαγή πλευράς.
  int get minutes {
    if (cardio != null) return cardio!.minutes;
    var s = 0.0;
    for (final i in items) {
      final work = perSideExercises.contains(i.ex) ? 2 * 40 + sideSwitchSec : 40.0;
      s += i.sets * (work + i.rest) + 120;
    }
    return (s / 60).round();
  }

  Workout copy() => Workout(
        id: id,
        name: name,
        items: [for (final i in items) i.copy()],
        cardio: cardio == null ? null : Cardio.fromJson(cardio!.toJson()),
        note: note,
        warmup: [...warmup],
        cooldown: [...cooldown],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (cardio != null) 'cardio': cardio!.toJson() else 'items': [for (final i in items) i.toJson()],
        if (note != null && note!.isNotEmpty) 'note': note,
        if (warmup.isNotEmpty) 'warmup': warmup,
        if (cooldown.isNotEmpty) 'cooldown': cooldown,
      };

  factory Workout.fromJson(Map<String, dynamic> j) => Workout(
        id: j['id'] as String,
        name: j['name'] as String? ?? j['id'] as String,
        items: [for (final i in (j['items'] as List? ?? const [])) PlanItem.fromJson(i as Map<String, dynamic>)],
        cardio: j['cardio'] is Map ? Cardio.fromJson(j['cardio'] as Map<String, dynamic>) : null,
        note: j['note'] as String?,
        warmup: _steps(j['warmup']),
        cooldown: _steps(j['cooldown']),
      );
}

/// Ημέρες της εβδομάδας (1 = Δευτέρα ... 7 = Κυριακή, όπως το DateTime.weekday).
const dayShort = {1: 'Δε', 2: 'Τρ', 3: 'Τε', 4: 'Πε', 5: 'Πα', 6: 'Σα', 7: 'Κυ'};
const weekdayLong = {1: 'Δευτέρα', 2: 'Τρίτη', 3: 'Τετάρτη', 4: 'Πέμπτη', 5: 'Παρασκευή', 6: 'Σάββατο', 7: 'Κυριακή'};

class Program {
  Program({
    required this.id,
    required this.name,
    Map<int, String>? days,
    List<Workout>? workouts,
    this.from,
    this.note,
    this.author = 'user',
    this.version = 1,
    this.savedAt,
  })  : days = days ?? {},
        workouts = workouts ?? [];

  String id, name;

  /// Μέρα (1–7) → id προπόνησης. Χωρίς τιμή = ξεκούραση.
  final Map<int, String> days;
  final List<Workout> workouts;
  DateTime? from;
  String? note;

  /// «claude» ή «user».
  String author;
  int version;
  DateTime? savedAt;

  /// Κλειδιά του «days» που δεν είναι μέρα (round1, S6-6), όπως γράφτηκαν: για το μήνυμα της επικόλλησης. Πριν, μια
  /// μέρα με άγνωστο όνομα γινόταν σιωπηλά «ξεκούραση». Δεν αποθηκεύονται.
  List<String> badDays = const [];

  Workout? workout(String? id) {
    for (final w in workouts) {
      if (w.id == id) return w;
    }
    return null;
  }

  /// Η εβδομάδα του προγράμματος τη μέρα [d] (0 = η πρώτη). Χωρίς ημερομηνία έναρξης, ή πριν από αυτήν: 0.
  int weekOf(DateTime d) {
    final f = from;
    if (f == null) return 0;
    final n = DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(f.year, f.month, f.day)).inDays;
    return n < 0 ? 0 : n ~/ 7;
  }

  /// Η προπόνηση [w] όπως ισχύει τη μέρα [d]: στην αερόβια με πλάνο, αντίγραφο με τα λεπτά της εβδομάδας. Αλλιώς η ίδια.
  Workout at(Workout w, DateTime d) {
    final c = w.cardio;
    if (c == null || c.plan.isEmpty) return w;
    return w.copy()..cardio!.minutes = c.minutesInWeek(weekOf(d));
  }

  /// R7-A6-6: η μέρα [d] είναι πριν από την έναρξη του προγράμματος ([from]): καμία προπόνηση του προγράμματος ακόμα.
  bool notStarted(DateTime d) {
    final f = from;
    return f != null && DateTime(d.year, d.month, d.day).isBefore(DateTime(f.year, f.month, f.day));
  }

  /// «εβδομάδα 2 από 4» της αερόβιας [c] τη μέρα [d]· null πριν από την έναρξη ([notStarted]) ή χωρίς πλάνο.
  String? planWeekText(Cardio c, DateTime d) => notStarted(d) ? null : c.planWeekText(weekOf(d));

  /// Η προπόνηση της μέρας [d], ή null (ξεκούραση, ή πριν από την έναρξη του προγράμματος, R7-A6-6: πριν, το «ισχύει
  /// από Δευ 16/11» φαινόταν αλλά το Σάββατο 14/11 η Σήμερα έδειχνε ήδη «Κάτω μέρος 2»).
  Workout? forDay(DateTime d) {
    if (notStarted(d)) return null;
    final w = workout(days[d.weekday]);
    return w == null ? null : at(w, d);
  }

  Program copy() => Program.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'kind': 'ygeia-program',
        'v': 1,
        'id': id,
        'name': name,
        'author': author,
        'version': version,
        if (from != null) 'from': _day(from!),
        if (savedAt != null) 'savedAt': savedAt!.millisecondsSinceEpoch,
        if (note != null && note!.isNotEmpty) 'note': note,
        'days': {for (final e in days.entries) '${e.key}': e.value},
        'workouts': [for (final w in workouts) w.toJson()],
      };

  factory Program.fromJson(Map<String, dynamic> j) {
    final days = <int, String>{};
    final bad = <String>[];
    final d = j['days'];
    if (d is Map) {
      d.forEach((k, v) {
        final n = int.tryParse('$k') ?? _dayKey('$k');
        if (n == null || n < 1 || n > 7) {
          bad.add('$k');
        } else if (v is String && v.isNotEmpty) {
          days[n] = v;
        }
      });
    }
    return Program(
      id: j['id'] as String? ?? 'p${DateTime.now().millisecondsSinceEpoch}',
      name: j['name'] as String? ?? 'Πρόγραμμα',
      days: days,
      workouts: [for (final w in (j['workouts'] as List? ?? const [])) Workout.fromJson(w as Map<String, dynamic>)],
      from: j['from'] is String ? DateTime.tryParse(j['from'] as String) : null,
      note: j['note'] as String?,
      author: j['author'] as String? ?? 'user',
      version: (j['version'] as num?)?.toInt() ?? 1,
      savedAt: j['savedAt'] is num ? DateTime.fromMillisecondsSinceEpoch((j['savedAt'] as num).toInt()) : null,
    )..badDays = bad;
  }
}

String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Αγγλικά/ελληνικά ονόματα ημερών στο JSON: «fri», «Friday», «Fri.», «Πα», «Παρ», «Παρασκευή» (round1, S6-6: και τα
/// ολόκληρα ονόματα, πεζά ή κεφαλαία, με ή χωρίς τόνο· πριν μόνο οι συντομογραφίες).
int? _dayKey(String k) {
  const m = {
    'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7,
    'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4, 'friday': 5, 'saturday': 6, 'sunday': 7,
    'tues': 2, 'thur': 4, 'thurs': 4,
    'δε': 1, 'τρ': 2, 'τε': 3, 'πε': 4, 'πα': 5, 'σα': 6, 'κυ': 7,
    'δευ': 1, 'τρι': 2, 'τετ': 3, 'πεμ': 4, 'παρ': 5, 'σαβ': 6, 'κυρ': 7,
    'δευτερα': 1, 'τριτη': 2, 'τεταρτη': 3, 'πεμπτη': 4, 'παρασκευη': 5, 'σαββατο': 6, 'κυριακη': 7,
  };
  const plain = {'ά': 'α', 'έ': 'ε', 'ή': 'η', 'ί': 'ι', 'ό': 'ο', 'ύ': 'υ', 'ώ': 'ω'};
  var s = k.toLowerCase().trim();
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(plain[ch] ?? ch);
  }
  return m[b.toString()];
}

/// Αποτέλεσμα επικόλλησης: το πρόγραμμα ή τι φταίει (απλά ελληνικά).
class PasteResult {
  PasteResult(this.program, this.errors, this.warnings);
  final Program? program;
  final List<String> errors;
  final List<String> warnings;
  bool get ok => program != null && errors.isEmpty;
}

/// Διαβάζει κείμενο που επικολλήθηκε (μπορεί να έχει γύρω του κείμενο ή ```json).
/// [known]: τα ids της βιβλιοθήκης, [names]: id → όνομα (για τα μηνύματα).
PasteResult parseProgram(String text, Set<String> known) {
  final a = text.indexOf('{'), b = text.lastIndexOf('}');
  if (a < 0 || b <= a) {
    return PasteResult(null, ['Δεν βρέθηκε πρόγραμμα στο κείμενο. Αντίγραψε ολόκληρο το κομμάτι που ξεκινά με «{».'], const []);
  }
  Object? j = programJsonIn(text);
  if (j == null) {
    try {
      j = jsonDecode(text.substring(a, b + 1));
    } on FormatException {
      return PasteResult(null, ['Το πρόγραμμα αντιγράφηκε μισό ή αλλοιωμένο. Αντίγραψέ το ξανά ολόκληρο.'], const []);
    }
  }
  if (j is! Map<String, dynamic> || j['kind'] != 'ygeia-program') {
    return PasteResult(null, ['Το κείμενο δεν είναι πρόγραμμα της εφαρμογής.'], const []);
  }
  final Program p;
  try {
    p = Program.fromJson(j);
  } catch (_) {
    return PasteResult(null, ['Το πρόγραμμα έχει λάθος μορφή. Ζήτα από τον Claude να το ξαναβγάλει.'], const []);
  }
  return PasteResult(p, [..._rawProblems(j), ...validate(p, known)], _warnings(p));
}

/// R7-A6-5: το JSON του προγράμματος μέσα σε όλο το μήνυμα, και όταν το κείμενο γύρω του έχει κι αυτό «{» ή «}» (π.χ.
/// «από το πρώτο `{` ως το τελευταίο `}`»). Πρώτα το περιεχόμενο ενός ```json … ```, μετά κάθε «{» από αριστερά ως το
/// «}» που το κλείνει (με τα εισαγωγικά των κειμένων): το πρώτο που διαβάζεται ως πρόγραμμα («kind»: «ygeia-program»).
/// null αν δεν βρεθεί (τότε ισχύει ο παλιός κανόνας, για το σωστό μήνυμα λάθους).
Map<String, dynamic>? programJsonIn(String text) {
  Map<String, dynamic>? tryDecode(String t) {
    try {
      final j = jsonDecode(t);
      return j is Map<String, dynamic> && j['kind'] == 'ygeia-program' ? j : null;
    } on FormatException {
      return null;
    }
  }

  final fence = RegExp(r'```(?:json)?\s*\n([\s\S]*?)```').allMatches(text);
  for (final m in fence) {
    final j = tryDecode(m.group(1)!.trim());
    if (j != null) return j;
  }
  for (var a = text.indexOf('{'); a >= 0; a = text.indexOf('{', a + 1)) {
    var depth = 0;
    var inStr = false, esc = false;
    for (var i = a; i < text.length; i++) {
      final ch = text[i];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (ch == r'\') {
          esc = true;
        } else if (ch == '"') {
          inStr = false;
        }
        continue;
      }
      if (ch == '"') {
        inStr = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          final j = tryDecode(text.substring(a, i + 1));
          if (j != null) return j;
          break;
        }
      }
    }
  }
  return null;
}

/// Ό,τι το [Program.fromJson] διαβάζει με ανοχή (για τα αποθηκευμένα προγράμματα), αλλά σε πρόγραμμα που επικολλάς είναι
/// λάθος και πρέπει να λέγεται (round1, S6-6): «reps» που δεν είναι [από, ως] ή ένας αριθμός (π.χ. "10-15" ή
/// [10, 12, 15]) γινόταν σιωπηλά 8–12.
List<String> _rawProblems(Map<String, dynamic> j) {
  final e = <String>[];
  final ws = j['workouts'];
  if (ws is! List) return e;
  for (final w in ws) {
    if (w is! Map) continue;
    final items = w['items'];
    if (items is! List) continue;
    for (final i in items) {
      if (i is! Map) continue;
      final r = i['reps'];
      if (r == null || r is num || (r is List && r.length == 2 && r[0] is num && r[1] is num)) continue;
      e.add('${w['name'] ?? w['id']}: οι επαναλήψεις στο «${i['ex']}» γράφονται [από, ως], π.χ. [8, 12].');
    }
  }
  return e;
}

/// Τα λεπτά μιας αερόβιας προπόνησης σε πρόγραμμα που επικολλάς: από 1 ως 600 (απόφαση 12/11, Συμβούλιο 3, Β4).
const cardioMinMinutes = 1, cardioMaxMinutes = 600;

/// Το «+» και το «−» στα λεπτά αερόβιας του επεξεργαστή προγράμματος: βήμα 5′. null = το κουμπί είναι σβηστό.
/// Το «+» φτάνει ως το όριο της επικόλλησης (απόφαση 12/11, Συμβούλιο 4): πριν σταματούσε στα 180′, και από ένα πρόγραμμα
/// με 240′ που είχες επικολλήσει, ένα «−» δεν γύριζε πίσω. Το «−» μένει όπως ήταν (ως τα 5′).
int? cardioMinutesPlus(int minutes) =>
    minutes < cardioMaxMinutes ? (minutes + 5 > cardioMaxMinutes ? cardioMaxMinutes : minutes + 5) : null;
int? cardioMinutesMinus(int minutes) => minutes > 5 ? minutes - 5 : null;

/// Λάθη που εμποδίζουν την αποθήκευση.
List<String> validate(Program p, Set<String> known) {
  final e = <String>[];
  if (p.workouts.isEmpty) e.add('Δεν έχει καμία προπόνηση.');
  final ids = <String>{};
  for (final w in p.workouts) {
    if (!ids.add(w.id)) e.add('Δύο προπονήσεις με το ίδιο όνομα «${w.id}».');
    if (!w.isCardio && w.items.isEmpty) e.add('Η «${w.name}» δεν έχει ασκήσεις.');
    // Πριν δεν ελέγχονταν καθόλου: −5 ή 100.000 λεπτά περνούσαν ως την κάρτα της Σήμερα και το ρολόι.
    if (w.cardio != null && (w.cardio!.minutes < cardioMinMinutes || w.cardio!.minutes > cardioMaxMinutes)) {
      e.add('${w.name}: τα λεπτά της αερόβιας πρέπει να είναι από $cardioMinMinutes ως $cardioMaxMinutes.');
    }
    // 13/11: πλάνο περπατήματος ανά εβδομάδα, ζέσταμα και αποθεραπεία.
    final plan = w.cardio?.plan ?? const <int>[];
    if (plan.length > planMaxWeeks || plan.any((m) => m < cardioMinMinutes || m > cardioMaxMinutes)) {
      e.add('${w.name}: το πλάνο θέλει ως $planMaxWeeks εβδομάδες, με $cardioMinMinutes ως $cardioMaxMinutes λεπτά η καθεμία.');
    }
    if (plan.isNotEmpty && p.from == null) e.add('${w.name}: το πλάνο ανά εβδομάδα θέλει ημερομηνία έναρξης του προγράμματος.');
    for (final (label, steps) in [('το ζέσταμα', w.warmup), ('η αποθεραπεία', w.cooldown)]) {
      if (steps.length > routineMaxSteps || steps.any((s) => s.length > routineMaxChars)) {
        e.add('${w.name}: $label θέλει ως $routineMaxSteps βήματα, ως $routineMaxChars γράμματα το καθένα.');
      }
    }
    for (final i in w.items) {
      if (!known.contains(i.ex)) e.add('Άγνωστη άσκηση «${i.ex}» στη «${w.name}».');
      if (i.next != null && !known.contains(i.next)) e.add('Άγνωστη παραλλαγή «${i.next}».');
      if (i.sets < 1 || i.sets > 10) e.add('${w.name}: τα σετ πρέπει να είναι 1–10.');
      if (i.lo < 1 || i.hi < i.lo || i.hi > 50) e.add('${w.name}: λάθος εύρος επαναλήψεων ${i.lo}–${i.hi}.');
      if (i.rest < 0 || i.rest > 600) e.add('${w.name}: το διάλειμμα πρέπει να είναι έως 10 λεπτά.');
      // round1, S6-6: η ερώτηση της ρεζέρβας φτάνει ως «4+»· με στόχο πάνω από 4 το βάρος δεν θα ανέβαινε ποτέ.
      if (i.rir > 4) e.add('${w.name}: το «άφησε» (πόσες επαναλήψεις να περισσεύουν) πρέπει να είναι από 2 ως 4.');
      // Βάρος που δεν είναι αριθμός (π.χ. 1e999 = «άπειρο»): πριν περνούσε, και μετά η αποθήκευση δεν έκανε τίποτα.
      final load = i.load;
      if (load != null && !load.isFinite) e.add('${w.name}: το βάρος στο «${i.ex}» δεν είναι σωστός αριθμός.');
      // R7-A6-10: αρνητικό βάρος δεν «στρογγυλεύεται» σε κάτι που βγαίνει· είναι λάθος.
      if (load != null && load.isFinite && load < 0) e.add('${w.name}: το βάρος στο «${i.ex}» δεν μπορεί να είναι αρνητικό.');
    }
  }
  p.days.forEach((d, id) {
    if (p.workout(id) == null) e.add('Η ${weekdayLong[d]} δείχνει σε προπόνηση που δεν υπάρχει («$id»).');
  });
  // round1, S6-6: μέρα με άγνωστο όνομα δεν γίνεται σιωπηλά «ξεκούραση».
  for (final k in p.badDays) {
    e.add('Δεν κατάλαβα τη μέρα «$k». Γράψε mon, tue, wed, thu, fri, sat, sun ή 1–7.');
  }
  return e;
}

/// Προσαρμογές που γίνονται αυτόματα, για ασφάλεια (λέγονται στον χρήστη).
List<String> _warnings(Program p) {
  final w = <String>[];
  for (final wo in p.workouts) {
    for (final i in wo.items) {
      // Ρεζέρβα τουλάχιστον 2 σε όλες τις ασκήσεις, ως να πει άλλα ο γιατρός (έλεγχος #2).
      if (i.rir < 2) {
        i.rir = 2;
        w.add(i.kind == LoadKind.bar
            ? 'Μπάρα χωρίς βραχίονες ασφαλείας: στο «${i.ex}» το «άφησε» έγινε 2.'
            : 'Ρεζέρβα τουλάχιστον 2 (ως να πει άλλα ο γιατρός σου): στο «${i.ex}» έγινε 2.');
      }
      if (i.load != null && i.load!.isFinite && i.load! >= 0 && hasLoad(i.kind)) {
        final s = snap(i.kind, i.load!);
        if ((s - i.load!).abs() > 1e-6) {
          // R7-A6-10: με τις λέξεις του εξοπλισμού (λάστιχα, kettlebell), όχι «δίσκοι» για όλα.
          final k = i.kind;
          final what = switch (k) {
            LoadKind.band || LoadKind.bandPair || LoadKind.bandAssist => '${loadLabel(k, i.load)} δεν βγαίνει με τα λάστιχά σου',
            LoadKind.kb => 'Δεν υπάρχει kettlebell ${kgText(i.load!)} kg',
            _ => '${loadLabel(k, i.load)} δεν βγαίνει με τους δίσκους σου',
          };
          w.add('$what· στο «${i.ex}» μπήκε ${loadLabel(k, s)}.');
          i.load = s;
        }
      }
    }
  }
  return w;
}
