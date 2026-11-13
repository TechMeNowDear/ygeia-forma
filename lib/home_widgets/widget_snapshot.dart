import '../body_trend.dart' show shownBody;
import '../data.dart';
import '../food/food_model.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../history.dart';
import '../reference.dart';
import '../shown.dart';
import '../sources.dart';
import '../training/training_store.dart';
import 'widget_style.dart';

// Το στιγμιότυπο που ζωγραφίζουν τα widgets: έτοιμα κείμενα, ένα ανά τιμή, ΜΕ ΤΟΥΣ ΙΔΙΟΥΣ κανόνες με τις οθόνες
// (σχέδιο πηγών, «συνήθως», εύρη). Η Kotlin δεν υπολογίζει τίποτα δικό της, εκτός από τα βήματα και την κίνηση της
// μέρας, που τα ανανεώνει από την ανάγνωση στο παρασκήνιο (HomeWidgets.kt).
//
// Μορφή: {v, at, kinds: {sleep: {src, srcShort?, m: {κλειδί: {l, v, u, cap?, d?, us?, r?, s?}}}}}
//   srcShort: σύντομη πηγή όταν η κανονική δεν χωρά (round 2, R2-U3-04).
//   l: όνομα στο κουτάκι, v: τιμή, u: μονάδα, cap: δεύτερη γραμμή όταν είναι η κεντρική τιμή,
//   d: −1/0/1 σε σχέση με τα συνηθισμένα, us: «συνήθως …», r: θέση στο εύρος, s: 7 τιμές για το γράφημα (null = κενό).

const widgetSnapshotVersion = 1;

Map<String, dynamic> buildWidgetSnapshot(HealthStore store, FoodStore food, DateTime now, {TrainingStore? training}) {
  final today = dayOf(now);
  return {
    'v': widgetSnapshotVersion,
    'at': now.millisecondsSinceEpoch,
    'kinds': {
      WKind.sleep: _sleep(store, today),
      WKind.move: _move(store, today),
      WKind.food: _food(food, today),
      WKind.body: _body(store, today),
    },
    // 13/11: το widget «Προπόνηση σήμερα» (QuickWidgetRules.kt). Νέο κλειδί· τα υπόλοιπα widgets δεν το διαβάζουν.
    if (training != null && training.ready) 'workout': workoutSnapshot(training, today),
  };
}

/// Το widget «Προπόνηση σήμερα» (13/11): ΟΛΗ η εβδομάδα του προγράμματος με έτοιμα κείμενα (1 = Δευτέρα … 7 = Κυριακή,
/// μόνο οι μέρες με προπόνηση), ώστε το widget να αλλάζει μόνο του στα μεσάνυχτα χωρίς να ξυπνήσει η εφαρμογή. Ίδιοι
/// κανόνες με την κάρτα «Άσκηση σήμερα» (today_training_card.dart): η μέρα του προγράμματος, και «έγινε» όταν υπάρχει
/// προπόνηση που ξεκίνησε σήμερα και τελείωσε.
Map<String, dynamic> workoutSnapshot(TrainingStore t, DateTime today) {
  final p = t.program;
  final done = t.sessions.reversed.where((s) => s.finished && sameDay(s.start, today)).firstOrNull;
  return {
    'has': p != null,
    'week': {
      if (p != null)
        for (var d = 1; d <= 7; d++)
          // Η επόμενη μέρα με αυτό το όνομα (σήμερα μαζί), ώστε το πλάνο περπατήματος να δίνει τα λεπτά της δικής της εβδομάδας.
          if (p.forDay(DateTime(today.year, today.month, today.day + (d - today.weekday) % 7)) case final w?)
            '$d': {
              't': w.cardio?.name ?? w.name,
              // Round 1 (U7-13): διάρκειες με ολόκληρες λέξεις (πριν «περίπου 50′»).
              's': w.cardio != null
                  ? hoursMinutes(w.cardio!.minutes)
                  : '${countText(w.items.length, 'άσκηση', 'ασκήσεις')} · περίπου ${hoursMinutes(w.minutes)}',
            },
    },
    if (done != null) 'done': dateKey(today),
    if (done != null) 'doneText': '${done.name} · ${hoursMinutes(done.end!.difference(done.start).inMinutes)}',
  };
}

Map<String, dynamic> _entry(String label, String value, String unit,
        {String? cap, int? d, String? usual, String? range, List<double?>? spark}) =>
    {
      'l': label,
      'v': value,
      'u': unit,
      if (cap != null) 'cap': cap,
      if (d != null) 'd': d,
      if (usual != null) 'us': usual,
      if (range != null) 'r': range,
      if (spark != null && spark.any((x) => x != null)) 's': spark,
    };

DateTime _minus(DateTime d, int n) => DateTime(d.year, d.month, d.day - n);

/// Ύπνος: η τελευταία νύχτα (σήμερα ή χθες), από την πηγή που ορίζει το σχέδιο.
Map<String, dynamic> _sleep(HealthStore store, DateTime today) {
  final h = store.history, plan = store.plan;
  DateTime? day;
  for (var i = 0; i < 2 && day == null; i++) {
    if (plan.value(h, K.sleepMin, _minus(today, i)) != null) day = _minus(today, i);
  }
  final out = <String, dynamic>{};
  // Round 1 (U7-16): χωρίς νύχτα τις δύο τελευταίες μέρες το widget το λέει (πριν: σκέτο «—» χωρίς εξήγηση).
  // Round 2 (R2-U3-04): και σύντομη μορφή («srcShort», νέο προαιρετικό κλειδί) για τη στήλη 1×3, όπου η κανονική κοβόταν
  // «καμία πρόσφατη…» και χανόταν ακριβώς η λέξη «νύχτα».
  if (day == null) return {'src': 'καμία πρόσφατη νύχτα', 'srcShort': 'καμία νύχτα', 'm': out};
  final d0 = day;
  final src = plan.nightSource(d0);
  List<double?> series(String k) => [for (var i = 6; i >= 0; i--) plan.value(h, k, _minus(d0, i))];

  void add(String key, String label, String unit, String Function(double v) show,
      {int digits = 0, String? cap, String? range, bool unitInUsual = true}) {
    final v = plan.value(h, key, d0);
    if (v == null) return;
    final b = personalBaseline(h, plan, key, d0);
    int? dir;
    String? usual;
    if (b?.usual != null) {
      final diff = shownDiff(b!.value, b.usual!, digits);
      dir = diff == 0 ? 0 : (diff > 0 ? 1 : -1);
      usual = 'συνήθως ${show(b.usual!)}${unit.isEmpty || !unitInUsual ? '' : unit}';
    }
    out[key] = _entry(label, show(v), unit, cap: cap, d: dir, usual: usual, range: range, spark: series(key));
  }

  final bed = plan.value(h, K.bedtime, d0), wake = plan.value(h, K.wake, d0);
  final sr = sleepRange(store.profile, today);
  // Έλεγχος 9/11 (04-M5 / V-B-15): η κρίση «κάτω/μέσα στο εύρος» από τον μέσο όρο 7 νυχτών (τουλάχιστον 4 με τιμή),
  // όχι από μία νύχτα· η τιμή της νύχτας μένει η μεγάλη τιμή.
  // Το κείμενο λέει πόσες νύχτες μέτρησαν (4–7), όχι πάντα «7».
  (double, int)? week(String key) {
    final vs = [for (var i = 0; i < 7; i++) plan.value(h, key, _minus(d0, i))].whereType<double>().toList();
    return vs.length < 4 ? null : (vs.reduce((a, b) => a + b) / vs.length, vs.length);
  }

  final sleepWeek = week(K.sleepMin), breathWeek = week(K.breath);
  // Στρογγύλεμα πρώτα (έλεγχος 8/11, DATA-03): 419,5 λεπτά → 7:00, όχι 6:00.
  // Round 1 (U7-13): «7:16 ώρες» (η μονάδα ως λέξη· στο «συνήθως» χωρίς αυτήν, για να χωρά η γραμμή).
  add(K.sleepMin, 'Ύπνος', ' ώρες', (v) => '${v.round() ~/ 60}:${two(v.round() % 60)}', unitInUsual: false,
      cap: bed != null && wake != null ? '${clockFromSix(bed)}–${clockFromSix(wake)}' : shortDayDate(d0),
      range: sleepWeek != null && sr != null ? '${countText(sleepWeek.$2, 'νύχτα', 'νύχτες')} ${sr.placeText(sleepWeek.$1)}' : null);
  add(K.energy, 'Ετοιμότητα', '', (v) => '${v.round()}');
  add(K.sleepScore, 'Σκορ', '', (v) => '${v.round()}');
  add(K.hrv, 'HRV', ' ms', (v) => '${v.round()}');
  add(K.sleepHr, 'Παλμοί', ' bpm', (v) => '${v.round()}');
  add(K.lowHr, 'Χαμηλότεροι', ' bpm', (v) => '${v.round()}');
  add(K.ringSpo2, 'Οξυγόνο', '%', spo2AvgText, digits: 1);
  add(K.breath, 'Αναπνοές', '', (v) => dec(v), digits: 1,
      range: breathWeek == null ? null : '${countText(breathWeek.$2, 'νύχτα', 'νύχτες')} ${breathRange.placeText(breathWeek.$1)}');
  // Θερμοκρασία: το Oura δίνει απόκλιση (+0,3°), το ρολόι απόλυτη τιμή καρπού (33,6 °C), που δεν δείχνεται ποτέ ως
  // «+33,6°» (έλεγχος 8/11, DATA-04). Από το ρολόι: μόνο η απόκλιση από τα συνηθισμένα, αν υπάρχουν.
  if (src == Source.oura) {
    add(K.skinTemp, 'Θερμοκρασία', '°', (v) => signedDec(v), digits: 1);
  } else {
    final v = plan.value(h, K.skinTemp, d0);
    final b = personalBaseline(h, plan, K.skinTemp, d0);
    if (v != null && b?.usual != null) {
      final diff = shownDiff(v, b!.usual!, 1);
      out[K.skinTemp] = _entry('Θερμοκρασία', signedDec(diff), '°', cap: 'απόκλιση καρπού');
    }
  }
  return {'src': '${src == Source.oura ? 'Oura' : 'ρολόι'} · ${shortDayDate(d0)}', 'm': out};
}

/// Κίνηση: η σημερινή μέρα ως τώρα (δεν συγκρίνεται με τα συνηθισμένα: δεν έχει τελειώσει).
Map<String, dynamic> _move(HealthStore store, DateTime today) {
  final d = store.data;
  final out = <String, dynamic>{};
  if (d == null) return {'m': out};
  final a = d.activity;
  double? n(String k) => (a[k] as num?)?.toDouble();
  final steps = d.todaySteps;
  final yest = d.valueFor(d.steps, _minus(today, 1))?.value;
  final stepSeries = [for (var i = 6; i >= 0; i--) d.valueFor(d.steps, _minus(today, i))?.value];
  final sr = stepsRange(store.profile, today);
  if (steps != null) {
    out['steps'] = _entry('Βήματα', thousands(steps.round()), '',
        cap: yest == null ? 'βήματα σήμερα' : 'χθες ${thousands(yest.round())}',
        range: yest != null && sr != null ? 'χθες ${sr.placeText(yest)}' : null,
        spark: stepSeries);
  }
  if (n('activeCalories') case final v?) out['activeKcal'] = _entry('Ενεργές', thousands(v.round()), ' kcal');
  if (n('calories') case final v?) out['totalKcal'] = _entry('Σύνολο', thousands(v.round()), ' kcal');
  if (n('activeMinutes') case final v?) out['activeMin'] = _entry('Ενεργός', '${v.round()}', ' λεπτά');
  if (d.valueFor(d.floors, today)?.value case final v?) out['floors'] = _entry('Όροφοι', '${v.round()}', '');
  if (n('distance') case final v?) out['distance'] = _entry('Απόσταση', dec(v / 1000), ' km');
  final dayHr = store.plan.value(store.history, K.dayHr, _minus(today, 1));
  if (dayHr != null) out['dayHr'] = _entry('Παλμοί χθες', '${dayHr.round()}', ' bpm');
  // 'day': η μέρα των τιμών· άλλη μέρα στο widget = «—» (έλεγχος 8/11, DATA-02, HomeWidgets.forToday).
  // Έλεγχος 9/11 (D2-05c): η μέρα της ΑΝΑΓΝΩΣΗΣ, όχι η σημερινή: τιμές χθεσινής ανάγνωσης (π.χ. άνοιγμα στις 00:05
  // με παλιά μνήμη) δεν φαίνονται σαν σημερινές.
  return {'src': 'ρολόι · ${hm(d.readAt)}', 'at': d.readAt.millisecondsSinceEpoch, 'day': dateKey(dayOf(d.readAt)), 'm': out};
}

/// Φαγητό: τα σύνολα της σημερινής μέρας, μόνο από τη βάση τροφίμων.
Map<String, dynamic> _food(FoodStore food, DateTime today) {
  final entries = food.entriesFor(today);
  final t = Totals(entries);
  final meals = {for (final e in entries) e.meal}.length;
  final series = [for (var i = 6; i >= 0; i--) _kcalOf(food, _minus(today, i))];
  String g(double v) => gramsText(v);
  final out = <String, dynamic>{
    'kcal': _entry('Θερμίδες', kcalText(t.kcal), ' kcal',
        cap: entries.isEmpty ? 'τίποτα ακόμα σήμερα' : (meals == 1 ? '1 γεύμα σήμερα' : '$meals γεύματα σήμερα'),
        spark: series),
    'protein': _entry('Πρωτεΐνη', g(t.protein), ' g'),
    'carbs': _entry('Υδατάνθρακες', g(t.carbs), ' g'),
    'fat': _entry('Λιπαρά', g(t.fat), ' g'),
    'fiber': _entry('Ίνες', g(t.fiber), ' g'),
    'salt': _entry('Αλάτι', dec(t.salt), ' g'),
    'sugars': _entry('Σάκχαρα', g(t.sugars), ' g'),
  };
  return {
    'day': dateKey(today),
    'src': entries.isEmpty ? 'σήμερα' : (meals == 1 ? '1 γεύμα' : '$meals γεύματα'),
    'bar': [t.protein * 4, t.carbs * 4, t.fat * 9],
    'm': out,
  };
}

double? _kcalOf(FoodStore food, DateTime day) {
  final e = food.entriesFor(day);
  return e.isEmpty ? null : Totals(e).kcal;
}

/// Σώμα: η τελευταία ζύγιση της InBody που μετρά· το γράφημα = οι 7 τελευταίες μέρες ζύγισης (μία ζύγιση τη μέρα).
Map<String, dynamic> _body(HealthStore store, DateTime today) {
  final body = store.data?.body ?? const <BodyMeasurement>[];
  final out = <String, dynamic>{};
  // Round 1 (U7-16): χωρίς ζύγιση το widget το λέει.
  // Round 2 (R2-U3-04): σύντομη μορφή για τη στήλη 1×3 (πριν «καμία ζύγιση ακ…»).
  if (body.isEmpty) return {'src': 'καμία ζύγιση ακόμα', 'srcShort': 'καμία ζύγιση', 'm': out};
  // Round 2 (g4 · R2-D-6, R2-D-8): ίδιοι κανόνες με τη Σήμερα και το Σώμα: μία ζύγιση ανά μέρα (η πρώτη της μέρας που
  // μετρά) και καμία «ξένη» ([countedBody]). Πριν: η τελευταία ζύγιση, όποια κι αν ήταν, με «κάτω από το εύρος» και
  // «−47,0 kg» για το παιδί στη ζυγαριά, και ζυγίσεις της ίδιας μέρας στο γράφημα. Ζύγιση «σε αναμονή» φαίνεται κανονικά.
  // Round 3 (k1 · R3-A-1): [shownBody] = όπως πριν (οι «σε αναμονή» φαίνονται ως η τελευταία ζύγιση, όπως στη Σήμερα)·
  // το [countedBody] δεν τις έχει πια.
  final counted = shownBody(body);
  final days = counted.isEmpty ? body : counted;
  final last = days.last;
  final prev = days.length >= 2 ? days[days.length - 2] : null;
  final recent = days.length > 7 ? days.sublist(days.length - 7) : days;
  List<double?> series(double? Function(BodyMeasurement b) f) =>
      [for (var i = 0; i < 7 - recent.length; i++) null, for (final b in recent) f(b)];
  final p = store.profile;
  final bmi = bmiOf(last.weight, p.heightCm) ?? last.bmi;
  final fat = fatRange(p, today);
  final hw = healthyWeight(p.heightCm);

  if (last.weight case final w?) {
    // Round 2 (g4 · R2-D-6): η διαφορά των νούμερων όπως φαίνονται, όπως η Σήμερα (τρίτος έλεγχος F3): 82,24 και 83,36 →
    // «−1,2», όχι «−1,1».
    final dw = prev?.weight == null ? null : shownDiff(w, prev!.weight!, 1);
    out['weight'] = _entry('Βάρος', dec(w), ' kg',
        cap: '${shortDayDate(last.time)}${dw == null ? '' : ' · ${signedDec(dw)} kg'}',
        d: dw == null ? null : (dw == 0 ? 0 : (dw > 0 ? 1 : -1)),
        range: hw == null ? null : RefRange(low: hw.$1, high: hw.$2, text: '', cite: '').placeText(w),
        spark: series((b) => b.weight));
  }
  if (last.fatPct case final v?) {
    out['fatPct'] = _entry('Λίπος', dec(v), '%',
        cap: shortDayDate(last.time), range: fat?.placeText(v), spark: series((b) => b.fatPct));
  }
  if (last.smm case final v?) out['smm'] = _entry('Μύες', dec(v), ' kg', cap: shortDayDate(last.time), spark: series((b) => b.smm));
  if (last.ffm case final v?) out['ffm'] = _entry('Άλιπη', dec(v), ' kg', cap: shortDayDate(last.time), spark: series((b) => b.ffm));
  if (last.bmr case final v?) out['bmr'] = _entry('Μεταβολισμός', thousands(v), ' kcal', cap: shortDayDate(last.time));
  if (bmi != null) out['bmi'] = _entry('Δείκτης', dec(bmi), '', cap: shortDayDate(last.time), range: bmiRange.placeText(bmi));
  if (last.water case final v?) out['water'] = _entry('Νερό', dec(v), ' L', cap: shortDayDate(last.time));
  return {'src': 'InBody · ${shortDayDate(last.time)}', 'm': out};
}
