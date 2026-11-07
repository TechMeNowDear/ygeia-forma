import 'package:flutter/material.dart';

import '../data.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../history.dart';
import '../labels.dart';
import '../nav.dart';
import '../oxygen_note.dart';
import '../shown.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import '../unusual.dart';
import 'nutrition.dart';
import 'oura_today.dart';
import 'sources_page.dart';
import 'unusual_card.dart';
import 'week_card.dart';
import 'oxygen_widgets.dart';

/// Η αρχική οθόνη: τα σημαντικά από κάθε κατηγορία, μία ερώτηση ανά κάρτα.
/// Πώς κοιμήθηκα; Τι έφαγα; Κουνήθηκα; Πού πάει το βάρος μου; Οι ειδοποιήσεις μόνο όταν υπάρχουν.
class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    required this.store,
    required this.food,
    required this.open,
    required this.openSettings,
    this.now,
  });

  final HealthStore store;
  final FoodStore food;

  /// Άνοιγμα κατηγορίας ([Cat]) και καρτέλας μέσα της.
  final void Function(int category, [int? tab]) open;
  final VoidCallback openSettings;

  /// Για τα στιγμιότυπα δοκιμών· στην εφαρμογή είναι πάντα «τώρα».
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = Aigaio.of(context);
        final d = store.data;
        final now = this.now ?? DateTime.now();
        final prefs = store.prefs;

        final settingsButton = IconButton(
          tooltip: 'Ρυθμίσεις',
          onPressed: openSettings,
          style: IconButton.styleFrom(
            backgroundColor: c.card,
            foregroundColor: c.text,
            fixedSize: const Size(46, 46),
            side: BorderSide(color: c.hairline),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          icon: const Icon(Icons.tune_rounded, size: 20),
        );
        // Στη μεγάλη οθόνη οι Ρυθμίσεις είναι κάτω στην πλευρική μπάρα.
        final action = MediaQuery.sizeOf(context).width >= 600 ? null : settingsButton;

        if (d == null || !d.hasAnyPermission) {
          return PageFrame(
            eyebrow: longDate(now),
            title: greeting(now),
            action: action,
            onRefresh: () => store.refresh(),
            left: [_ConnectCard(store: store)],
          );
        }

        final error = store.error != null ? _ErrorCard(store: store) : null;
        // Από τη σύνδεση του Oura η «νύχτα» (ύπνος, παλμοί και θερμοκρασία ύπνου, ετοιμότητα) έρχεται μόνο από αυτό.
        final ouraNight = store.plan.nightSource(now) != Source.watch;
        final openSleep = () => open(Cat.health, HealthTab.sleep);
        final sleep = !prefs.show('sleep')
            ? null
            : ouraNight
                ? OuraSleepTodayCard(store: store, now: now, onTap: openSleep)
                : _SleepCard(data: d, onTap: openSleep);
        // Μόνο όταν η χθεσινή νύχτα έχει τιμές από το Oura (αλλιώς η κάρτα ύπνου λέει ήδη γιατί λείπει).
        final rest = ouraNight && store.plan.nightSource(now) == Source.oura && OuraRestCard.hasData(store, now)
            ? OuraRestCard(store: store, now: now, onTap: openSleep)
            : null;
        final ouraState = PlanUnknownCard.shows(store)
            ? PlanUnknownCard(onOpen: () => Navigator.of(context).push(SourcesPage.route(store, now: this.now)))
            : OuraStatusCard.shows(store)
                ? OuraStatusCard(store: store, now: now)
                : null;
        final review = prefs.show('week') ? currentWeekReview(store.history, now, plan: store.analysisPlan) : null;
        final week = review == null ? null : WeekCard(review: review);
        final unusualResult = prefs.show('unusual') ? checkUnusual(store.history, dayOf(now), plan: store.analysisPlan) : null;
        final unusual = unusualResult != null && unusualResult.show ? UnusualCard(result: unusualResult) : null;
        final foodCard = prefs.show('food')
            ? FoodTodayCard(food: food, now: now, onOpen: () => open(Cat.food, FoodTab.diary))
            : null;

        final pair = <Widget>[
          if (prefs.show('steps')) _stepsCard(context, d, now, () => open(Cat.exercise)),
          if (prefs.show('weight')) _weightCard(context, d, () => open(Cat.health, HealthTab.body)),
        ];

        // Με το Oura: το Energy Score της Samsung δεν φαίνεται (τη θέση του παίρνει η ετοιμότητα του Oura στην
        // «Καρδιά και θερμοκρασία στον ύπνο»), και οι παλμοί/θερμοκρασία ύπνου είναι μόνο στην ίδια κάρτα. Το οξυγόνο μένει του ρολογιού.
        // Οξυγόνο: η σημείωση υπολογίζεται εδώ, γιατί η κάρτα εμφανίζεται ΜΟΝΗ της (και κλειστή στις Ρυθμίσεις) όταν το
        // χαμηλό επαναλαμβάνεται (τρίτος κλινικός έλεγχος C3/F5): αλλιώς η σύσταση «πες το στον γιατρό σου» ήταν δύο
        // πατήματα μακριά. Όχι για μία μόνο νύχτα.
        // Έλεγχος 3, E5: όλες οι 30 νύχτες από το ιστορικό (ίδιος αισθητήρας), πέρα από τη σύνδεση του Oura και το
        // όριο της επανάγνωσης· χωρίς «since».
        final oxGuidance = ouraNight
            ? oxygenGuidance(
                d.spo2MinByNight(now, ouraNights: true, windows: store.ouraWindows, history: store.history), now,
                today: now)
            : (d.lastNight == null
                ? null
                : oxygenGuidance(
                    d.spo2MinByNight(d.lastNight!.date, history: store.history), d.lastNight!.date, today: now));
        final oxAuto = !prefs.show('spo2') && oxGuidance != null && (oxGuidance.veryLowRepeated || oxGuidance.repeated);
        Widget oxCard() => ouraNight
            ? _watchSpo2Card(context, d, now, store.ouraWindows, oxGuidance!, () => open(Cat.health, HealthTab.heart),
                auto: oxAuto)
            : _spo2Card(context, d, now, oxGuidance, () => open(Cat.health, HealthTab.heart), auto: oxAuto);
        final extras = <Widget>[
          if (!ouraNight && prefs.show('energy')) _energyCard(context, d, () => open(Cat.health, HealthTab.heart)),
          if (!ouraNight && prefs.show('rhr')) _restingCard(context, d, now, () => open(Cat.health, HealthTab.heart)),
          if (prefs.show('calories')) _caloriesCard(context, d, now, () => open(Cat.exercise)),
          if (prefs.show('spo2')) oxCard(),
          if (!ouraNight && prefs.show('skin')) _skinCard(context, d, now, () => open(Cat.health, HealthTab.body)),
        ];

        final footer = Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Ενημέρωση ${sameDay(d.readAt, now) ? '' : '${relativeDay(d.readAt, now)} '}${hm(d.readAt)} · '
            'τράβηξε προς τα κάτω για ανανέωση',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textTertiary, fontSize: 12.5),
          ),
        );

        final dbNotice = store.dbCorruptAt == null ? null : _DatabaseCard(store: store);
        final alerts = [
          if (dbNotice != null) dbNotice,
          if (ouraState != null) ouraState,
          if (error != null) error,
          if (unusual != null) unusual,
          if (oxAuto) KeyedSubtree(key: const ValueKey('today-oxygen-auto'), child: oxCard()),
        ];
        final more = [
          ...pairUp(pair),
          if (extras.isNotEmpty) ...[const SectionHeader('Επίσης'), ...pairUp(extras)],
        ];

        return PageFrame(
          eyebrow: longDate(now),
          title: greeting(now),
          action: action,
          onRefresh: () => store.refresh(),
          single: [
            ...alerts,
            if (sleep != null) sleep,
            if (rest != null) rest,
            if (week != null) week,
            if (foodCard != null) foodCard,
            ...more,
            footer,
          ],
          top: alerts,
          left: [if (sleep != null) sleep, if (rest != null) rest, if (week != null) week],
          right: [if (foodCard != null) foodCard, ...more, footer],
        );
      },
    );
  }

  Widget _stepsCard(BuildContext context, Dashboard d, DateTime now, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final steps = d.todaySteps;
    final base = d.stepsBaseline;
    final last7 = d.steps.length <= 7 ? d.steps : d.steps.sublist(d.steps.length - 7);
    return StatCard(
      icon: Icons.directions_walk_rounded,
      color: c.exercise,
      // Από αποθηκευμένη ανάγνωση άλλης μέρας: το λέει, να μη μοιάζει με τα σημερινά.
      // UX U8: ίδια μορφή ημερομηνίας με τις άλλες κάρτες («Σάβ 24/10»).
      title: datedTitle('Βήματα', d.readAt, now),
      value: steps == null ? null : thousands(steps),
      note: base == null ? null : 'Συνήθως ${thousands(base)}',
      chart: last7.length >= 2 ? MiniBars(values: [for (final s in last7) s.value], color: c.exercise) : null,
      onTap: onTap,
    );
  }

  Widget _weightCard(BuildContext context, Dashboard d, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final last = d.latestBody;
    final prev = d.previousBody;
    Widget? trend;
    if (last?.weight != null && prev?.weight != null) {
      // Η διαφορά των νούμερων όπως φαίνονται (τρίτος έλεγχος F3): 82,2 και 83,4 → «−1,2», όχι «−1,1».
      final diff = shownDiff(last!.weight!, prev!.weight!, 1);
      trend = TrendPill(
        // Σύντομη ημερομηνία και έως 2 γραμμές: στα 360 dp το «από 13 Αυγ» κοβόταν (έλεγχος UX U2).
        '${signedDec(diff)} kg από ${prev.time.day}/${prev.time.month}',
        // Ουδέτερο χρώμα: χωρίς στόχο (μετά τον γιατρό) ούτε η πτώση ούτε η άνοδος είναι «καλή» ή «κακή».
        kind: TrendKind.neutral,
        maxLines: 2,
      );
    }
    final weights = [for (final b in d.body) if (b.weight != null) b.weight!];
    final recent = weights.length <= 10 ? weights : weights.sublist(weights.length - 10);
    return StatCard(
      icon: Icons.monitor_weight_rounded,
      color: c.body,
      // Αν η τελευταία ζύγιση δεν είναι σημερινή, λέει πότε έγινε.
      title: last == null || sameDay(last.time, d.readAt) ? 'Βάρος' : 'Βάρος · ${relativeDay(last.time, d.readAt)}',
      value: last?.weight == null ? null : dec(last!.weight!),
      unit: 'kg',
      trend: trend,
      chart: recent.length >= 2 ? Sparkline(values: recent, color: c.body) : null,
      empty: 'Ζυγίσου στην InBody. Η μέτρηση φτάνει εδώ σε λίγα λεπτά.',
      onTap: onTap,
    );
  }

  Widget _energyCard(BuildContext context, Dashboard d, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final e = d.latestEnergy;
    final recent = d.energy.length <= 7 ? d.energy : d.energy.sublist(d.energy.length - 7);
    return StatCard(
      icon: Icons.bolt_rounded,
      color: c.energy,
      title: 'Energy Score',
      value: e?.value.round().toString(),
      unit: 'από 100',
      note: e == null ? null : '${relativeDay(e.day, d.readAt)} · εκτίμηση της Samsung',
      chart: recent.length >= 2 ? Sparkline(values: [for (final v in recent) v.value], color: c.energy) : null,
      empty: 'Έρχεται μετά από έναν ύπνο με το ρολόι.',
      onTap: onTap,
    );
  }

  Widget _restingCard(BuildContext context, Dashboard d, DateTime now, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final hr = d.lastNight?.sleepingHr;
    final base = d.restingHrBaseline;
    Widget? trend;
    if (hr != null && base != null) {
      // Η διαφορά των νούμερων όπως φαίνονται (έλεγχος υπολογισμών C6) και η ίδια λέξη «συνήθως» παντού (C7/U7).
      // Ένας κανόνας σε όλες τις οθόνες (τρίτος έλεγχος F1).
      final diff = shownDiff(hr, base);
      trend = diff == 0
          ? const TrendPill(asUsualText)
          : TrendPill(
              '${signedShown(diff)} · συνήθως ${base.round()}',
              up: diff > 0,
              // Η πτώση είναι ουδέτερη, όχι «καλή» (κλινικός έλεγχος M4). Κόκκινο μόνο με τον κανόνα του «Εκτός
              // συνηθισμένου» (κλινικός έλεγχος 4, C1)· αλλιώς γκρι.
              kind: diff > 0 && sleepHrOff(store.history, d.lastNight!.date, plan: store.analysisPlan)
                  ? TrendKind.bad
                  : TrendKind.neutral,
            );
    }
    final recent = d.nights.where((n) => n.sleepingHr != null).toList();
    final last7 = recent.length <= 7 ? recent : recent.sublist(recent.length - 7);
    return StatCard(
      icon: Icons.favorite_rounded,
      color: c.heart,
      title: datedTitle('Παλμοί στον ύπνο', hr == null ? null : d.lastNight!.date, now),
      value: hr?.round().toString(),
      unit: 'bpm',
      trend: trend,
      chart: last7.length >= 2 ? Sparkline(values: [for (final n in last7) n.sleepingHr!], color: c.heart) : null,
      empty: 'Έρχεται μετά από έναν ύπνο με το ρολόι.',
      onTap: onTap,
    );
  }

  /// Οξυγόνο της νύχτας από το ρολόι όταν ο ύπνος είναι του Oura: μετρήσεις του ρολογιού μέσα στις ώρες της
  /// νύχτας του Oura. Χωρίς νύχτα του Oura δεν ξέρουμε πότε κοιμήθηκες: κενό, με τον λόγο.
  /// [g]: η σημείωση χαμηλού οξυγόνου (B7) με τις τιμές του ορισμού A4. [auto]: η κάρτα φαίνεται μόνη της, επειδή το
  /// χαμηλό επαναλαμβάνεται· τότε η σημείωση φαίνεται και χωρίς τιμή για την τελευταία νύχτα.
  Widget _watchSpo2Card(BuildContext context, Dashboard d, DateTime now, SleepWindows windows, OxygenGuidance g,
      VoidCallback onTap, {bool auto = false}) {
    final c = Aigaio.of(context);
    // 7/11: μέσος όρος από το Oura, χαμηλότερη από το ρολόι (μόνο με κάλυψη ≥ 50%).
    final rox = ringOxygen(store, d, now, windows);
    final noWindow = !windows.mains.containsKey(dateKey(dayOf(now)));
    return StatCard(
      icon: Icons.air_rounded,
      color: c.sleep,
      title: 'Οξυγόνο στον ύπνο',
      value: rox.avg == null ? null : spo2AvgText(rox.avg!),
      unit: '%',
      trend: rox.min == null ? null : TrendPill('Χαμηλότερο ${lowestText(rox.min!)}% · ρολόι'),
      note: rox.isEmpty ? null : (g.short ?? (rox.avg == null ? ringAvgMissing(store) : 'Μέσος όρος · Oura')),
      empty: auto && g.short != null
          ? g.short
          : noWindow
              ? 'Χωρίς νύχτα από το δαχτυλίδι δεν ξέρουμε πότε κοιμήθηκες· το οξυγόνο της νύχτας μένει κενό.'
              : ringAvgMissing(store),
      onTap: onTap,
    );
  }

  Widget _caloriesCard(BuildContext context, Dashboard d, DateTime now, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final total = (d.activity['calories'] as num?)?.toDouble();
    final active = (d.activity['activeCalories'] as num?)?.toDouble();
    final minutes = (d.activity['activeMinutes'] as num?)?.toInt();
    return StatCard(
      icon: Icons.local_fire_department_rounded,
      color: c.heart,
      // Κλινικός έλεγχος M9: τα ρολόγια κάνουν μεγάλα λάθη στις θερμίδες (συχνά 20–30%).
      // Οι θερμίδες είναι της μέρας της ανάγνωσης: από αποθηκευμένη ανάγνωση άλλης μέρας, με την ημερομηνία (A11).
      title: datedTitle('Θερμίδες', total == null ? null : d.readAt, now),
      value: total == null ? null : thousands(total),
      unit: 'kcal',
      note: active == null ? 'Εκτίμηση ρολογιού' : 'Εκτίμηση ρολογιού · από κίνηση ${thousands(active)} kcal',
      trend: (minutes != null && minutes > 0) ? TrendPill('Ενεργός ${hoursMinutes(minutes)}') : null,
      onTap: onTap,
    );
  }

  Widget _spo2Card(BuildContext context, Dashboard d, DateTime now, OxygenGuidance? g, VoidCallback onTap,
      {bool auto = false}) {
    final c = Aigaio.of(context);
    final n = d.lastNight;
    final min = n?.spo2Min;
    return StatCard(
      icon: Icons.air_rounded,
      color: c.sleep,
      title: datedTitle('Οξυγόνο', n?.spo2Avg == null && min == null ? null : n!.date, now),
      value: n?.spo2Avg == null ? null : spo2AvgText(n!.spo2Avg!),
      unit: '%',
      trend: min == null
          ? null
          : TrendPill('Χαμηλότερη μέτρηση ${lowestText(min)}% · ενδεικτικό'),
      note: g?.short,
      empty: auto && g?.short != null ? g!.short : 'Έρχεται μετά από έναν ύπνο με το ρολόι.',
      onTap: onTap,
    );
  }

  Widget _skinCard(BuildContext context, Dashboard d, DateTime now, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final t = d.lastNight?.skinTemp;
    final base = d.skinTempBaseline;
    return StatCard(
      icon: Icons.thermostat_rounded,
      color: c.move,
      title: datedTitle('Θερμοκρασία καρπού', t == null ? null : d.lastNight!.date, now),
      // Χωρίς μέσο όρο δεν δείχνουμε απόλυτη τιμή καρπού (π.χ. 33,6 °C διαβάζεται ως υποθερμία· κλινικός έλεγχος L5).
      // Διαφορά των νούμερων όπως φαίνονται, ίδια με το «Εκτός συνηθισμένου» (τρίτος έλεγχος F3).
      value: t == null || base == null ? null : signedDec(shownDiff(t, base, 1)),
      unit: '°C',
      note: (t != null && base != null) ? 'Απόκλιση από τα συνηθισμένα σου' : null,
      empty: t == null ? 'Έρχεται μετά από έναν ύπνο με το ρολόι.' : 'Μαθαίνει το συνηθισμένο σου (7 νύχτες).',
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Ο ύπνος της νύχτας, σε σύντομη μορφή (η πλήρης είναι στην Υγεία › Ύπνος)
// ---------------------------------------------------------------------------

class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.data, required this.onTap});

  final Dashboard data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final n = data.lastNight;

    if (n == null) {
      return EmptyCard(
        icon: Icons.bedtime_rounded,
        color: c.sleep,
        title: 'Ύπνος',
        text: 'Δεν υπάρχει ύπνος τις τελευταίες μέρες. Φόρεσε το ρολόι στον ύπνο και θα εμφανιστεί εδώ το πρωί.',
      );
    }

    const white = Colors.white;
    final soft = Colors.white.withValues(alpha: 0.75);
    final base = data.sleepBaseline;
    // Σύγκριση μόνο για νύχτα με φάσεις (πραγματικός ύπνος): χωρίς φάσεις η διάρκεια έχει τα ξυπνήματα.
    final diff = base == null || !n.staged ? null : n.minutes - base.round();
    // Ένας κανόνας για το «συνήθως» (τρίτος έλεγχος F1): «Όσο κοιμάσαι συνήθως» μόνο για 0 λεπτά διαφορά.
    final total = stageOrder.fold<int>(0, (s, k) => s + (n.stageMinutes[k] ?? 0));
    final stages = [for (final k in stageOrder) if ((n.stageMinutes[k] ?? 0) > 0) k];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppCard.radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.nightTop, c.nightBottom],
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppCard.radius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.bedtime_rounded, size: 18, color: soft),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ύπνος · ${_nightLabel(n.date, data.readAt)}',
                        style: TextStyle(color: soft, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.6)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: DurationValue(n.minutes, size: 42, color: white, unitColor: soft)),
                    // Χωρίς βαθμολογία της νύχτας (π.χ. σε κομμάτια, η Samsung βαθμολογεί το καθένα): χωρίς άδειο
                    // δαχτυλίδι «—», που ήθελε εξήγηση (έλεγχος UX U8).
                    if (n.score != null) ...[
                      const SizedBox(width: 12),
                      ScoreRing(
                        value: n.score!.toDouble(),
                        size: 64,
                        stroke: 6,
                        color: c.ring,
                        track: Colors.white.withValues(alpha: 0.16),
                      ),
                    ],
                  ],
                ),
                if (diff != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TrendPill(
                      sleepVsUsualText(diff),
                      up: diff == 0 ? null : diff > 0,
                      onDark: true,
                      maxLines: 2,
                    ),
                  ),
                ],
                if (!n.staged) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Χωρίς φάσεις από τη Samsung· διάρκεια με τα ξυπνήματα',
                    style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                ],
                if (n.estimatedMinutes > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    // Μία φράση παντού για το κενό που ίσως ήταν ύπνος (UX U3).
                    '+${hoursMinutes(n.estimatedMinutes)} $possibleSleepPhrase',
                    style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                ],
                if (total > 0) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 10,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, k) in stages.indexed) ...[
                            if (i > 0) const SizedBox(width: 2),
                            Expanded(flex: n.stageMinutes[k]!, child: ColoredBox(color: c.stage(k))),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(hm(n.start), style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w600, fontFeatures: tabular)),
                      Expanded(
                        // Χωρίς ποσοστά μίας νύχτας (κλινικός έλεγχος H1): μόνο η μπάρα, ως εκτίμηση.
                        child: Text(
                          'Φάσεις · εκτίμηση της Samsung',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(hm(n.end), style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w600, fontFeatures: tabular)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _nightLabel(DateTime wakeDay, DateTime now) {
    if (sameDay(wakeDay, now)) return 'χθες βράδυ';
    return 'ξύπνημα ${relativeDay(wakeDay, now).toLowerCase()}';
  }
}

// ---------------------------------------------------------------------------

class _ConnectCard extends StatelessWidget {
  const _ConnectCard({required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final err = store.error;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.nightTop, c.nightBottom],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            store.loading ? 'Διαβάζω…' : 'Σύνδεση με Samsung Health',
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            err != null
                ? errorText(err['kind'] as String? ?? 'other')
                : 'Θα ανοίξει το παράθυρο του Samsung Health. Πάτα «Επιλογή όλων» και «Τέλος». '
                    'Η εφαρμογή μόνο διαβάζει.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15.5, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (store.loading)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: c.nightTop),
              onPressed: () => store.refresh(askPermissions: true),
              child: const Text('Σύνδεση με Samsung Health'),
            ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final kind = store.error?['kind'] as String? ?? 'other';
    return EmptyCard(
      icon: Icons.sync_problem_rounded,
      color: c.bad,
      title: 'Δεν έγινε νέα ανάγνωση',
      text: '${errorText(kind)} Βλέπεις τα τελευταία δεδομένα που διάβασα.',
      buttonText: 'Δοκίμασε ξανά',
      onPressed: () => store.refresh(),
    );
  }
}

/// Η βάση του κινητού βρέθηκε χαλασμένη (A7): τίποτα δεν σβήστηκε, το παλιό αρχείο κρατήθηκε.
class _DatabaseCard extends StatelessWidget {
  const _DatabaseCard({required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return EmptyCard(
      icon: Icons.storage_rounded,
      color: c.bad,
      title: 'Η βάση χάλασε· κράτησα αντίγραφο',
      text: 'Ξεκίνησε καινούργια βάση και το παλιό αρχείο κρατήθηκε στο κινητό. Το ιστορικό ξαναδιαβάζεται από τη '
          'Samsung Health. Το ημερολόγιο φαγητού επανέρχεται από το αντίγραφό σου (Ρυθμίσεις › Αντίγραφο ασφαλείας).',
      buttonText: 'Εντάξει',
      onPressed: () => store.dismissDatabaseNotice(),
    );
  }
}
