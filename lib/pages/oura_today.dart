import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../oura/oura_api.dart';
import '../oura/oura_store.dart';
import '../oura/oura_view.dart';
import '../plan_file.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import 'oura_pages.dart';
import 'source_widgets.dart';

/// Κάρτες κατάστασης στην κορυφή της Σήμερα, μόνο όταν ισχύουν (States mockup). Φεύγουν μόνες τους.
class OuraStatusCard extends StatelessWidget {
  const OuraStatusCard({super.key, required this.store, required this.now});
  final HealthStore store;
  final DateTime now;

  /// Αν πρέπει να φανεί κάρτα.
  static bool shows(HealthStore s) => switch (s.ouraStatus) {
        OuraStatus.waiting || OuraStatus.missing || OuraStatus.reconnect || OuraStatus.subscription => true,
        OuraStatus.disconnected || OuraStatus.starting || OuraStatus.startingNow || OuraStatus.incomplete => true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final s = store.ouraStatus;
    final missing = store.ouraMissingNights;
    final last = store.lastOuraNight;
    final (title, text, color, button) = switch (s) {
      OuraStatus.waiting => (
          'Περιμένει το Oura',
          'Η χθεσινή νύχτα δεν έχει φτάσει ακόμα. Άνοιξε την εφαρμογή Oura για να συγχρονίσει, και μετά γύρνα εδώ.',
          c.sleep,
          null,
        ),
      OuraStatus.missing when missing >= 2 => (
          last == null
              ? 'Το Oura δεν έχει συγχρονιστεί ακόμα'
              : 'Το Oura δεν έχει συγχρονιστεί από ${relativeDay(last.day, now).toLowerCase() == 'χθες' ? 'χθες' : weekdayFull(last.day)}',
          'Λείπουν ${countText(missing, 'νύχτα', 'νύχτες')}. Άνοιξε την εφαρμογή Oura με το δαχτυλίδι κοντά στο κινητό· '
              'οι νύχτες έρχονται μόνες τους μετά.',
          c.move,
          null,
        ),
      OuraStatus.missing => (
          'Χθες βράδυ χωρίς ύπνο από το δαχτυλίδι',
          'Η νύχτα μένει κενή στον Ύπνο και στις Τάσεις. Το οξυγόνο από το ρολόι φαίνεται κανονικά.',
          c.textSecondary,
          null,
        ),
      OuraStatus.starting => (
          'Από απόψε ο ύπνος από το Oura',
          'Το Oura συνδέθηκε. Η χθεσινή νύχτα μένει όπως τη μέτρησε το ρολόι· από την επόμενη νύχτα ο ύπνος έρχεται '
              'μόνο από το δαχτυλίδι. Φόρεσέ το απόψε.',
          c.sleep,
          null,
        ),
      OuraStatus.startingNow => (
          store.ouraFirstNightText,
          'Το Oura συνδέθηκε. ${now.hour < 4 ? 'Όταν ξυπνήσεις, άνοιξε' : 'Άνοιξε'} την εφαρμογή Oura για να συγχρονίσει, '
              'και μετά γύρνα εδώ. Ο ύπνος έρχεται μόνο από το δαχτυλίδι.',
          c.sleep,
          store.canWatchLastNight && now.hour >= 4 ? 'Oura' : null,
        ),
      OuraStatus.incomplete => (
          'Η σύνδεση δεν ολοκληρώθηκε',
          'Η σύνδεση με το Oura έμεινε μισή και δεν άλλαξε τίποτα. Δοκίμασε ξανά.',
          c.textSecondary,
          'Σύνδεση με Oura',
        ),
      OuraStatus.reconnect => (
          'Χρειάζεται νέα σύνδεση με το Oura',
          'Γίνεται μετά από αλλαγή κινητού ή αν αφαιρέσεις την άδεια στην Oura. Δεν χάνεται τίποτα· οι νύχτες που '
              'έλειψαν έρχονται μετά.',
          c.bad,
          'Σύνδεση ξανά',
        ),
      OuraStatus.subscription => ('Η Oura δεν δίνει δεδομένα', ouraErrorText(OuraErrorKind.subscription), c.bad, null),
      OuraStatus.disconnected => (
          'Ο ύπνος δεν έχει πηγή',
          'Το Oura αποσυνδέθηκε. Οι νύχτες μένουν κενές ώσπου να το συνδέσεις ξανά ή να διαλέξεις το ρολόι.',
          c.textSecondary,
          'Oura',
        ),
      _ => ('', '', c.textSecondary, null),
    };
    return EmptyCard(
      key: ValueKey('oura-status-${s.name}'),
      icon: s == OuraStatus.reconnect || s == OuraStatus.subscription ? Icons.link_off_rounded : Icons.bedtime_rounded,
      color: color,
      title: title,
      text: text,
      buttonText: button,
      onPressed: button == null
          ? null
          : () => Navigator.of(context).push(
                (s == OuraStatus.reconnect || s == OuraStatus.incomplete) && store.ouraConfigured
                    ? OuraConnectPage.route(store, now: now)
                    : OuraManagePage.route(store, now: now),
              ),
    );
  }
}

/// Το σχέδιο πηγών δεν διαβάστηκε με σιγουριά (π.χ. χαλασμένο αρχείο): οι νύχτες μένουν κενές, τίποτα δεν
/// γράφεται, και ο χρήστης διαλέγει στις Πηγές. Ποτέ σιωπηλά πίσω στο ρολόι.
class PlanUnknownCard extends StatelessWidget {
  const PlanUnknownCard({super.key, required this.onOpen});
  final VoidCallback onOpen;

  static bool shows(HealthStore s) => s.planState == PlanState.unknown;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return EmptyCard(
      key: const ValueKey('plan-unknown'),
      icon: Icons.device_unknown_rounded,
      color: c.bad,
      title: 'Δεν διαβάστηκε από πού έρχεται ο ύπνος',
      text: 'Οι ρυθμίσεις πηγών δεν διαβάστηκαν. Για να μη μπερδευτούν συσκευές, οι νύχτες μένουν κενές και δεν '
          'αποθηκεύεται τίποτα ώσπου να διαλέξεις.',
      buttonText: 'Διάλεξε πηγή',
      onPressed: onOpen,
    );
  }
}

/// «Τρίτη» κ.λπ. για τις κάρτες κατάστασης.
String weekdayFull(DateTime d) => longDate(d).split(' ').first;

/// Ο ύπνος της νύχτας από το Oura, στη Σήμερα.
class OuraSleepTodayCard extends StatelessWidget {
  const OuraSleepTodayCard({super.key, required this.store, required this.now, required this.onTap});
  final HealthStore store;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final today = dayOf(now);
    final night = store.ouraNightFor(today);
    final m = night?.main;
    const white = Colors.white;
    final soft = Colors.white.withValues(alpha: 0.8);

    Widget body;
    if (m == null) {
      final reason = store.ouraNightReason(today, now);
      body = Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          reason == null ? 'Δεν υπάρχουν δεδομένα από το δαχτυλίδι' : emptyNightText(reason),
          style: const TextStyle(color: white, fontSize: 20, fontWeight: FontWeight.w700),
        ),
      );
      // «Μόνο υπνάκος»: οι ώρες του φαίνονται (π.χ. σύντομη νύχτα που τελείωσε πριν από τα μεσάνυχτα).
      if (reason == EmptyNight.onlyNap && napTimes(night).isNotEmpty) {
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            const SizedBox(height: 6),
            Text(
              'Υπνάκος ${napTimes(night)} (δεν μετρά ως νύχτα)',
              key: const ValueKey('oura-only-nap-times'),
              style: TextStyle(color: soft, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ],
        );
      }
    } else {
      // Συνηθισμένη διάρκεια: μόνο από νύχτες του Oura (το ίδιο κομμάτι πηγής), τουλάχιστον 4.
      final usual = <double>[];
      final seg = store.plan.segmentStart(K.sleepMin, today);
      for (var i = 1; i <= 7; i++) {
        final d = DateTime(today.year, today.month, today.day - i);
        if (seg != null && d.isBefore(seg)) break;
        final v = store.plan.value(store.history, K.sleepMin, d);
        if (v != null) usual.add(v);
      }
      final base = usual.length >= minNightsForAverage ? usual.reduce((a, b) => a + b) / usual.length : null;
      final diff = base == null || m.totalMinutes == null ? null : m.totalMinutes! - base.round();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: m.totalMinutes == null
                    ? const Text('—', style: TextStyle(color: white, fontSize: 42, fontWeight: FontWeight.w800))
                    : DurationValue(m.totalMinutes!, size: 42, color: white, unitColor: soft),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  ScoreRing(
                    value: night!.sleepScore?.toDouble(),
                    size: 60,
                    stroke: 6,
                    color: c.ring,
                    track: Colors.white.withValues(alpha: 0.16),
                  ),
                  const SizedBox(height: 4),
                  EstimateNote('σκορ · εκτίμηση', onDark: true),
                ],
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Κοιμήθηκες ${m.onset == null ? '—' : hm(m.onset!)}',
                  style: TextStyle(color: soft, fontSize: 13.5, fontWeight: FontWeight.w600, fontFeatures: tabular),
                ),
              ),
              Text(
                'Ξύπνησες ${hm(m.end)}',
                style: TextStyle(color: soft, fontSize: 13.5, fontWeight: FontWeight.w600, fontFeatures: tabular),
              ),
            ],
          ),
          if (night.shortNight || night.pieces.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (night.shortNight) shortNightLabel,
                if (night.pieces.isNotEmpty) 'και άλλο κομμάτι ${hm(night.pieces.first.start)}–${hm(night.pieces.first.end)} (χωριστά)',
              ].join(' · '),
              style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ],
          if (night.naps.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Και υπνάκος ${hoursMinutes(night.napMinutes)} (χωριστά, δεν μετρά στη νύχτα)',
              style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ],
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppCard.radius),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.nightTop, c.nightBottom]),
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
                      child: Text('Ύπνος · χθες βράδυ', style: TextStyle(color: soft, fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    const SourceTag(Source.oura, onDark: true),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.6)),
                  ],
                ),
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Ξεκούραση στον ύπνο»: HRV, παλμοί, θερμοκρασία (μέσοι όροι όλης της νύχτας), και ετοιμότητα.
/// Όλα από το Oura, σε σύγκριση με τις 14 τελευταίες νύχτες σου από το Oura.
class OuraRestCard extends StatelessWidget {
  const OuraRestCard({super.key, required this.store, required this.now, required this.onTap});
  final HealthStore store;
  final DateTime now;
  final VoidCallback onTap;

  /// Αν η νύχτα έχει έστω μία από τις τιμές της κάρτας.
  static bool hasData(HealthStore s, DateTime now) =>
      [K.hrv, K.sleepHr, K.skinTemp, K.energy].any((k) => s.plan.value(s.history, k, dayOf(now)) != null);

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final day = dayOf(now);
    final plan = store.plan;
    final hrv = ouraBaseline(store.history, plan, K.hrv, day);
    final hr = ouraBaseline(store.history, plan, K.sleepHr, day);
    final temp = plan.value(store.history, K.skinTemp, day);
    final readiness = plan.value(store.history, K.energy, day);

    String note(NightBaseline? b, {required double same, String up = 'πάνω', String down = 'κάτω'}) {
      if (b == null) return '—';
      if (b.usual == null) return 'μαθαίνει';
      final d = b.diff!;
      if (d.abs() < same) return 'συνηθισμένο';
      return '${d.abs().round()} ${d > 0 ? up : down}';
    }

    Widget cell(String label, String value, String unit, String sub) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: c.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: BigValue(value, unit: unit, size: 22),
              ),
              Text(sub, style: TextStyle(color: c.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text('Ξεκούραση στον ύπνο', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text))),
            const SourceTag(Source.oura),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            cell('HRV', hrv == null ? '—' : '${hrv.value.round()}', 'ms', note(hrv, same: 3)),
            cell('Παλμοί στον ύπνο', hr == null ? '—' : '${hr.value.round()}', 'bpm', note(hr, same: 2)),
            cell(
              'Θερμοκρασία',
              temp == null ? '—' : signedDec(temp),
              '°C',
              temp == null ? '—' : (temp.abs() < 0.3 ? 'συνηθισμένη' : (temp > 0 ? 'πιο ζεστά' : 'πιο κρύα')),
            ),
          ]),
          const Hairline(vertical: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ετοιμότητα', style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                    const EstimateNote('εκτίμηση του Oura, όχι μέτρηση'),
                  ],
                ),
              ),
              Text(
                readiness == null ? '—' : '${readiness.round()}',
                style: TextStyle(color: c.text, fontSize: 24, fontWeight: FontWeight.w800, fontFeatures: tabular),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Μέσοι όροι όλης της νύχτας, σε σύγκριση με τις 14 τελευταίες νύχτες σου.',
            style: TextStyle(color: c.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
