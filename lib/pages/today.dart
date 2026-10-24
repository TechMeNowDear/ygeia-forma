import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../labels.dart';
import '../theme.dart';
import '../widgets.dart';
import '../unusual.dart';
import 'unusual_card.dart';
import 'week_card.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    required this.store,
    required this.openTab,
    required this.openSettings,
    this.now,
  });

  final HealthStore store;
  final void Function(int) openTab;
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

        final settingsButton = TextButton.icon(
          onPressed: openSettings,
          style: TextButton.styleFrom(
            backgroundColor: c.card,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: const StadiumBorder(),
          ),
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Ρυθμίσεις'),
        );

        if (d == null || !d.hasAnyPermission) {
          return PageFrame(
            eyebrow: longDate(now),
            title: greeting(now),
            action: settingsButton,
            onRefresh: () => store.refresh(),
            left: [_ConnectCard(store: store)],
          );
        }

        final error = store.error != null ? _ErrorCard(store: store) : null;
        final hero = prefs.show('sleep') ? _SleepHero(data: d, onTap: () => openTab(2)) : null;
        final review = prefs.show('week') ? currentWeekReview(store.history, now) : null;
        final week = review == null ? null : WeekCard(review: review);
        final unusualResult = prefs.show('unusual') ? checkUnusual(store.history, dayOf(now)) : null;
        final unusual = unusualResult != null && unusualResult.show ? UnusualCard(result: unusualResult) : null;

        final heartCards = <Widget>[
          if (prefs.show('energy')) _energyCard(context, d),
          if (prefs.show('rhr')) _restingCard(context, d, () => openTab(3)),
        ];
        final moveCards = <Widget>[
          if (prefs.show('steps')) _stepsCard(context, d, () => openTab(4)),
          if (prefs.show('calories')) _caloriesCard(context, d, () => openTab(4)),
        ];
        final nightCards = <Widget>[
          if (prefs.show('spo2')) _spo2Card(context, d, () => openTab(3)),
          if (prefs.show('skin')) _skinCard(context, d, () => openTab(4)),
        ];
        final weight = prefs.show('weight') ? _WeightCard(data: d, onTap: () => openTab(4)) : null;

        final footer = Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Ενημέρωση ${hm(d.readAt)} · τράβηξε προς τα κάτω για ανανέωση',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textTertiary, fontSize: 12.5),
          ),
        );

        final heartSection = [
          if (heartCards.isNotEmpty) ...[const SectionHeader('Καρδιά και ενέργεια'), ...pairUp(heartCards)],
        ];
        final moveSection = [
          if (moveCards.isNotEmpty) ...[const SectionHeader('Κίνηση σήμερα'), ...pairUp(moveCards)],
        ];
        final nightSection = [
          if (nightCards.isNotEmpty) ...[const SectionHeader('Στον ύπνο'), ...pairUp(nightCards)],
        ];
        final bodySection = [
          if (weight != null) ...[const SectionHeader('Σώμα'), weight],
        ];

        return PageFrame(
          eyebrow: longDate(now),
          title: greeting(now),
          action: settingsButton,
          onRefresh: () => store.refresh(),
          single: [
            if (error != null) error,
            if (unusual != null) unusual,
            if (hero != null) hero,
            if (week != null) week,
            ...heartSection,
            ...moveSection,
            ...bodySection,
            ...nightSection,
            footer,
          ],
          left: [
            if (error != null) error,
            if (unusual != null) unusual,
            if (hero != null) hero,
            if (week != null) week,
            ...bodySection,
          ],
          right: [
            ...heartSection,
            ...moveSection,
            ...nightSection,
            footer,
          ],
        );
      },
    );
  }

  Widget _energyCard(BuildContext context, Dashboard d) {
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

  Widget _stepsCard(BuildContext context, Dashboard d, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final steps = d.todaySteps;
    final base = d.stepsBaseline;
    final last7 = d.steps.length <= 7 ? d.steps : d.steps.sublist(d.steps.length - 7);
    return StatCard(
      icon: Icons.directions_walk_rounded,
      color: c.move,
      title: 'Βήματα',
      value: steps == null ? null : thousands(steps),
      note: base == null ? null : 'Μέσος όρος ${thousands(base)}',
      chart: last7.length >= 2 ? MiniBars(values: [for (final s in last7) s.value], color: c.move) : null,
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
          : TrendPill('Χαμηλότερο ${min.round()}%', kind: min < 88 ? TrendKind.bad : TrendKind.neutral),
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
      title: 'Θερμοκρασία δέρματος',
      value: t == null ? null : (base == null ? dec(t) : signedDec(t - base)),
      unit: '°C',
      note: (t != null && base != null) ? 'Απόκλιση από τον μέσο όρο σου' : null,
      empty: 'Έρχεται μετά από έναν ύπνο με το ρολόι.',
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Η νυχτερινή κάρτα ύπνου
// ---------------------------------------------------------------------------

class _SleepHero extends StatelessWidget {
  const _SleepHero({required this.data, required this.onTap});

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
    final soft = Colors.white.withValues(alpha: 0.72);
    final base = data.sleepBaseline;
    final diff = base == null ? null : n.minutes - base.round();

    Widget time(String label, DateTime t, IconData icon) => Expanded(
          child: Row(
            children: [
              Icon(icon, size: 20, color: soft),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: soft, fontSize: 13, fontWeight: FontWeight.w500)),
                  Text(
                    hm(t),
                    style: const TextStyle(
                      color: white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabular,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
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
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.bedtime_rounded, size: 18, color: soft),
                              const SizedBox(width: 6),
                              Text(
                                'Ύπνος · ${_nightLabel(n.date, data.readAt)}',
                                style: TextStyle(color: soft, fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          DurationValue(n.minutes, size: 34, color: white, unitColor: soft),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ScoreRing(
                      value: n.score?.toDouble(),
                      size: 70,
                      stroke: 7,
                      color: white,
                      track: Colors.white.withValues(alpha: 0.16),
                      caption: 'Βαθμολογία',
                    ),
                  ],
                ),
                if (diff != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TrendPill(
                      diff.abs() < 10 ? 'Όσο κοιμάσαι συνήθως' : '${moreLessMinutes(diff)} από ό,τι συνήθως',
                      up: diff.abs() < 10 ? null : diff > 0,
                      onDark: true,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      time('Κοιμήθηκες', n.start, Icons.nights_stay_rounded),
                      Container(width: 1, height: 34, color: Colors.white.withValues(alpha: 0.15)),
                      const SizedBox(width: 14),
                      time('Ξύπνησες', n.end, Icons.wb_twilight_rounded),
                    ],
                  ),
                ),
                if (n.parts.length > 1) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Σε ${n.parts.length} κομμάτια, με διακοπές ενδιάμεσα',
                    style: TextStyle(color: soft, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 16),
                Hypnogram(night: n, height: 64, onDark: true),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(hm(n.start), style: TextStyle(color: soft, fontSize: 11.5, fontFeatures: tabular)),
                    const Spacer(),
                    Text(hm(n.end), style: TextStyle(color: soft, fontSize: 11.5, fontFeatures: tabular)),
                  ],
                ),
                const SizedBox(height: 14),
                StageLegend(night: n, onBlue: true),
                if (n.napMinutes > 0) ...[
                  const SizedBox(height: 12),
                  Text('Και υπνάκος ${hoursMinutes(n.napMinutes)}', style: TextStyle(color: soft, fontSize: 13)),
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
// Βάρος
// ---------------------------------------------------------------------------

class _WeightCard extends StatelessWidget {
  const _WeightCard({required this.data, required this.onTap});
  final Dashboard data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final last = data.latestBody;
    if (last == null || last.weight == null) {
      return EmptyCard(
        icon: Icons.monitor_weight_rounded,
        color: c.body,
        title: 'Βάρος',
        text: 'Ζυγίσου στην InBody. Η μέτρηση φτάνει εδώ μέσα σε λίγα λεπτά.',
      );
    }
    final prev = data.previousBody;
    final prevWeight = prev?.weight;
    Widget? trend;
    if (prev != null && prevWeight != null) {
      final diff = last.weight! - prevWeight;
      trend = TrendPill(
        '${signedDec(diff)} kg από ${dayMonth(prev.time)}',
        up: diff.abs() < 0.05 ? null : diff > 0,
        kind: diff < -0.05 ? TrendKind.good : (diff > 0.05 ? TrendKind.bad : TrendKind.neutral),
      );
    }
    final weights = [for (final b in data.body) if (b.weight != null) b.weight!];
    final recent = weights.length <= 10 ? weights : weights.sublist(weights.length - 10);

    Widget mini(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w700, fontFeatures: tabular),
              ),
            ],
          ),
        );

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            icon: Icons.monitor_weight_rounded,
            title: 'Βάρος · ${relativeDay(last.time, data.readAt)}',
            color: c.body,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BigValue(dec(last.weight!), unit: 'kg', size: 34),
                    if (trend != null) ...[const SizedBox(height: 8), trend],
                  ],
                ),
              ),
              if (recent.length >= 2)
                SizedBox(width: 120, child: Sparkline(values: recent, color: c.body, height: 48)),
            ],
          ),
          const Hairline(vertical: 14),
          Row(
            children: [
              mini('Λίπος', last.fatPct == null ? '—' : '${dec(last.fatPct!)}%'),
              mini('Σκελετικοί μύες', last.smm == null ? '—' : '${dec(last.smm!)} kg'),
              mini('Μάζα λίπους', last.fatKg == null ? '—' : '${dec(last.fatKg!)} kg'),
            ],
          ),
        ],
      ),
    );
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
