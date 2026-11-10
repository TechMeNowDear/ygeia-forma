import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
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
import 'oxygen_widgets.dart';
import 'source_widgets.dart';

/// Ο λόγος που η χθεσινή νύχτα είναι κενή (null = υπάρχει).
EmptyNight? lastNightReason(HealthStore s, DateTime now) => s.ouraNightReason(dayOf(now), now);

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

    final lastCard = last == null
        ? _EmptyNightCard(reason: reason ?? EmptyNight.noRing, day: today, night: store.ouraNightFor(today))
        : _OuraNightCard(
            night: last,
            now: now,
            reason: sameDay(last.day, today) ? null : reason,
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
            header: CardHeader(icon: Icons.layers_rounded, title: 'Φάσεις · μέσος όρος 7 νυχτών', color: c.sleep),
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
            InfoRow(stageLabel('DEEP'), hmList(stages.deep!), dot: c.stage('DEEP')),
            InfoRow(stageLabel('LIGHT'), hmList(stages.light!), dot: c.stage('LIGHT')),
            InfoRow(stageLabel('REM'), hmList(stages.rem!), dot: c.stage('REM')),
            // «≥»: τα ξυπνήματα μετριούνται λιγότερα απ' όσα είναι (το «γιατί» στο ⓘ).
            InfoRow('Ξύπνιος', '≥ ${hmList(stages.awake!)}', dot: c.stage('AWAKE')),
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
          return _NightLine(
            day: d,
            now: now,
            night: n,
            reason: n?.main != null
                ? null
                : store.ouraNightReason(d, now),
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
  const _EmptyNightCard({required this.reason, required this.day, this.night});
  final EmptyNight reason;
  final DateTime day;

  /// Για «Μόνο υπνάκος»: οι ώρες του υπνάκου.
  final OuraNight? night;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final text = switch (reason) {
      EmptyNight.waiting => 'Η χθεσινή νύχτα δεν έχει φτάσει ακόμα. Άνοιξε την εφαρμογή Oura για να συγχρονίσει, και μετά γύρνα εδώ.',
      EmptyNight.noRing => 'Η νύχτα μένει κενή στον Ύπνο και στις Τάσεις. Οξυγόνο από το ρολόι φαίνεται κανονικά στην Καρδιά.',
      EmptyNight.reconnect => 'Η σύνδεση με το Oura χρειάζεται ανανέωση. Δεν χάνεται τίποτα· οι νύχτες έρχονται μετά.',
      EmptyNight.subscription => 'Χωρίς ενεργή συνδρομή Oura η εφαρμογή δεν μπορεί να διαβάσει τον ύπνο.',
      EmptyNight.notRead => 'Δεν έγινε ακόμα ανάγνωση από την Oura. Τράβηξε προς τα κάτω για να ξαναδοκιμάσεις.',
      EmptyNight.disconnected => 'Οι νύχτες μένουν κενές ώσπου να συνδέσεις ξανά το Oura ή να διαλέξεις το ρολόι (Ρυθμίσεις › Πηγές).',
      EmptyNight.onlyNap => 'Το δαχτυλίδι κατέγραψε μόνο υπνάκο, όχι νύχτα'
          '${napTimes(night).isEmpty ? '' : ': ${napTimes(night)}'}. Ο υπνάκος δεν μετρά ως νύχτα.',
      EmptyNight.unknownPlan => 'Οι ρυθμίσεις πηγών δεν διαβάστηκαν. Για να μη μπερδευτούν συσκευές, οι νύχτες μένουν κενές '
          'ώσπου να διαλέξεις στις Ρυθμίσεις › Πηγές.',
      EmptyNight.notOura => '',
    };
    return EmptyCard(icon: Icons.bedtime_rounded, color: c.sleep, title: emptyNightText(reason), text: text);
  }
}

class _OuraNightCard extends StatelessWidget {
  const _OuraNightCard(
      {required this.night, required this.now, this.reason, this.todayNight, this.range, this.readiness, this.onHistory, this.onMetric});

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
            Text(
              '${emptyNightText(reason!)} για χθες βράδυ'
              '${reason == EmptyNight.onlyNap && napTimes(todayNight, nightOnly: true).isNotEmpty ? ' (${napTimes(todayNight, nightOnly: true)})' : ''}. '
              'Βλέπεις την τελευταία νύχτα που ήρθε.',
              style: TextStyle(color: c.bad, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35),
            ),
            const SizedBox(height: 10),
          ],
          TitleRow(
            header: CardHeader(icon: Icons.bedtime_rounded, title: 'Τελευταία νύχτα · ${shortDayDate(night.day)}', color: c.sleep),
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
              if (readiness != null) (readiness!, 'Ετοιμότητα', 'για σήμερα', 'sleep-readiness'),
            ]),
          ],
          if (minutes != null && range != null) ...[
            const SizedBox(height: 12),
            RangeNote(value: minutes.toDouble(), range: range!, min: 180, max: 600, color: c.sleep, oneNight: true),
          ],
          const SizedBox(height: 14),
          // Τρεις στήλες όσο χωράει κάθε λέξη· αλλιώς γραμμές «ετικέτα … ώρα» (ποτέ «00:2/6»).
          LayoutBuilder(builder: (context, box) {
            // Σχέδια 9/11 (2α): Κοιμήθηκες · Ξύπνησες · Ξύπνιος (ο χρόνος ξύπνιος ΜΕΣΑ στον ύπνο).
            final awakeSec = parts.every((p) => p.awakeInSleep == null) ? null : parts.fold<int>(0, (a, p) => a + (p.awakeInSleep ?? 0));
            final items = [
              ('Κοιμήθηκες', parts.first.onset == null ? '—' : hm(parts.first.onset!)),
              ('Ξύπνησες', hm(parts.last.end)),
              ('Ξύπνιος', awakeSec == null ? '—' : hmList((awakeSec / 60).round())),
            ];
            final fits = wordsFit(context, [for (final i in items) i.$1], TextStyle(fontSize: 13, color: c.textSecondary), box.maxWidth / 3 - 4) &&
                wordsFit(context, const ['00:00'], const TextStyle(fontSize: 20, fontWeight: FontWeight.w700), box.maxWidth / 3 - 4);
            if (fits) return Row(children: [for (final i in items) clock(i.$1, i.$2)]);
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
              Text(hm(n.start), style: TextStyle(color: c.textTertiary, fontSize: 11.5)),
              const Spacer(),
              Text(hm(n.end), style: TextStyle(color: c.textTertiary, fontSize: 11.5)),
            ]),
          ],
          if (parts.length > 1) ...[
            const Hairline(vertical: 12),
            for (final x in parts)
              InfoRow('Κομμάτι ${hm(x.start)}–${hm(x.end)}', x.totalMinutes == null ? '—' : hoursMinutes(x.totalMinutes!)),
            InfoRow(
              'Κενό ανάμεσα (δεν μετρά)',
              hoursMinutes([for (var i = 1; i < parts.length; i++) parts[i].start.difference(parts[i - 1].end).inMinutes].fold(0, (a, b) => a + b)),
              dot: c.textTertiary,
            ),
          ],
          if (night.naps.isNotEmpty || night.others.isNotEmpty) ...[
            const Hairline(vertical: 12),
            // Υπνάκοι κατά τον κοινό κανόνα με το ρολόι, και περίοδοι που επικαλύπτονται: χωριστά, δεν προστίθενται.
            for (final x in night.naps)
              InfoRow('Υπνάκος ${hm(x.start)}–${hm(x.end)} (χωριστά)', x.totalMinutes == null ? '—' : hoursMinutes(x.totalMinutes!)),
            for (final x in night.others)
              InfoRow('Άλλος ύπνος ${hm(x.start)}–${hm(x.end)} (χωριστά)', x.totalMinutes == null ? '—' : hoursMinutes(x.totalMinutes!)),
          ],
          if (onHistory != null) ...[
            const Hairline(vertical: 8),
            InkWell(
              key: const ValueKey('sleep-30-nights'),
              onTap: onHistory,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
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
    if (big || tiles.length == 1) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(height: 8), tile(tiles[i])],
      ]);
    }
    return Row(children: [
      for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: tile(tiles[i]))],
    ]);
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
      if (b.usual == null) return Text('μαθαίνει το συνηθισμένο σου', style: TextStyle(fontSize: 13, color: c.textSecondary));
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

    Widget row(String metric, String label, String value, {Widget? sub, bool line = true}) => InkWell(
          key: ValueKey('sleep-rest-$metric'),
          onTap: () => Navigator.of(context).push(MetricPage.route(store, metric, now: now)),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: line ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Ετικέτα και τιμή· αν δεν χωρούν, η τιμή πάει ολόκληρη στην επόμενη γραμμή (σχέδια 9/11, 9β).
              Wrap(alignment: WrapAlignment.spaceBetween, spacing: 12, children: [
                Text(label, style: TextStyle(fontSize: 15, color: c.text)),
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
            header: CardHeader(icon: Icons.favorite_rounded, title: 'Καρδιά και θερμοκρασία στον ύπνο', color: c.heart),
            trailing: const [SourceTag(Source.oura), InfoButton(K.hrv)],
          ),
          const SizedBox(height: 4),
          row(K.hrv, 'HRV', hrv == null ? '—' : '${hrv.value.round()} ms', sub: usual(hrv)),
          row(K.sleepHr, 'Παλμοί ύπνου', hr == null ? '—' : '${hr.value.round()} bpm', sub: usual(hr)),
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
            rox.avg == null ? '$oxygenAvgLabel —' : '$oxygenAvgLabel ${spo2AvgText(rox.avg!)}%',
            rox.avg == null
                ? (windows.mains.containsKey(dateKey(day)) ? ringAvgMissing(store) : 'Χωρίς νύχτα από το δαχτυλίδι')
                : 'Όλη τη νύχτα',
            Source.oura,
          ),
          const Hairline(vertical: 2),
          // 7/11: η χαμηλότερη από το ρολόι, μόνο με κάλυψη ≥ 50% του ύπνου του Oura.
          row(
            rox.min == null ? '$oxygenMinLabel —' : '$oxygenMinLabel ${lowestText(rox.min!)}%',
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
                          : '${hm(night!.counted.first.onset ?? night!.counted.first.start)} – ${hm(night!.counted.last.end)}'
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
                      Text('σκορ ${night!.sleepScore}', style: TextStyle(color: c.sleep, fontSize: 13, fontWeight: FontWeight.w600)),
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
