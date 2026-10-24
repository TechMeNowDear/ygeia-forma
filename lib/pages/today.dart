import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../labels.dart';
import '../theme.dart';
import '../widgets.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    required this.store,
    required this.openTab,
    required this.openSettings,
  });

  final HealthStore store;
  final void Function(int) openTab;
  final VoidCallback openSettings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final d = store.data;
        final now = DateTime.now();
        final prefs = store.prefs;

        final settingsButton = TextButton.icon(
          onPressed: openSettings,
          icon: const Icon(Icons.tune),
          label: const Text('Ρυθμίσεις'),
        );

        if (d == null || !d.hasAnyPermission) {
          return PageFrame(
            title: 'Σήμερα',
            subtitle: longDate(now),
            action: settingsButton,
            onRefresh: () => store.refresh(),
            left: [_ConnectCard(store: store)],
          );
        }

        final hero = <Widget>[
          if (store.error != null) _ErrorCard(store: store),
          if (prefs.show('sleep')) _SleepHero(data: d, onTap: () => openTab(1)),
        ];

        final small = <Widget>[
          if (prefs.show('energy')) _energyCard(d),
          if (prefs.show('rhr')) _restingCard(context, d, () => openTab(2)),
          if (prefs.show('steps')) _stepsCard(d, () => openTab(4)),
          if (prefs.show('calories')) _caloriesCard(d, () => openTab(4)),
          if (prefs.show('weight')) _weightCard(context, d, () => openTab(3)),
          if (prefs.show('spo2')) _spo2Card(context, d, () => openTab(2)),
          if (prefs.show('skin')) _skinCard(d, () => openTab(3)),
        ];

        final footer = Text(
          'Ενημέρωση ${hm(d.readAt)} · τράβηξε προς τα κάτω για ανανέωση',
          textAlign: TextAlign.center,
          style: TextStyle(color: Aigaio.of(context).textSecondary, fontSize: 13),
        );

        return PageFrame(
          title: 'Σήμερα',
          subtitle: longDate(now),
          action: settingsButton,
          onRefresh: () => store.refresh(),
          left: [...hero, if (hero.isEmpty) ...pairUp(small)],
          right: hero.isEmpty ? [footer] : [...pairUp(small), footer],
        );
      },
    );
  }

  Widget _energyCard(Dashboard d) {
    final e = d.latestEnergy;
    return StatCard(
      title: 'Energy Score',
      value: e?.value.round().toString(),
      note: e == null ? null : relativeDay(e.day, d.readAt),
      empty: 'Θέλει ύπνο με το ρολόι',
    );
  }

  Widget _restingCard(BuildContext context, Dashboard d, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final hr = d.lastNight?.sleepingHr;
    final base = d.restingHrBaseline;
    String? note;
    Color? color;
    if (hr != null && base != null) {
      final diff = hr - base;
      note = diff.abs() < 1 ? 'Όπως συνήθως' : '${signedDec(diff, 0)} από τον μέσο όρο σου';
      color = diff >= 3 ? c.terracotta : (diff <= -1 ? c.olive : null);
    } else if (hr != null) {
      note = 'Μέσος όρος στον ύπνο';
    }
    return StatCard(
      title: 'Παλμοί ηρεμίας',
      value: hr?.round().toString(),
      unit: 'bpm',
      note: note,
      noteColor: color,
      empty: 'Θέλει ύπνο με το ρολόι',
      onTap: onTap,
    );
  }

  Widget _stepsCard(Dashboard d, VoidCallback onTap) {
    final steps = d.todaySteps;
    final base = d.stepsBaseline;
    return StatCard(
      title: 'Βήματα',
      value: steps == null ? null : thousands(steps),
      note: base == null ? null : 'Μέσος όρος εβδομάδας ${thousands(base)}',
      onTap: onTap,
    );
  }

  Widget _caloriesCard(Dashboard d, VoidCallback onTap) {
    final total = (d.activity['calories'] as num?)?.toDouble();
    final active = (d.activity['activeCalories'] as num?)?.toDouble();
    return StatCard(
      title: 'Θερμίδες που έκαψες',
      value: total == null ? null : thousands(total),
      unit: 'kcal',
      note: active == null ? null : 'Από κίνηση ${thousands(active)} kcal',
      onTap: onTap,
    );
  }

  Widget _weightCard(BuildContext context, Dashboard d, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final last = d.latestBody;
    final prev = d.previousBody;
    String? note;
    Color? color;
    if (last != null) {
      final parts = <String>[];
      if (last.fatPct != null) parts.add('λίπος ${dec(last.fatPct!)}%');
      final prevWeight = prev?.weight;
      if (prev != null && prevWeight != null && last.weight != null) {
        final diff = last.weight! - prevWeight;
        parts.add('${signedDec(diff)} kg από ${dayMonth(prev.time)}');
        color = diff < -0.2 ? c.olive : null;
      }
      parts.add(relativeDay(last.time, d.readAt));
      note = parts.join(' · ');
    }
    return StatCard(
      title: 'Βάρος',
      value: last?.weight == null ? null : dec(last!.weight!),
      unit: 'kg',
      note: note,
      noteColor: color,
      empty: 'Ζυγίσου στην InBody',
      onTap: onTap,
    );
  }

  Widget _spo2Card(BuildContext context, Dashboard d, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final n = d.lastNight;
    final min = n?.spo2Min;
    return StatCard(
      title: 'Οξυγόνο στον ύπνο',
      value: n?.spo2Avg?.round().toString(),
      unit: '%',
      note: min == null ? null : 'Χαμηλότερο ${min.round()}%',
      noteColor: (min != null && min < 88) ? c.terracotta : null,
      empty: 'Θέλει ύπνο με το ρολόι',
      onTap: onTap,
    );
  }

  Widget _skinCard(Dashboard d, VoidCallback onTap) {
    final t = d.lastNight?.skinTemp;
    final base = d.skinTempBaseline;
    return StatCard(
      title: 'Θερμοκρασία δέρματος',
      value: (t == null || base == null) ? (t == null ? null : dec(t)) : signedDec(t - base),
      unit: '°C',
      note: (t != null && base != null) ? 'Σε σχέση με τον μέσο όρο σου' : null,
      empty: 'Θέλει ύπνο με το ρολόι',
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------

class _SleepHero extends StatelessWidget {
  const _SleepHero({required this.data, required this.onTap});

  final Dashboard data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final n = data.lastNight;
    final on = c.onPrimary;

    if (n == null) {
      return const EmptyCard(
        title: 'Ύπνος',
        text: 'Δεν υπάρχει ύπνος τις τελευταίες μέρες. Φόρεσε το ρολόι στον ύπνο και θα εμφανιστεί εδώ το πρωί.',
      );
    }

    final base = data.sleepBaseline;
    final diff = base == null ? null : n.minutes - base.round();

    return Material(
      color: c.primary,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ύπνος · ${_nightLabel(n.date, data.readAt)}',
                          style: TextStyle(color: on.withValues(alpha: 0.85), fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hoursMinutes(n.minutes),
                          style: TextStyle(color: on, fontSize: 36, fontWeight: FontWeight.w800),
                        ),
                        if (diff != null)
                          Text(
                            diff.abs() < 10
                                ? 'Όσο ο μέσος όρος της εβδομάδας'
                                : '${signedMinutes(diff)} από τον μέσο όρο της εβδομάδας',
                            style: TextStyle(color: on.withValues(alpha: 0.85), fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      ScoreRing(
                        value: n.score?.toDouble(),
                        size: 68,
                        stroke: 7,
                        color: on,
                        track: on.withValues(alpha: 0.25),
                      ),
                      const SizedBox(height: 4),
                      Text('Βαθμολογία', style: TextStyle(color: on.withValues(alpha: 0.85), fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              StageTimeline(night: n, onBlue: true),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(hm(n.start), style: TextStyle(color: on.withValues(alpha: 0.85), fontSize: 12)),
                  const Spacer(),
                  Text(hm(n.end), style: TextStyle(color: on.withValues(alpha: 0.85), fontSize: 12)),
                ],
              ),
              const SizedBox(height: 10),
              StageLegend(night: n, onBlue: true),
              if (n.napMinutes > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Και υπνάκος ${hoursMinutes(n.napMinutes)}',
                  style: TextStyle(color: on.withValues(alpha: 0.85), fontSize: 13),
                ),
              ],
            ],
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

class _ConnectCard extends StatelessWidget {
  const _ConnectCard({required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final on = c.onPrimary;
    final err = store.error;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(26)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            store.loading ? 'Διαβάζω…' : 'Σύνδεση με Samsung Health',
            style: TextStyle(color: on, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            err != null
                ? errorText(err['kind'] as String? ?? 'other')
                : 'Θα ανοίξει το παράθυρο του Samsung Health. Πάτα «Επιλογή όλων» και «Τέλος». '
                    'Η εφαρμογή μόνο διαβάζει.',
            style: TextStyle(color: on, fontSize: 16, height: 1.35),
          ),
          const SizedBox(height: 16),
          if (store.loading)
            Center(child: CircularProgressIndicator(color: on))
          else
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: on, foregroundColor: c.primary),
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
    final kind = store.error?['kind'] as String? ?? 'other';
    return EmptyCard(
      title: 'Δεν έγινε νέα ανάγνωση',
      text: '${errorText(kind)} Βλέπεις τα τελευταία δεδομένα που διάβασα.',
      buttonText: 'Δοκίμασε ξανά',
      onPressed: () => store.refresh(),
    );
  }
}
