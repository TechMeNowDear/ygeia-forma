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
    // Σφάλμα με παλιά δεδομένα στην οθόνη: λέμε ως πότε είναι (έλεγχος UX U5· ποτέ «χθες βράδυ» για παλιά νύχτα).
    final synced = store.ouraLastSync;
    final syncedText = synced == null ? '' : ' Ό,τι βλέπεις ήρθε ως τον τελευταίο συγχρονισμό, ${shortDayDate(synced)} ${hm(synced)}.';
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
      OuraStatus.missing when napTimes(store.ouraNightFor(dayOf(now)), nightOnly: true).isNotEmpty => (
          'Χθες βράδυ μόνο υπνάκος από το δαχτυλίδι',
          'Υπνάκος ${napTimes(store.ouraNightFor(dayOf(now)), nightOnly: true)}. Δεν μετρά ως νύχτα: η νύχτα μένει κενή στον Ύπνο και '
              'στις Τάσεις. Το οξυγόνο από το ρολόι φαίνεται κανονικά.',
          c.textSecondary,
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
          store.canWatchLastNight && now.hour >= 4 ? 'Ρυθμίσεις Oura' : null,
        ),
      OuraStatus.incomplete => (
          'Η σύνδεση δεν ολοκληρώθηκε',
          'Η σύνδεση με το Oura έμεινε μισή και δεν άλλαξε τίποτα. Δοκίμασε ξανά.',
          c.textSecondary,
          'Σύνδεση με Oura',
        ),
      OuraStatus.reconnect when store.ouraError == OuraErrorKind.scopeMissing => (
          'Λείπει άδεια στην Oura',
          'Η Oura δεν δίνει τον ύπνο με την άδεια που δόθηκε. Σύνδεσε ξανά και τσέκαρε την άδεια για τον ύπνο.',
          c.bad,
          'Σύνδεση ξανά',
        ),
      OuraStatus.reconnect => (
          'Χρειάζεται νέα σύνδεση με το Oura',
          'Γίνεται μετά από αλλαγή κινητού ή αν αφαιρέσεις την άδεια στην Oura. Δεν χάνεται τίποτα· οι νύχτες που '
              'έλειψαν έρχονται μετά.$syncedText',
          c.bad,
          'Σύνδεση ξανά',
        ),
      OuraStatus.subscription => (
          'Η Oura δεν δίνει νέα δεδομένα',
          '${ouraErrorText(OuraErrorKind.subscription)}$syncedText',
          c.bad,
          null,
        ),
      OuraStatus.disconnected => (
          'Ο ύπνος δεν έχει πηγή',
          'Το Oura αποσυνδέθηκε. Οι νύχτες μένουν κενές ώσπου να το συνδέσεις ξανά ή να διαλέξεις το ρολόι.',
          c.textSecondary,
          'Ρυθμίσεις Oura',
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
      // Η τελευταία νύχτα που ήρθε, ΜΕ την ημερομηνία της (έλεγχος UX U5): ποτέ ως «χθες βράδυ».
      final older = store.lastOuraNight;
      final olderMinutes = older == null || sameDay(older.day, today) ? null : older.nightMinutes;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              reason == null ? 'Δεν υπάρχουν δεδομένα από το δαχτυλίδι' : emptyNightText(reason),
              style: const TextStyle(color: white, fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          if (olderMinutes != null) ...[
            const SizedBox(height: 6),
            Text(
              'Τελευταία νύχτα που ήρθε: ${shortDayDate(older!.day)} · ${hoursMinutes(olderMinutes)}',
              key: const ValueKey('oura-today-older-night'),
              style: TextStyle(color: soft, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      );
      // «Μόνο υπνάκος»: οι ώρες του φαίνονται (π.χ. λαγοκοίμισμα που τελείωσε ως τις 22:00).
      if (reason == EmptyNight.onlyNap && napTimes(night, nightOnly: true).isNotEmpty) {
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            const SizedBox(height: 6),
            Text(
              'Υπνάκος ${napTimes(night, nightOnly: true)} (δεν μετρά ως νύχτα)',
              key: const ValueKey('oura-only-nap-times'),
              style: TextStyle(color: soft, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ],
        );
      }
    } else {
      // Συνηθισμένη διάρκεια: ο ίδιος κανόνας «συνήθως» με όλη την εφαρμογή (μεσαία τιμή έως 14 προηγούμενων νυχτών,
      // τουλάχιστον 7), μόνο από νύχτες του Oura του ίδιου κομματιού πηγής (έλεγχος υπολογισμών C7, D9).
      final minutes = night!.nightMinutes;
      final base = ouraBaseline(store.history, store.plan, K.sleepMin, today)?.usual;
      final diff = base == null || minutes == null ? null : minutes - base.round();
      final parts = night.counted;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: minutes == null
                    ? const Text('—', style: TextStyle(color: white, fontSize: 42, fontWeight: FontWeight.w800))
                    : DurationValue(minutes, size: 42, color: white, unitColor: soft),
              ),
              // Χωρίς βαθμολογία από την Oura: χωρίς άδειο δαχτυλίδι «—» (έλεγχος UX U8, ίδιο με το ρολόι).
              if (night.sleepScore != null) ...[
                const SizedBox(width: 12),
                Column(
                  children: [
                    ScoreRing(
                      value: night.sleepScore!.toDouble(),
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
                  'Κοιμήθηκες ${parts.first.onset == null ? '—' : hm(parts.first.onset!)}',
                  style: TextStyle(color: soft, fontSize: 13.5, fontWeight: FontWeight.w600, fontFeatures: tabular),
                ),
              ),
              Text(
                'Ξύπνησες ${hm(parts.last.end)}',
                style: TextStyle(color: soft, fontSize: 13.5, fontWeight: FontWeight.w600, fontFeatures: tabular),
              ),
            ],
          ),
          if (night.shortNight || night.pieces.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (night.shortNight && (minutes ?? 0) < 180) shortNightLabel,
                if (parts.length > 1) 'σε ${parts.length} κομμάτια: ${[for (final p in parts) '${hm(p.start)}–${hm(p.end)}'].join(' και ')} (το κενό δεν μετρά)',
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

/// «Καρδιά και θερμοκρασία στον ύπνο»: HRV, παλμοί, θερμοκρασία (μέσοι όροι όλης της νύχτας), και ετοιμότητα.
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

    // Ίδια λέξη «συνήθως» και η διαφορά των νούμερων όπως φαίνονται (έλεγχος υπολογισμών C6/C7, UX U7).
    String note(NightBaseline? b, {required double same}) {
      if (b == null) return '—';
      if (b.usual == null) return 'μαθαίνει';
      final d = b.value.round() - b.usual!.round();
      if (d.abs() < same) return 'όπως συνήθως';
      return 'συνήθως ${b.usual!.round()}';
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
            // Κλινικός έλεγχος M8 (4/11): όχι «ξεκούραση»· HRV και θερμοκρασία δεν είναι επικυρωμένοι δείκτες ανάρρωσης.
            Expanded(child: Text('Καρδιά και θερμοκρασία στον ύπνο', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text))),
            const SourceTag(Source.oura),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            cell('HRV (RMSSD)', hrv == null ? '—' : '${hrv.value.round()}', 'ms', note(hrv, same: 3)),
            cell('Παλμοί στον ύπνο', hr == null ? '—' : '${hr.value.round()}', 'bpm', note(hr, same: 2)),
            // Πάντα ως απόκλιση από το συνηθισμένο, ποτέ σαν θερμοκρασία σώματος (κλινικός έλεγχος M7, UX U4).
            cell(
              'Θερμοκρασία',
              temp == null ? '—' : signedDec(temp),
              '°C',
              temp == null ? '—' : 'απόκλιση από το συνηθισμένο',
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
