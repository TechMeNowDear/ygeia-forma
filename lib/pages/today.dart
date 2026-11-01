import 'package:flutter/material.dart';

import '../data.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../labels.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets.dart';
import '../unusual.dart';
import 'nutrition.dart';
import 'unusual_card.dart';
import 'week_card.dart';

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
        final sleep = prefs.show('sleep') ? _SleepCard(data: d, onTap: () => open(Cat.health, HealthTab.sleep)) : null;
        final review = prefs.show('week') ? currentWeekReview(store.history, now) : null;
        final week = review == null ? null : WeekCard(review: review);
        final unusualResult = prefs.show('unusual') ? checkUnusual(store.history, dayOf(now)) : null;
        final unusual = unusualResult != null && unusualResult.show ? UnusualCard(result: unusualResult) : null;
        final foodCard = prefs.show('food')
            ? FoodTodayCard(food: food, now: now, onOpen: () => open(Cat.food, FoodTab.diary))
            : null;

        final pair = <Widget>[
          if (prefs.show('steps')) _stepsCard(context, d, () => open(Cat.exercise)),
          if (prefs.show('weight')) _weightCard(context, d, () => open(Cat.health, HealthTab.body)),
        ];

        final extras = <Widget>[
          if (prefs.show('energy')) _energyCard(context, d, () => open(Cat.health, HealthTab.heart)),
          if (prefs.show('rhr')) _restingCard(context, d, () => open(Cat.health, HealthTab.heart)),
          if (prefs.show('calories')) _caloriesCard(context, d, () => open(Cat.exercise)),
          if (prefs.show('spo2')) _spo2Card(context, d, () => open(Cat.health, HealthTab.heart)),
          if (prefs.show('skin')) _skinCard(context, d, () => open(Cat.health, HealthTab.body)),
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

        final alerts = [if (error != null) error, if (unusual != null) unusual];
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
            if (week != null) week,
            if (foodCard != null) foodCard,
            ...more,
            footer,
          ],
          top: alerts,
          left: [if (sleep != null) sleep, if (week != null) week],
          right: [if (foodCard != null) foodCard, ...more, footer],
        );
      },
    );
  }

  Widget _stepsCard(BuildContext context, Dashboard d, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final steps = d.todaySteps;
    final base = d.stepsBaseline;
    final last7 = d.steps.length <= 7 ? d.steps : d.steps.sublist(d.steps.length - 7);
    return StatCard(
      icon: Icons.directions_walk_rounded,
      color: c.exercise,
      title: 'Βήματα',
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
      final diff = last!.weight! - prev!.weight!;
      trend = TrendPill(
        '${signedDec(diff)} kg από ${dayMonth(prev.time)}',
        // Κάτω από 1 kg είναι θόρυβος της ζυγαριάς (νερό, φαγητό): ουδέτερο χρώμα.
        kind: diff <= -1 ? TrendKind.good : (diff >= 1 ? TrendKind.bad : TrendKind.neutral),
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
      note: e == null ? null : relativeDay(e.day, d.readAt),
      chart: recent.length >= 2 ? Sparkline(values: [for (final v in recent) v.value], color: c.energy) : null,
      empty: 'Έρχεται μετά από έναν ύπνο με το ρολόι.',
      onTap: onTap,
    );
  }

  Widget _restingCard(BuildContext context, Dashboard d, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final hr = d.lastNight?.sleepingHr;
    final base = d.restingHrBaseline;
    Widget? trend;
    if (hr != null && base != null) {
      final diff = (hr - base).round();
      trend = diff == 0
          ? const TrendPill('Όπως συνήθως')
          : TrendPill(
              '${diff > 0 ? '+' : '−'}${diff.abs()} από τον μ.ό.',
              up: diff > 0,
              kind: diff >= 3 ? TrendKind.bad : (diff < 0 ? TrendKind.good : TrendKind.neutral),
            );
    }
    final recent = d.nights.where((n) => n.sleepingHr != null).toList();
    final last7 = recent.length <= 7 ? recent : recent.sublist(recent.length - 7);
    return StatCard(
      icon: Icons.favorite_rounded,
      color: c.heart,
      title: 'Παλμοί στον ύπνο',
      value: hr?.round().toString(),
      unit: 'bpm',
      trend: trend,
      chart: last7.length >= 2 ? Sparkline(values: [for (final n in last7) n.sleepingHr!], color: c.heart) : null,
      empty: 'Έρχεται μετά από έναν ύπνο με το ρολόι.',
      onTap: onTap,
    );
  }

  Widget _caloriesCard(BuildContext context, Dashboard d, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final total = (d.activity['calories'] as num?)?.toDouble();
    final active = (d.activity['activeCalories'] as num?)?.toDouble();
    final minutes = (d.activity['activeMinutes'] as num?)?.toInt();
    return StatCard(
      icon: Icons.local_fire_department_rounded,
      color: c.heart,
      title: 'Θερμίδες που έκαψες',
      value: total == null ? null : thousands(total),
      unit: 'kcal',
      note: active == null ? null : 'Από κίνηση ${thousands(active)} kcal',
      trend: (minutes != null && minutes > 0) ? TrendPill('Ενεργός ${hoursMinutes(minutes)}') : null,
      onTap: onTap,
    );
  }

  Widget _spo2Card(BuildContext context, Dashboard d, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final n = d.lastNight;
    final min = n?.spo2Min;
    return StatCard(
      icon: Icons.air_rounded,
      color: c.sleep,
      title: 'Οξυγόνο',
      value: n?.spo2Avg?.round().toString(),
      unit: '%',
      trend: min == null
          ? null
          : TrendPill('Χαμηλότερη μέτρηση ${min.round()}%'),
      empty: 'Έρχεται μετά από έναν ύπνο με το ρολόι.',
      onTap: onTap,
    );
  }

  Widget _skinCard(BuildContext context, Dashboard d, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final t = d.lastNight?.skinTemp;
    final base = d.skinTempBaseline;
    return StatCard(
      icon: Icons.thermostat_rounded,
      color: c.move,
      title: 'Θερμοκρασία καρπού',
      value: t == null ? null : (base == null ? dec(t) : signedDec(t - base)),
      unit: '°C',
      note: (t != null && base != null) ? 'Απόκλιση από τον μέσο όρο σου' : null,
      empty: 'Έρχεται μετά από έναν ύπνο με το ρολόι.',
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
    final diff = base == null ? null : n.minutes - base.round();
    final total = stageOrder.fold<int>(0, (s, k) => s + (n.stageMinutes[k] ?? 0));
    int pct(String k) => total == 0 ? 0 : ((n.stageMinutes[k] ?? 0) * 100 / total).round();
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
                    const SizedBox(width: 12),
                    ScoreRing(
                      value: n.score?.toDouble(),
                      size: 64,
                      stroke: 6,
                      color: c.ring,
                      track: Colors.white.withValues(alpha: 0.16),
                    ),
                  ],
                ),
                if (diff != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TrendPill(
                      diff.abs() < 10 ? 'Όσο κοιμάσαι συνήθως' : '${moreLessMinutes(diff)} από ό,τι συνήθως',
                      up: diff.abs() < 10 ? null : diff > 0,
                      onDark: true,
                    ),
                  ),
                ],
                if (n.estimatedMinutes > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Και ${hoursMinutes(n.estimatedMinutes)} πιθανός ύπνος στα κενά της Samsung (δεν μετρά)',
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
                        child: Text(
                          '${stageLabel('DEEP')} ${pct('DEEP')}% · REM ${pct('REM')}%',
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
