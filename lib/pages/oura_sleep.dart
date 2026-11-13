import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../hrv_trend.dart';
import '../oura/oura_model.dart';
import '../oura/oura_store.dart';
import '../oura/oura_view.dart';
import '../oxygen_note.dart';
import '../reference.dart';
import '../shown.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import 'info_sheet.dart';
import 'metric_page.dart';
import 'oura_pages.dart';
import 'oxygen_widgets.dart';
import 'source_widgets.dart';
import 'sources_page.dart';

/// Ο λόγος που η χθεσινή νύχτα είναι κενή (null = υπάρχει).
EmptyNight? lastNightReason(HealthStore s, DateTime now) => s.ouraNightReason(dayOf(now), now);

/// Round 1 (U2a-04): η ΜΙΑ ενέργεια για κάθε λόγο κενής νύχτας: (κείμενο κουμπιού, τι κάνει). null = δεν υπάρχει
/// κάτι να κάνεις. «Ενημέρωση τώρα» = ρητή ανάγνωση (S5-10: χωρίς το όριο των 30 λεπτών), μαζί με τη Samsung.
(String, VoidCallback)? emptyNightAction(BuildContext context, HealthStore store, EmptyNight? reason, DateTime? now) =>
    switch (reason) {
      EmptyNight.reconnect => (
          'Σύνδεση ξανά',
          () {
            Navigator.of(context)
                .push(store.ouraConfigured ? OuraConnectPage.route(store, now: now) : OuraManagePage.route(store, now: now));
          },
        ),
      EmptyNight.subscription => (
          'Ρυθμίσεις Oura',
          () {
            Navigator.of(context).push(OuraManagePage.route(store, now: now));
          },
        ),
      // Μετά το «Ο ύπνος ξανά από το ρολόι» δεν μένει τίποτα να γίνει (U2b-09).
      EmptyNight.disconnected when store.watchSleepFromTonight => null,
      EmptyNight.disconnected => (
          'Ρυθμίσεις Oura',
          () {
            Navigator.of(context).push(OuraManagePage.route(store, now: now));
          },
        ),
      EmptyNight.unknownPlan => (
          'Διάλεξε πηγή',
          () {
            Navigator.of(context).push(SourcesPage.route(store, now: now));
          },
        ),
      EmptyNight.waiting || EmptyNight.notRead || EmptyNight.noRing || EmptyNight.onlyNap => (
          'Ενημέρωση τώρα',
          () {
            store.refresh();
          },
        ),
      _ => null,
    };

/// Υγεία › Ύπνος όταν ο ύπνος έρχεται από το Oura (ή δεν έχει πηγή μετά την αποσύνδεση).
class OuraSleepPage extends StatelessWidget {
  const OuraSleepPage({super.key, required this.store, this.now});
  final HealthStore store;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final now = this.now ?? DateTime.now();
    final today = dayOf(now);
    final plan = store.plan;
    final last = store.lastOuraNight != null && plan.nightSource(store.lastOuraNight!.day) == Source.oura
        ? store.lastOuraNight
        : null;
    final reason = lastNightReason(store, now);
    // Round 1 (U2a-04): κάθε λόγος με τη μία ενέργειά του (κουμπί).
    final action = emptyNightAction(context, store, reason, this.now);

    final lastCard = last == null
        ? _EmptyNightCard(
            reason: reason ?? EmptyNight.noRing,
            day: today,
            night: store.ouraNightFor(today),
            watchTonight: store.watchSleepFromTonight,
            action: reason == null ? null : action)
        : _OuraNightCard(
            night: last,
            now: now,
            // S5-2: πριν από τις 04:00 η νύχτα με τη σημερινή ημερομηνία δεν έχει τελειώσει: δεν «λείπει» τίποτα.
            reason: sameDay(last.day, today) || reason == EmptyNight.notYet ? null : reason,
            watchTonight: store.watchSleepFromTonight,
            action: action,
            todayNight: store.ouraNightFor(today),
            range: sleepRange(store.profile, today),
            readiness: plan.value(store.history, K.energy, last.day),
            onHistory: () => Navigator.of(context).push(OuraNightsPage.route(store, now: this.now)),
            onMetric: (k) => Navigator.of(context).push(MetricPage.route(store, k, now: this.now)));

    final heart = _OuraRestCard(store: store, day: last?.day ?? today, now: now);
    final breath = _BreathCard(store: store, day: last?.day ?? today, now: now);

    // Χωρίς τελευταία νύχτα: ο δρόμος για τις 30 νύχτες μένει (έλεγχος premium, S2).
    final history = last != null
        ? null
        : AppCard(
            padding: EdgeInsets.zero,
            child: NavRow(
              key: const ValueKey('sleep-30-nights'),
              icon: Icons.calendar_month_rounded,
              color: c.sleep,
              title: 'Ύπνος 30 νυχτών',
              onTap: () => Navigator.of(context).push(OuraNightsPage.route(store, now: this.now)),
            ),
          );

    return PageFrame(
      title: 'Ύπνος',
      subtitle: plan.nightSource(today) == Source.none ? 'Το Oura δεν είναι συνδεδεμένο' : 'Από το Oura Ring 5',
      onRefresh: () => store.refresh(),
      // Σχέδια 9/11 (2α): η σελίδα όπως ο πίνακας· οι φάσεις 7 νυχτών και η λίστα των νυχτών στο «Ύπνος 30 νυχτών ›».
      single: [lastCard, if (history != null) history, heart, breath],
      left: [lastCard, if (history != null) history, heart],
      right: [breath],
    );
  }
}

/// «Ύπνος 30 νυχτών» (έλεγχος premium, S2): γράφημα διάρκειας, φάσεις 7 νυχτών και κάθε νύχτα μία-μία.
class OuraNightsPage extends StatelessWidget {
  const OuraNightsPage({super.key, required this.store, this.now});
  final HealthStore store;
  final DateTime? now;

  static Route<void> route(HealthStore store, {DateTime? now}) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'Ύπνος 30 νυχτών'),
        builder: (_) => OuraNightsPage(store: store, now: now),
      );

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final now = this.now ?? DateTime.now();
    final today = dayOf(now);
    final plan = store.plan;
    final nights = store.ouraNights.where((n) => plan.nightSource(n.day) == Source.oura).toList();
    final stages = ouraStageAverages(nights, today, plan);
    // Σχέδια 9/11 (4β): μία ετικέτα «εκτίμηση» στον τίτλο και ⓘ για το «γιατί», αντί για παράγραφο.
    final stagesCard = AppCard(
      key: const ValueKey('sleep-stages'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TitleRow(
            // Round 1 (U2a-11): το «7 νυχτών» δεν σπάει σε δύο γραμμές.
            header: CardHeader(icon: Icons.layers_rounded, title: 'Φάσεις · μέσος όρος ${glued('7 νυχτών')}', color: c.sleep),
            trailing: const [LabelTag('εκτίμηση'), InfoButton(stagesInfoKey)],
          ),
          const SizedBox(height: 12),
          if (stages.deep == null)
            Text(
              'Χρειάζονται τουλάχιστον $minNightsForAverage νύχτες με το δαχτυλίδι μέσα σε μία εβδομάδα '
              '(τώρα ${countText(stages.nights, 'νύχτα', 'νύχτες')}).',
              style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.4),
            )
          else ...[
            StackedBar(parts: [
              (stages.deep!.toDouble(), c.stage('DEEP')),
              (stages.light!.toDouble(), c.stage('LIGHT')),
              (stages.rem!.toDouble(), c.stage('REM')),
              (stages.awake!.toDouble(), c.stage('AWAKE')),
            ]),
            const SizedBox(height: 6),
            // Round 1 (U2a-02): διάρκειες με ολόκληρες λέξεις («1 ώρα 10 λεπτά»), όχι «1 ω 10 λ».
            InfoRow(stageLabel('DEEP'), hoursMinutes(stages.deep!), dot: c.stage('DEEP')),
            InfoRow(stageLabel('LIGHT'), hoursMinutes(stages.light!), dot: c.stage('LIGHT')),
            InfoRow(stageLabel('REM'), hoursMinutes(stages.rem!), dot: c.stage('REM')),
            // «τουλάχιστον»: τα ξυπνήματα μετριούνται λιγότερα απ' όσα είναι (το «γιατί» στο ⓘ).
            InfoRow('Ξύπνιος', atLeast(stages.awake!), dot: c.stage('AWAKE')),
          ],
        ],
      ),
    );

    final list = [
      const SectionHeader('Νύχτα προς νύχτα'),
      for (var i = 0; i < 30; i++)
        () {
          final d = DateTime(today.year, today.month, today.day - i);
          if (plan.nightSource(d) == Source.watch) return null;
          final n = store.ouraNightFor(d);
          final reason = n?.main != null ? null : store.ouraNightReason(d, now);
          // S5-2: πριν από τις 04:00 η νύχτα με τη σημερινή ημερομηνία δεν έχει γίνει ακόμα: καμία γραμμή γι' αυτήν.
          if (reason == EmptyNight.notYet) return null;
          return _NightLine(
            day: d,
            now: now,
            night: n,
            reason: reason,
          );
        }(),
    ].whereType<Widget>().toList();

    final chart = AppCard(
      padding: EdgeInsets.zero,
      child: NavRow(
        key: const ValueKey('sleep-duration-chart'),
        icon: Icons.show_chart_rounded,
        color: c.sleep,
        title: 'Διάρκεια ύπνου, γράφημα',
        onTap: () => Navigator.of(context).push(MetricPage.route(store, K.sleepMin, now: this.now)),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Ύπνος 30 νυχτών')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                chart,
                const SizedBox(height: 12),
                stagesCard,
                const SizedBox(height: 16),
                for (final w in list) Padding(padding: const EdgeInsets.only(bottom: 10), child: w),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyNightCard extends StatelessWidget {
  const _EmptyNightCard({required this.reason, required this.day, this.night, this.watchTonight = false, this.action});
  final EmptyNight reason;
  final DateTime day;

  /// Για «Μόνο υπνάκος»: οι ώρες του υπνάκου.
  final OuraNight? night;

  /// Μετά την αποσύνδεση διάλεξε ρητά «από απόψε το ρολόι» (U2b-09).
  final bool watchTonight;

  /// Η μία ενέργεια αυτής της κατάστασης ([emptyNightAction])· null = καμία.
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    // Round 1 (U2a-03 / U2a-04 / U2a-13): κάθε κείμενο λέει τι ισχύει και τι να κάνεις· χωρίς νύχτα από το δαχτυλίδι
    // το οξυγόνο της νύχτας ΔΕΝ φαίνεται (πριν: «οξυγόνο από το ρολόι φαίνεται κανονικά»).
    final text = switch (reason) {
      EmptyNight.waiting => 'Η χθεσινή νύχτα δεν έχει φτάσει ακόμα. Άνοιξε την εφαρμογή Oura για να συγχρονίσει, και μετά γύρνα εδώ.',
      EmptyNight.noRing => 'Η νύχτα μένει κενή στον Ύπνο και στις Τάσεις, και το οξυγόνο της νύχτας μένει κενό, γιατί χωρίς νύχτα '
          'από το δαχτυλίδι δεν ξέρουμε πότε κοιμήθηκες. Αν το φορούσες, άνοιξε την εφαρμογή Oura για να συγχρονίσει και μετά '
          'γύρνα εδώ.',
      EmptyNight.reconnect => 'Το Oura χρειάζεται νέα σύνδεση: πάτα «Σύνδεση ξανά». Δεν χάνεται τίποτα· οι νύχτες έρχονται μετά.',
      EmptyNight.subscription => 'Η Oura δεν δίνει τον ύπνο: η συνδρομή Oura δεν είναι ενεργή ή λείπει η άδεια για τον ύπνο. '
          'Έλεγξε τη συνδρομή στην εφαρμογή Oura και μετά άνοιξε τις «Ρυθμίσεις Oura».',
      EmptyNight.notRead => 'Δεν έγινε ακόμα ανάγνωση από την Oura. Πάτα «Ενημέρωση τώρα» ή τράβηξε προς τα κάτω για να ξαναδοκιμάσεις.',
      EmptyNight.disconnected => watchTonight
          ? 'Το Oura αποσυνδέθηκε. Από απόψε ο ύπνος έρχεται από το ρολόι, όπως διάλεξες.'
          : 'Οι νύχτες μένουν κενές ώσπου να συνδέσεις ξανά το Oura ή να διαλέξεις το ρολόι, στις «Ρυθμίσεις Oura».',
      EmptyNight.onlyNap => 'Το δαχτυλίδι κατέγραψε μόνο υπνάκο, όχι νύχτα'
          '${napTimes(night).isEmpty ? '' : ': ${napTimes(night)}'}. Ο υπνάκος δεν μετρά ως νύχτα.',
      EmptyNight.unknownPlan => 'Οι ρυθμίσεις πηγών δεν διαβάστηκαν. Για να μην μπερδευτούν οι συσκευές, οι νύχτες μένουν κενές '
          'ώσπου να διαλέξεις πηγή.',
      EmptyNight.notYet => 'Η νύχτα φαίνεται εδώ το πρωί, όταν ξυπνήσεις και συγχρονίσει η εφαρμογή Oura.',
      EmptyNight.notOura => '',
    };
    return EmptyCard(
      icon: Icons.bedtime_rounded,
      color: c.sleep,
      title: emptyNightText(reason),
      text: text,
      buttonText: action?.$1,
      onPressed: action?.$2,
    );
  }
}

class _OuraNightCard extends StatelessWidget {
  const _OuraNightCard(
      {required this.night,
      required this.now,
      this.reason,
      this.watchTonight = false,
      this.action,
      this.todayNight,
      this.range,
      this.readiness,
      this.onHistory,
      this.onMetric});

  /// Μετά την αποσύνδεση διάλεξε ρητά «από απόψε το ρολόι» (U2b-09).
  final bool watchTonight;

  /// Η μία ενέργεια για τον λόγο που λείπει η χθεσινή νύχτα ([emptyNightAction])· null = καμία.
  final (String, VoidCallback)? action;

  /// Πάτημα σε δαχτυλίδι: οι 30 νύχτες της μέτρησης (έλεγχος premium, S9).
  final void Function(String metric)? onMetric;
  final OuraNight night;

  /// Ετοιμότητα του Oura για την ίδια μέρα (σχέδια 9/11: η «Ανάκαμψη» μοιράστηκε στον Ύπνο).
  final double? readiness;

  /// «Ύπνος 30 νυχτών ›».
  final VoidCallback? onHistory;

  /// 7/11: το εύρος αναφοράς του ύπνου (≥ 7 ώρες για ενήλικες), αν ισχύει για την ηλικία.
  final RefRange? range;

  /// Η χθεσινή (π.χ. μόνο υπνάκος), για να φαίνονται οι ώρες της.
  final OuraNight? todayNight;
  final DateTime now;

  /// Αν αυτή δεν είναι η χθεσινή νύχτα: γιατί λείπει η χθεσινή.
  final EmptyNight? reason;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final n = night.toNight()!;
    // Νύχτα σε κομμάτια (ως 4 ώρες κενό): μετρούν όλα μαζί, το κενό όχι (δεύτερος γύρος ελέγχου, U12).
    final parts = night.counted;
    final minutes = night.nightMinutes;
    Widget clock(String label, String v) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: c.textSecondary, fontSize: 13)),
              Text(
                v,
                style: TextStyle(color: c.text, fontSize: 20, fontWeight: FontWeight.w700, fontFeatures: tabular),
              ),
            ],
          ),
        );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (reason != null) ...[
            // Round 1 (U2a-06 / U2a-04): ολόκληρη πρόταση για κάθε λόγο (πριν: «… για χθες βράδυ» κολλημένο σε κάθε
            // τίτλο), κόκκινο μόνο όταν κάτι θέλει διόρθωση (σύνδεση, άδεια/συνδρομή, πηγές), και η μία ενέργεια.
            Text(
              '${lastNightNote(reason!, nap: napTimes(todayNight, nightOnly: true), watchTonight: watchTonight)} '
              'Κάτω βλέπεις την τελευταία νύχτα που ήρθε.',
              key: const ValueKey('oura-last-night-note'),
              style: TextStyle(
                  color: switch (reason!) {
                    EmptyNight.reconnect || EmptyNight.subscription || EmptyNight.unknownPlan => c.bad,
                    EmptyNight.notRead => c.warn,
                    _ => c.textSecondary,
                  },
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35),
            ),
            if (action != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('oura-last-night-action'),
                  onPressed: action!.$2,
                  child: Text(action!.$1),
                ),
              )
            else
              const SizedBox(height: 10),
          ],
          TitleRow(
            // Round 1 (U2a-11): η ημερομηνία σε δική της γραμμή κάτω από τον τίτλο (πριν έσπαγε: «· Σάβ / 14/11»).
            header: CardHeader(
                icon: Icons.bedtime_rounded, title: 'Τελευταία νύχτα', subtitle: shortDayDate(night.day), color: c.sleep),
            trailing: [const SourceTag(Source.oura), InfoButton(K.sleepMin, range: range)],
          ),
          if (night.shortNight && (minutes ?? 0) < 180) ...[
            const SizedBox(height: 8),
            Text(shortNightLabel,
                key: const ValueKey('oura-short-night'),
                style: TextStyle(color: c.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 14),
          minutes == null
              ? Text('—', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: c.text))
              : DurationValue(minutes, size: 44),
          // Σχέδια 9/11 (2α): δύο δαχτυλίδια δίπλα δίπλα, Βαθμολογία ύπνου και Ετοιμότητα για σήμερα (με μεγάλα
          // γράμματα το ένα κάτω από το άλλο). Χωρίς τιμή: χωρίς άδειο δαχτυλίδι (έλεγχος UX U8).
          if (night.sleepScore != null || readiness != null) ...[
            const SizedBox(height: 14),
            _RingTiles(onTap: onMetric, tiles: [
              if (night.sleepScore != null) (night.sleepScore!.toDouble(), 'Βαθμολογία', 'ύπνου', 'sleep-score'),
              // Round 1 (S5-4): «για σήμερα» μόνο όταν η τιμή είναι της σημερινής μέρας· αλλιώς η μέρα της.
              if (readiness != null)
                (
                  readiness!,
                  'Ετοιμότητα',
                  sameDay(night.day, now) ? 'για σήμερα' : 'για ${shortDayDate(night.day)}',
                  'sleep-readiness',
                ),
            ]),
          ],
          if (minutes != null && range != null) ...[
            const SizedBox(height: 12),
            if (range!.low == null)
              RangeNote(value: minutes.toDouble(), range: range!, min: 180, max: 600, color: c.sleep, oneNight: true)
            else ...[
              // Round 1 (S4-5): η σύσταση «τουλάχιστον 7 ώρες» βγήκε από ώρες που ΔΗΛΩΝΑΝ οι άνθρωποι· το δαχτυλίδι
              // μετρά μόνο τον ύπνο, χωρίς τα ξυπνήματα. Η πρόταση δείχνει ύπνο ΚΑΙ χρόνο στο κρεβάτι και δεν γράφει
              // «κάτω από το εύρος» όταν ο χρόνος στο κρεβάτι φτάνει τη σύσταση ([sleepVsAdvice]).
              RangeBar(value: minutes.toDouble(), range: range!, min: 180, max: 600, color: c.sleep),
              const SizedBox(height: 6),
              Text(
                sleepVsAdvice(
                  asleepMin: minutes,
                  inBedMin: parts.every((p) => p.timeInBed != null)
                      ? (parts.fold<int>(0, (a, p) => a + p.timeInBed!) / 60).round()
                      : null,
                  adviceMin: range!.low!.round(),
                ),
                key: const ValueKey('oura-sleep-advice'),
                style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.35),
              ),
            ],
          ],
          const SizedBox(height: 14),
          // Τρεις στήλες όσο χωράει κάθε λέξη· αλλιώς γραμμές «ετικέτα … ώρα» (ποτέ «00:2/6»).
          LayoutBuilder(builder: (context, box) {
            // Σχέδια 9/11 (2α): Κοιμήθηκες · Ξύπνησες · Ξύπνιος (ο χρόνος ξύπνιος ΜΕΣΑ στον ύπνο).
            final awakeSec = parts.every((p) => p.awakeInSleep == null) ? null : parts.fold<int>(0, (a, p) => a + (p.awakeInSleep ?? 0));
            // Round 1 (S5-1): οι ώρες του τόπου όπου κοιμήθηκες. (U2a-02): «Ξύπνιος 22 λεπτά», όχι «22 λ»· αν η τιμή δεν
            // χωρά ολόκληρη στη στήλη της, γραμμές «ετικέτα … τιμή» (ποτέ σπασμένη τιμή).
            final items = [
              ('Κοιμήθηκες', parts.first.wallOnset == null ? '—' : hm(parts.first.wallOnset!)),
              ('Ξύπνησες', hm(parts.last.wallEnd)),
              ('Ξύπνιος', awakeSec == null ? '—' : hoursMinutes((awakeSec / 60).round())),
            ];
            final fits = wordsFit(context, [for (final i in items) i.$1], TextStyle(fontSize: 13, color: c.textSecondary), box.maxWidth / 3 - 4) &&
                wordsFit(context, [for (final i in items) glued(i.$2)],
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFeatures: tabular), box.maxWidth / 3 - 4);
            if (fits) return Row(children: [for (final i in items) clock(i.$1, glued(i.$2))]);
            return Column(children: [for (final i in items) InfoRow(i.$1, i.$2)]);
          }),
          if (n.stages.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text('Φάσεις', style: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w600))),
              const LabelTag('εκτίμηση'),
            ]),
            const SizedBox(height: 8),
            Hypnogram(night: n, height: 64),
            const SizedBox(height: 4),
            Row(children: [
              Text(hm(parts.first.wallStart), style: TextStyle(color: c.textTertiary, fontSize: 11.5)),
              const Spacer(),
              Text(hm(parts.last.wallEnd), style: TextStyle(color: c.textTertiary, fontSize: 11.5)),
            ]),
            const SizedBox(height: 6),
            // Round 1 (U2a-14): υπόμνημα, με τη σειρά των γραμμών από πάνω προς τα κάτω. Μόνο ονόματα, ποτέ λεπτά
            // μίας νύχτας (κανόνας 2/11).
            Wrap(key: const ValueKey('oura-hypno-legend'), spacing: 12, runSpacing: 4, children: [
              for (final name in const ['AWAKE', 'REM', 'LIGHT', 'DEEP'])
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: c.stage(name), shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(stageLabel(name), style: TextStyle(color: c.textSecondary, fontSize: 12)),
                ]),
            ]),
          ],
          if (parts.length > 1) ...[
            const Hairline(vertical: 12),
            for (final x in parts)
              InfoRow('Κομμάτι ${hm(x.wallStart)}–${hm(x.wallEnd)}', x.totalMinutes == null ? '—' : hoursMinutes(x.totalMinutes!)),
            // Round 1 (U2a-19): χωρίς κουκκίδα, στοιχισμένο με τις γραμμές «Κομμάτι» (με την κουκκίδα έσπαγε σε δύο γραμμές).
            InfoRow(
              'Κενό ανάμεσα (δεν μετρά)',
              hoursMinutes([for (var i = 1; i < parts.length; i++) parts[i].start.difference(parts[i - 1].end).inMinutes].fold(0, (a, b) => a + b)),
            ),
          ],
          if (night.naps.isNotEmpty || night.others.isNotEmpty) ...[
            const Hairline(vertical: 12),
            // Υπνάκοι κατά τον κοινό κανόνα με το ρολόι, και περίοδοι που επικαλύπτονται: χωριστά, δεν προστίθενται.
            for (final x in night.naps)
              InfoRow('Υπνάκος ${hm(x.wallStart)}–${hm(x.wallEnd)} (χωριστά)', x.totalMinutes == null ? '—' : hoursMinutes(x.totalMinutes!)),
            for (final x in night.others)
              InfoRow('Άλλος ύπνος ${hm(x.wallStart)}–${hm(x.wallEnd)} (χωριστά)', x.totalMinutes == null ? '—' : hoursMinutes(x.totalMinutes!)),
          ],
          if (onHistory != null) ...[
            // Round 1 (U2a-17): στόχος αφής 48 dp (12 + εικονίδιο 24 + 12)· πριν 40.
            const Hairline(vertical: 4),
            InkWell(
              key: const ValueKey('sleep-30-nights'),
              onTap: onHistory,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  Expanded(child: Text('Ύπνος 30 νυχτών', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.health))),
                  Icon(Icons.chevron_right_rounded, color: c.health),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Δαχτυλίδια βαθμολογίας σε απαλά πλακίδια: (τιμή, λέξη, δεύτερη λέξη, κλειδί).
class _RingTiles extends StatelessWidget {
  const _RingTiles({required this.tiles, this.onTap});
  final List<(double, String, String, String)> tiles;
  final void Function(String metric)? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final big = MediaQuery.textScalerOf(context).scale(10) > 13.5;
    Widget tile((double, String, String, String) t) => Material(
          color: c.tint(c.sleep),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
          key: ValueKey(t.$4),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap == null ? null : () => onTap!(t.$4 == 'sleep-score' ? K.sleepScore : K.energy),
          child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 6, 10),
          child: Row(children: [
            ScoreRing(value: t.$1, size: 44, stroke: 5, color: c.sleep, track: c.tint(c.sleep), textColor: c.text),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.$2, style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.25)),
                Text(t.$3, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text, height: 1.25)),
              ]),
            ),
          ]),
          ),
          ),
        );
    Widget stacked() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(height: 8), tile(tiles[i])],
        ]);
    if (big || tiles.length == 1) return stacked();
    // Round 1 (U2a-09): δίπλα δίπλα μόνο όταν κάθε ετικέτα χωρά ολόκληρη στη στήλη της (ανοιχτό Fold: στήλη 82 dp,
    // «για σήμερα» έσπαγε σε δύο γραμμές και στα 750 dp οι λέξεις στη μέση)· αλλιώς το ένα κάτω από το άλλο.
    return LayoutBuilder(builder: (context, box) {
      // Πλάτος για το κείμενο ενός πλακιδίου: μισό πλάτος μείον κενό (10), περιθώρια (8 + 6), δαχτυλίδι (44) και κενό (8).
      final slot = (box.maxWidth - 10) / 2 - 8 - 6 - 44 - 8;
      final fits = wordsFit(context, [for (final t in tiles) t.$2], const TextStyle(fontSize: 13, height: 1.25), slot) &&
          wordsFit(context, [for (final t in tiles) glued(t.$3)],
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25), slot);
      if (!fits) return stacked();
      return Row(children: [
        for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: tile(tiles[i]))],
      ]);
    });
  }
}

/// «Καρδιά και θερμοκρασία στον ύπνο» (σχέδια 9/11, 2α): HRV, παλμοί ύπνου, θερμοκρασία δέρματος, μόνο από το Oura,
/// σε σύγκριση με τις δικές σου 14 τελευταίες νύχτες. Κάθε γραμμή ανοίγει τις 30 νύχτες, άρα δεν χάνεται τίποτα από
/// την πρώην «Ανάκαμψη». Τίτλος: κλινικός έλεγχος M8 (4/11), όχι «ξεκούραση».
class _OuraRestCard extends StatelessWidget {
  const _OuraRestCard({required this.store, required this.day, required this.now});
  final HealthStore store;
  final DateTime day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final plan = store.plan;
    final hrv = ouraBaseline(store.history, plan, K.hrv, day);
    final hr = ouraBaseline(store.history, plan, K.sleepHr, day);
    final temp = plan.value(store.history, K.skinTemp, day);

    // Ίδιος κανόνας «συνήθως» με τη Σήμερα και την Καρδιά (τρίτος έλεγχος F1): βέλος + διαφορά, «συνήθως» σε γκρι.
    Widget? usual(NightBaseline? b) {
      if (b == null) return null;
      // Round 1 (U2a-15): η ίδια πρόταση με τις «Αναπνοές» της ίδιας οθόνης (λέει τι να περιμένεις).
      if (b.usual == null) {
        return Text('Το συνηθισμένο σου βγαίνει μετά από $minNightsForBaseline νύχτες',
            style: TextStyle(fontSize: 13, color: c.textSecondary));
      }
      final d = shownDiff(b.value, b.usual!);
      return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
        if (d != 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: c.tint(c.textSecondary), borderRadius: BorderRadius.circular(8)),
            child: Text('${d > 0 ? '↑' : '↓'} ${d.abs().round()}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary, fontFeatures: tabular)),
          ),
        Text(d == 0 ? 'όπως συνήθως (${b.usual!.round()})' : 'συνήθως ${b.usual!.round()}',
            style: TextStyle(fontSize: 13, color: c.textSecondary, fontFeatures: tabular)),
      ]);
    }

    // 13/11: κάτω από το «συνήθως», ο μέσος όρος 7 νυχτών απέναντι στο δικό σου εύρος (hrv_trend.dart). Μόνο περιγραφή.
    final trend = hrv == null ? null : hrvTrend(store.history, plan, day);
    Widget? hrvSub() {
      final u = usual(hrv);
      if (trend == null) return u;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (u != null) ...[u, const SizedBox(height: 3)],
        Text(hrvTrendText(trend), key: const ValueKey('sleep-hrv-trend'), style: TextStyle(fontSize: 13, color: c.textSecondary, fontFeatures: tabular)),
      ]);
    }

    Widget row(String metric, String label, String value, {Widget? sub, bool line = true}) => InkWell(
          key: ValueKey('sleep-rest-$metric'),
          onTap: () => Navigator.of(context).push(MetricPage.route(store, metric, now: now)),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: line ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Ετικέτα και τιμή (σχέδια 9/11, 9β). Round 1 (U1a-4 γ, αίτημα f4 → f5): η τιμή ΠΑΝΤΑ δεξιά. Η ετικέτα σπάει
              // σε γραμμές αν χρειαστεί και η τιμή μένει στην ίδια γραμμή βάσης· με πολύ μεγάλα γράμματα η τιμή πάει στην
              // επόμενη γραμμή, δεξιά (καμία λέξη δεν κόβεται). Πριν (Wrap) η τιμή που δεν χωρούσε έπεφτε ΑΡΙΣΤΕΡΑ, ενώ οι
              // άλλες της ίδιας κάρτας έμεναν δεξιά.
              if (veryLargeText(context))
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(label, style: TextStyle(fontSize: 15, color: c.text)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular)),
                  ),
                ])
              else
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: c.text))),
                  const SizedBox(width: 12),
                  Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular)),
                ]),
              if (sub != null) ...[const SizedBox(height: 3), sub],
            ]),
          ),
        );

    return AppCard(
      key: const ValueKey('sleep-rest'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TitleRow(
            // Round 1 (U2a-07): τιμές παλιότερης νύχτας (η χθεσινή δεν ήρθε ακόμα) με την ημερομηνία τους.
            header: CardHeader(
                icon: Icons.favorite_rounded,
                title: 'Καρδιά και θερμοκρασία στον ύπνο',
                subtitle: sameDay(day, now) ? null : shortDayDate(day),
                color: c.heart),
            trailing: const [SourceTag(Source.oura), InfoButton(K.hrv)],
          ),
          const SizedBox(height: 4),
          row(K.hrv, 'HRV', hrv == null ? '—' : '${hrv.value.round()} ms', sub: hrvSub()),
          // Round 1 (U1a-7, αίτημα f4 → f5): ίδια λέξη με Καρδιά, Σήμερα, Τάσεις, ⓘ («Παλμοί στον ύπνο», όχι «Παλμοί ύπνου»).
          row(K.sleepHr, 'Παλμοί στον ύπνο', hr == null ? '—' : '${hr.value.round()} bpm', sub: usual(hr)),
          row(K.skinTemp, 'Θερμοκρασία δέρματος', temp == null ? '—' : '${signedDec(temp)} °C',
              sub: Text(ouraTempDeviationLabel, style: TextStyle(fontSize: 13, color: c.textSecondary)), line: false),
        ],
      ),
    );
  }
}

/// Αναπνοή (Oura) και οξυγόνο (ρολόι): δύο γραμμές, κάθε μία με την πηγή της. Ποτέ μαζί σε μία τιμή.
class _BreathCard extends StatelessWidget {
  const _BreathCard({required this.store, required this.day, required this.now});
  final HealthStore store;
  final DateTime day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final plan = store.plan;
    final b = ouraBaseline(store.history, plan, K.breath, day);
    final windows = store.ouraWindows;
    final rox = ringOxygen(store, store.data, day, windows);
    // Σημειώσεις για χαμηλό οξυγόνο (B7) με τις τιμές του ορισμού A4: ρολόι μέσα στις ώρες ύπνου του Oura· όλες οι 30
    // νύχτες, και πριν από τη σύνδεση (έλεγχος 3, E5: ίδιος αισθητήρας, όπως η αναφορά).
    final g = oxygenGuidance(
      store.data?.spo2MinByNight(day, ouraNights: true, windows: windows, history: store.history) ?? const {},
      day,
      today: now,
    );

    Widget row(String title, String sub, Source s) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text)),
                    const SizedBox(height: 2),
                    Text(sub, style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SourceTag(s),
            ],
          ),
        );

    // Η ίδια λέξη «συνήθως» και η διαφορά των νούμερων όπως φαίνονται (έλεγχος υπολογισμών C6/C7).
    String breathNote() {
      if (b == null) return 'Δεν υπάρχει για αυτή τη νύχτα';
      if (b.usual == null) return 'Το συνηθισμένο σου βγαίνει μετά από $minNightsForBaseline νύχτες';
      // Τρίτος έλεγχος F1: «Όπως συνήθως» μόνο για διαφορά 0 (πριν: ως ±0,9, που φαινόταν ως διαφορά).
      final d = shownDiff(b.value, b.usual!, 1);
      if (d == 0) return '$asUsualText (${dec(b.usual!)})';
      return '${signedShown(d, 1)} · συνήθως ${dec(b.usual!)}';
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            icon: Icons.air_rounded,
            title: 'Αναπνοή και οξυγόνο τη νύχτα',
            // Round 1 (U2a-07): τιμές παλιότερης νύχτας με την ημερομηνία τους.
            subtitle: sameDay(day, now) ? null : shortDayDate(day),
            color: c.sleep,
            trailing: const InfoButton(K.ringSpo2),
          ),
          const SizedBox(height: 6),
          InkWell(
            key: const ValueKey('sleep-breath'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.of(context).push(MetricPage.route(store, K.breath, now: now)),
            child: row(b == null ? 'Αναπνοές —' : 'Αναπνοές ${dec(b.value)} το λεπτό', breathNote(), Source.oura),
          ),
          const Hairline(vertical: 2),
          row(
            // Έλεγχος 9/11 (UX3-05): οι ίδιες δύο ετικέτες παντού.
            // Round 1 (U2a-11): η τιμή δεν μένει μόνη της στην επόμενη γραμμή («μέσος όρος / 96%»).
            gluedAfterComma(rox.avg == null ? '$oxygenAvgLabel —' : '$oxygenAvgLabel ${spo2AvgText(rox.avg!)}%'),
            rox.avg == null
                ? (windows.mains.containsKey(dateKey(day)) ? ringAvgMissing(store) : 'Χωρίς νύχτα από το δαχτυλίδι')
                : 'Όλη τη νύχτα',
            Source.oura,
          ),
          const Hairline(vertical: 2),
          // 7/11: η χαμηλότερη από το ρολόι, μόνο με κάλυψη ≥ 50% του ύπνου του Oura.
          row(
            gluedAfterComma(rox.min == null ? '$oxygenMinLabel —' : '$oxygenMinLabel ${lowestText(rox.min!)}%'),
            windows.mains.containsKey(dateKey(day))
                ? watchLowText(rox.watch)
                : 'Χωρίς νύχτα από το δαχτυλίδι δεν ξέρουμε πότε κοιμήθηκες',
            Source.watch,
          ),
          const SizedBox(height: 6),
          // Κλινικός έλεγχος C1/M3 (4/11): το τεστ άπνοιας του ρολογιού είναι διαλογή· το πλήρες κείμενο με «Τι σημαίνει».
          const OxygenAbout(),
          const SizedBox(height: 4),
          OxygenNotes(guidance: g),
        ],
      ),
    );
  }
}

class _NightLine extends StatelessWidget {
  const _NightLine({required this.day, required this.now, required this.night, required this.reason});
  final DateTime day;
  final DateTime now;
  final OuraNight? night;
  final EmptyNight? reason;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final m = night?.main;
    final n = night?.toNight();
    final minutes = night?.nightMinutes;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                    Text(
                      sameDay(day, now) ? 'Χθες βράδυ' : shortDayDate(day),
                      style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // Τελικός έλεγχος: μέρα με μόνο υπνάκο: οι ώρες και το σύνολο, ποτέ «χωρίς ύπνο».
                      m == null && reason == EmptyNight.onlyNap && napTimes(night).isNotEmpty
                          ? '${night!.naps.length == 1 ? 'Υπνάκος' : 'Υπνάκοι'} ${napTimes(night)}'
                          : m == null
                          ? emptyNightText(reason ?? EmptyNight.noRing)
                          : '${hm(night!.counted.first.wallOnset ?? night!.counted.first.wallStart)} – ${hm(night!.counted.last.wallEnd)}'
                              '${night!.counted.length > 1 ? ' · ${night!.counted.length} κομμάτια' : ''}',
                      style: TextStyle(color: c.textSecondary, fontSize: 13.5, fontFeatures: tabular),
                    ),
                  ],
                ),
              ),
              if (m == null && reason == EmptyNight.onlyNap)
                Text('Μόνο υπνάκος', style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
              if (m != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      minutes == null ? '—' : hoursMinutes(minutes),
                      style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 15, fontFeatures: tabular),
                    ),
                    if (night!.sleepScore != null)
                      // Round 1 (U2a-15): «βαθμολογία», όπως παντού αλλού.
                      Text('βαθμολογία ${night!.sleepScore}', style: TextStyle(color: c.sleep, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),
          if (n != null && n.stages.isNotEmpty) ...[
            const SizedBox(height: 10),
            StageTimeline(night: n, height: 8),
          ],
        ],
      ),
    );
  }
}

/// Για την κάρτα της Σήμερα: η κατάσταση του Oura σε μία γραμμή.
String ouraStatusLine(OuraStatus s) => switch (s) {
      OuraStatus.waiting || OuraStatus.startingNow => 'Περιμένει το Oura',
      OuraStatus.missing => 'Χωρίς ύπνο από το δαχτυλίδι',
      OuraStatus.reconnect => 'Χρειάζεται νέα σύνδεση',
      OuraStatus.subscription => 'Η συνδρομή Oura δεν είναι ενεργή',
      OuraStatus.disconnected => 'Το Oura δεν είναι συνδεδεμένο',
      _ => '',
    };
