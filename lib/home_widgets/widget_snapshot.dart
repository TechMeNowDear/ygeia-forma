import '../data.dart';
import '../food/food_model.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../history.dart';
import '../reference.dart';
import '../shown.dart';
import '../sources.dart';
import 'widget_style.dart';

// Το στιγμιότυπο που ζωγραφίζουν τα widgets: έτοιμα κείμενα, ένα ανά τιμή, ΜΕ ΤΟΥΣ ΙΔΙΟΥΣ κανόνες με τις οθόνες
// (σχέδιο πηγών, «συνήθως», εύρη). Η Kotlin δεν υπολογίζει τίποτα δικό της, εκτός από τα βήματα και την κίνηση της
// μέρας, που τα ανανεώνει από την ανάγνωση στο παρασκήνιο (HomeWidgets.kt).
//
// Μορφή: {v, at, kinds: {sleep: {src, m: {κλειδί: {l, v, u, cap?, d?, us?, r?, s?}}}}}
//   l: όνομα στο κουτάκι, v: τιμή, u: μονάδα, cap: δεύτερη γραμμή όταν είναι η κεντρική τιμή,
//   d: −1/0/1 σε σχέση με τα συνηθισμένα, us: «συνήθως …», r: θέση στο εύρος, s: 7 τιμές για το γράφημα (null = κενό).

const widgetSnapshotVersion = 1;

Map<String, dynamic> buildWidgetSnapshot(HealthStore store, FoodStore food, DateTime now) {
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
  if (day == null) return {'m': out};
  final d0 = day;
  final src = plan.nightSource(d0);
  List<double?> series(String k) => [for (var i = 6; i >= 0; i--) plan.value(h, k, _minus(d0, i))];

  void add(String key, String label, String unit, String Function(double v) show, {int digits = 0, String? cap, String? range}) {
    final v = plan.value(h, key, d0);
    if (v == null) return;
    final b = personalBaseline(h, plan, key, d0);
    int? dir;
    String? usual;
    if (b?.usual != null) {
      final diff = shownDiff(b!.value, b.usual!, digits);
      dir = diff == 0 ? 0 : (diff > 0 ? 1 : -1);
      usual = 'συνήθως ${show(b.usual!)}${unit.isEmpty ? '' : unit}';
    }
    out[key] = _entry(label, show(v), unit, cap: cap, d: dir, usual: usual, range: range, spark: series(key));
  }

  final bed = plan.value(h, K.bedtime, d0), wake = plan.value(h, K.wake, d0);
  final sleepMin = plan.value(h, K.sleepMin, d0);
  final sr = sleepRange(store.profile, today);
  // Στρογγύλεμα πρώτα (έλεγχος 8/11, DATA-03): 419,5 λεπτά → 7:00, όχι 6:00.
  add(K.sleepMin, 'Ύπνος', '', (v) => '${v.round() ~/ 60}:${two(v.round() % 60)}',
      cap: bed != null && wake != null ? '${clockFromSix(bed)}–${clockFromSix(wake)}' : shortDayDate(d0),
      range: sleepMin != null && sr != null ? sr.placeText(sleepMin) : null);
  add(K.energy, 'Ετοιμότητα', '', (v) => '${v.round()}');
  add(K.sleepScore, 'Σκορ', '', (v) => '${v.round()}');
  add(K.hrv, 'HRV', ' ms', (v) => '${v.round()}');
  add(K.sleepHr, 'Παλμοί', ' bpm', (v) => '${v.round()}');
  add(K.lowHr, 'Χαμηλότεροι', ' bpm', (v) => '${v.round()}');
  add(K.ringSpo2, 'Οξυγόνο', '%', spo2AvgText, digits: 1);
  add(K.breath, 'Αναπνοές', '', (v) => dec(v), digits: 1,
      range: plan.value(h, K.breath, d0) == null ? null : breathRange.placeText(plan.value(h, K.breath, d0)!));
  // Θερμοκρασία: το Oura δίνει απόκλιση (+0,3°), το ρολόι απόλυτη τιμή καρπού (33,6 °C), που δεν δείχνεται ποτέ ως
  // «+33,6°» (έλεγχος 8/11, DATA-04). Από το ρολόι: μόνο η απόκλιση από τα συνηθισμένα, αν υπάρχουν.
  if (src == Source.oura) {
    add(K.skinTemp, 'Θερμοκρ.', '°', (v) => signedDec(v), digits: 1);
  } else {
    final v = plan.value(h, K.skinTemp, d0);
    final b = personalBaseline(h, plan, K.skinTemp, d0);
    if (v != null && b?.usual != null) {
      final diff = shownDiff(v, b!.usual!, 1);
      out[K.skinTemp] = _entry('Θερμοκρ.', signedDec(diff), '°', cap: 'απόκλιση καρπού');
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
  if (n('activeMinutes') case final v?) out['activeMin'] = _entry('Ενεργός', '${v.round()}′', '');
  if (d.valueFor(d.floors, today)?.value case final v?) out['floors'] = _entry('Όροφοι', '${v.round()}', '');
  if (n('distance') case final v?) out['distance'] = _entry('Απόσταση', dec(v / 1000), ' km');
  final dayHr = store.plan.value(store.history, K.dayHr, _minus(today, 1));
  if (dayHr != null) out['dayHr'] = _entry('Παλμοί χθες', '${dayHr.round()}', ' bpm');
  // 'day': η μέρα των τιμών· άλλη μέρα στο widget = «—» (έλεγχος 8/11, DATA-02, HomeWidgets.forToday).
  return {'src': 'ρολόι · ${hm(d.readAt)}', 'at': d.readAt.millisecondsSinceEpoch, 'day': dateKey(today), 'm': out};
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
    'carbs': _entry('Υδατ.', g(t.carbs), ' g'),
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

/// Σώμα: η τελευταία ζύγιση της InBody· το γράφημα = οι 7 τελευταίες ζυγίσεις (μία την εβδομάδα).
Map<String, dynamic> _body(HealthStore store, DateTime today) {
  final body = store.data?.body ?? const <BodyMeasurement>[];
  final out = <String, dynamic>{};
  if (body.isEmpty) return {'m': out};
  final last = body.last;
  final prev = body.length >= 2 ? body[body.length - 2] : null;
  final recent = body.length > 7 ? body.sublist(body.length - 7) : body;
  List<double?> series(double? Function(BodyMeasurement b) f) =>
      [for (var i = 0; i < 7 - recent.length; i++) null, for (final b in recent) f(b)];
  final p = store.profile;
  final bmi = bmiOf(last.weight, p.heightCm) ?? last.bmi;
  final fat = fatRange(p, today);
  final hw = healthyWeight(p.heightCm);

  if (last.weight case final w?) {
    final dw = prev?.weight == null ? null : w - prev!.weight!;
    out['weight'] = _entry('Βάρος', dec(w), ' kg',
        cap: '${shortDayDate(last.time)}${dw == null ? '' : ' · ${signedDec(dw)} kg'}',
        d: dw == null ? null : (shownDiff(w, prev!.weight!, 1) == 0 ? 0 : (dw > 0 ? 1 : -1)),
        range: hw == null ? null : RefRange(low: hw.$1, high: hw.$2, text: '', cite: '').placeText(w),
        spark: series((b) => b.weight));
  }
  if (last.fatPct case final v?) {
    out['fatPct'] = _entry('Λίπος', dec(v), '%',
        cap: shortDayDate(last.time), range: fat?.placeText(v), spark: series((b) => b.fatPct));
  }
  if (last.smm case final v?) out['smm'] = _entry('Μύες', dec(v), ' kg', cap: shortDayDate(last.time), spark: series((b) => b.smm));
  if (last.ffm case final v?) out['ffm'] = _entry('Άλιπη', dec(v), ' kg', cap: shortDayDate(last.time), spark: series((b) => b.ffm));
  if (last.bmr case final v?) out['bmr'] = _entry('Μεταβολ.', thousands(v), ' kcal', cap: shortDayDate(last.time));
  if (bmi != null) out['bmi'] = _entry('Δείκτης', dec(bmi), '', cap: shortDayDate(last.time), range: bmiRange.placeText(bmi));
  if (last.water case final v?) out['water'] = _entry('Νερό', dec(v), ' L', cap: shortDayDate(last.time));
  return {'src': 'InBody · ${shortDayDate(last.time)}', 'm': out};
}
