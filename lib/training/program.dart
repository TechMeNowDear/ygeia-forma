/// Το πρόγραμμα προπόνησης: μέρες, προπονήσεις, ασκήσεις με στόχους. Το φτιάχνει ο Claude (επικόλληση)
/// ή ο ίδιος ο χρήστης (επεξεργαστής). Μορφή JSON, ίδια και για τα δύο.
library;

import 'dart:convert';

import 'equipment.dart';

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
  Cardio({this.activity = 'walk', this.minutes = 30, this.note});
  String activity;
  int minutes;
  String? note;

  static const names = {'walk': 'Περπάτημα', 'brisk': 'Γρήγορο περπάτημα', 'bike': 'Ποδήλατο', 'stairs': 'Σκάλες'};
  String get name => names[activity] ?? 'Αερόβια';

  Map<String, dynamic> toJson() => {'activity': activity, 'minutes': minutes, if (note != null) 'note': note};
  factory Cardio.fromJson(Map<String, dynamic> j) =>
      Cardio(activity: j['activity'] as String? ?? 'walk', minutes: (j['minutes'] as num?)?.toInt() ?? 30, note: j['note'] as String?);
}

class Workout {
  Workout({required this.id, required this.name, List<PlanItem>? items, this.cardio, this.note}) : items = items ?? [];
  String id, name;
  final List<PlanItem> items;
  Cardio? cardio;
  String? note;

  bool get isCardio => cardio != null;

  /// Περίπου πόσα λεπτά: σετ × (40″ δουλειά + διάλειμμα) + 2′ στήσιμο ανά άσκηση.
  int get minutes {
    if (cardio != null) return cardio!.minutes;
    var s = 0;
    for (final i in items) {
      s += i.sets * (40 + i.rest) + 120;
    }
    return (s / 60).round();
  }

  Workout copy() => Workout(id: id, name: name, items: [for (final i in items) i.copy()], cardio: cardio == null ? null : Cardio.fromJson(cardio!.toJson()), note: note);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (cardio != null) 'cardio': cardio!.toJson() else 'items': [for (final i in items) i.toJson()],
        if (note != null && note!.isNotEmpty) 'note': note,
      };

  factory Workout.fromJson(Map<String, dynamic> j) => Workout(
        id: j['id'] as String,
        name: j['name'] as String? ?? j['id'] as String,
        items: [for (final i in (j['items'] as List? ?? const [])) PlanItem.fromJson(i as Map<String, dynamic>)],
        cardio: j['cardio'] is Map ? Cardio.fromJson(j['cardio'] as Map<String, dynamic>) : null,
        note: j['note'] as String?,
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

  Workout? workout(String? id) {
    for (final w in workouts) {
      if (w.id == id) return w;
    }
    return null;
  }

  Workout? forDay(DateTime d) => workout(days[d.weekday]);

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
    final d = j['days'];
    if (d is Map) {
      d.forEach((k, v) {
        final n = int.tryParse('$k') ?? _dayKey('$k');
        if (n != null && n >= 1 && n <= 7 && v is String && v.isNotEmpty) days[n] = v;
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
    );
  }
}

String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Αγγλικά/ελληνικά ονόματα ημερών στο JSON («fri», «Πα»).
int? _dayKey(String k) {
  const m = {
    'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7,
    'δε': 1, 'τρ': 2, 'τε': 3, 'πε': 4, 'πα': 5, 'σα': 6, 'κυ': 7,
  };
  return m[k.toLowerCase().trim()];
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
    return PasteResult(null, ['Δεν βρέθηκε πρόγραμμα στο κείμενο. Αντέγραψε ολόκληρο το κομμάτι που ξεκινά με «{».'], const []);
  }
  Object? j;
  try {
    j = jsonDecode(text.substring(a, b + 1));
  } on FormatException {
    return PasteResult(null, ['Το πρόγραμμα αντιγράφηκε μισό ή αλλοιωμένο. Αντέγραψέ το ξανά ολόκληρο.'], const []);
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
  return PasteResult(p, validate(p, known), _warnings(p));
}

/// Λάθη που εμποδίζουν την αποθήκευση.
List<String> validate(Program p, Set<String> known) {
  final e = <String>[];
  if (p.workouts.isEmpty) e.add('Δεν έχει καμία προπόνηση.');
  final ids = <String>{};
  for (final w in p.workouts) {
    if (!ids.add(w.id)) e.add('Δύο προπονήσεις με το ίδιο όνομα «${w.id}».');
    if (!w.isCardio && w.items.isEmpty) e.add('Η «${w.name}» δεν έχει ασκήσεις.');
    for (final i in w.items) {
      if (!known.contains(i.ex)) e.add('Άγνωστη άσκηση «${i.ex}» στη «${w.name}».');
      if (i.next != null && !known.contains(i.next)) e.add('Άγνωστη παραλλαγή «${i.next}».');
      if (i.sets < 1 || i.sets > 10) e.add('${w.name}: τα σετ πρέπει να είναι 1–10.');
      if (i.lo < 1 || i.hi < i.lo || i.hi > 50) e.add('${w.name}: λάθος εύρος επαναλήψεων ${i.lo}–${i.hi}.');
      if (i.rest < 0 || i.rest > 600) e.add('${w.name}: το διάλειμμα πρέπει να είναι έως 10 λεπτά.');
    }
  }
  p.days.forEach((d, id) {
    if (p.workout(id) == null) e.add('Η ${weekdayLong[d]} δείχνει σε προπόνηση που δεν υπάρχει («$id»).');
  });
  return e;
}

/// Προσαρμογές που γίνονται αυτόματα, για ασφάλεια (λέγονται στον χρήστη).
List<String> _warnings(Program p) {
  final w = <String>[];
  for (final wo in p.workouts) {
    for (final i in wo.items) {
      // Ρεζέρβα τουλάχιστον 2 σε όλες τις ασκήσεις, ως να πει άλλα ο καρδιολόγος (έλεγχος #2).
      if (i.rir < 2) {
        i.rir = 2;
        w.add(i.kind == LoadKind.bar
            ? 'Μπάρα χωρίς βραχίονες ασφαλείας: η ρεζέρβα στο «${i.ex}» έγινε 2.'
            : 'Ρεζέρβα τουλάχιστον 2 (ως να πει άλλα ο γιατρός σου): στο «${i.ex}» έγινε 2.');
      }
      if (i.load != null && hasLoad(i.kind)) {
        final s = snap(i.kind, i.load!);
        if ((s - i.load!).abs() > 1e-6) {
          w.add('${loadLabel(i.kind, i.load)} δεν βγαίνει με τους δίσκους σου· μπήκε ${loadLabel(i.kind, s)}.');
          i.load = s;
        }
      }
    }
  }
  return w;
}
