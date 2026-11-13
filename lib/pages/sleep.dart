import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart' show K;
import '../oura/oura_view.dart' show atLeast, glued, minNightsForAverage;
import '../oxygen_note.dart';
import '../reference.dart' show stagesInfoKey;
import '../shown.dart';
import '../trends.dart' show circularMeanMinutes, unwrapMinutes;
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import 'info_sheet.dart';
import 'oura_sleep.dart';
import 'oxygen_widgets.dart';

class SleepPage extends StatelessWidget {
  const SleepPage({super.key, required this.store, this.now});
  final HealthStore store;

  /// Για τα στιγμιότυπα δοκιμών.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = Aigaio.of(context);
        // Μετά τη σύνδεση του Oura (ή την αποσύνδεσή του χωρίς άλλη πηγή): μόνο ύπνος από το Oura.
        if (store.plan.nightSource(now ?? DateTime.now()) != Source.watch) {
          return OuraSleepPage(store: store, now: now);
        }
        final d = store.data;
        final nights = d?.nights ?? const <Night>[];
        if (d == null || nights.isEmpty) {
          return PageFrame(
            title: 'Ύπνος',
            onRefresh: () => store.refresh(),
            left: [
              if (d != null && d.failed.contains('sleep'))
                EmptyCard(
                  icon: Icons.bedtime_rounded,
                  color: c.sleep,
                  title: 'Ο ύπνος δεν διαβάστηκε τώρα',
                  text: 'Η Samsung δεν τον έδωσε αυτή τη φορά. Τράβηξε την οθόνη προς τα κάτω για να ξαναδοκιμάσεις.',
                )
              else
                EmptyCard(
                  icon: Icons.bedtime_rounded,
                  color: c.sleep,
                  title: 'Δεν υπάρχει ύπνος ακόμα',
                  text: 'Φόρεσε το ρολόι στον ύπνο. Το πρωί θα δεις εδώ πότε κοιμήθηκες, πόσο και πόσο καλά.',
                ),
            ],
          );
        }

        final last14 = nights.length <= 14 ? nights : nights.sublist(nights.length - 14);
        // Τελικός έλεγχος: μέρες με μόνο υπνάκο (καμία νύχτα) φαίνονται κι αυτές στη λίστα και στο γράφημα (κενή
        // στήλη), ως «Μόνο υπνάκος». Δεν μπαίνουν σε κανέναν μέσο όρο ή στατιστικό νύχτας.
        final timeline = <(DateTime, Night?)>[
          for (final n in last14) (n.date, n),
          for (final x in napOnlyDays(d, store.plan, last14.first.date)) (x, null),
        ]..sort((a, b) => a.$1.compareTo(b.$1));
        // Εβδομάδα = οι νύχτες των 7 τελευταίων ημερών, όχι οι 7 τελευταίες καταγραφές (έλεγχος υπολογισμών F15).
        final lastDay = nights.last.date;
        final week = [
          for (final n in nights)
            if (n.date.isAfter(DateTime(lastDay.year, lastDay.month, lastDay.day - 7))) n,
        ];
        // Μέσος όρος μόνο από νύχτες με φάσεις (πραγματικός ύπνος, χωρίς τα ξυπνήματα)· η ετικέτα λέει από πόσες.
        final timed = week.where((n) => n.fullDuration).length;
        final avg7 = Dashboard.mean(week.where((n) => n.fullDuration).map((n) => n.minutes.toDouble()));
        final scoreAvg = Dashboard.mean(week.map((n) => n.score?.toDouble()));
        // Οι χωρισμένες νύχτες δεν έχουν βαθμολογία: λέμε από πόσες βγαίνει ο μέσος όρος.
        final scored = week.where((n) => n.score != null).length;

        return PageFrame(
          title: 'Ύπνος',
          // Έλεγχος UX U6: τα διαστήματα της σελίδας γραμμένα μία φορά, ίδια σε κάθε κάρτα.
          subtitle: 'Η τελευταία νύχτα · μέσοι όροι 7 νυχτών · γράφημα 14 νυχτών',
          onRefresh: () => store.refresh(),
          left: [
            _LastNightCard(
              night: nights.last,
              data: d,
              oxHistory: store.history,
              today: now ?? DateTime.now(),
            ),
            _WatchStagesCard(nights: week),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardHeader(icon: Icons.bar_chart_rounded, title: 'Διάρκεια · 14 νύχτες', color: c.sleep),
                  const SizedBox(height: 14),
                  // Round 1 (U1a-4β): οι δύο τιμές στην ίδια γραμμή βάσης, ακόμα κι όταν η μία ετικέτα πιάνει δύο γραμμές.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: _Summary(
                          label: timed == 7 ? 'Μέσος όρος 7 νυχτών' : 'Μέσος όρος 7 νυχτών (από ${countText(timed, 'νύχτα', 'νύχτες')})',
                          value: avg7 == null ? '—' : hoursMinutes(avg7.round()),
                        ),
                      ),
                      Expanded(
                        child: _Summary(
                          label: scored == week.length ? 'Μέση βαθμολογία 7 νυχτών' : 'Μέση βαθμολογία 7 νυχτών (από ${countText(scored, 'νύχτα', 'νύχτες')})',
                          value: scoreAvg == null ? '—' : '${scoreAvg.round()} από 100',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  BarChart(
                    values: [for (final t in timeline) t.$2 == null ? null : sleepBarHours(t.$2!)],
                    labels: [for (final t in timeline) weekdayShort(t.$1)],
                    average: avg7 == null ? null : avg7 / 60,
                    valueLabel: (v) => hoursMinutes((v * 60).round()),
                    color: c.sleep,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Η διακεκομμένη γραμμή είναι ο μέσος όρος των 7 νυχτών.',
                    style: TextStyle(color: c.textTertiary, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            _ConsistencyCard(nights: last14),
          ],
          right: [
            const SectionHeader('Νύχτα προς νύχτα · 14 νύχτες'),
            for (final t in timeline.reversed)
              t.$2 == null
                  ? _NapOnlyRow(day: t.$1, naps: d.napTimes[t.$1]!, now: d.readAt)
                  : _NightRow(night: t.$2!, now: d.readAt),
          ],
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w700, fontFeatures: tabular)),
      ],
    );
  }
}

class _LastNightCard extends StatelessWidget {
  const _LastNightCard({required this.night, required this.data, required this.today, this.oxHistory = const {}});
  final Night night;
  final Dashboard data;

  /// Σήμερα: για να μη λέγεται «χθεσινή» μια παλιότερη νύχτα στη σημείωση του οξυγόνου.
  final DateTime today;

  /// Αρχή της εποχής του ορισμού του οξυγόνου (οι σημειώσεις δεν μετρούν νύχτες με άλλον ορισμό, A4).
  /// Έλεγχος 3, E5: το ιστορικό, για τις νύχτες του μήνα πριν από τη σύνδεση του Oura/την επανανάγνωση.
  final Map<String, Map<String, double>> oxHistory;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final n = night;

    Widget clock(String label, DateTime t) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: c.textSecondary, fontSize: 13)),
              Text(
                hm(t),
                style: TextStyle(color: c.text, fontSize: 22, fontWeight: FontWeight.w700, fontFeatures: tabular),
              ),
            ],
          ),
        );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Round 1 (U1a-8α): η ημερομηνία ως υπότιτλος (πριν έσπαγε ο τίτλος «… · Σάβ | 14/11»).
          CardHeader(
            icon: Icons.bedtime_rounded,
            title: 'Τελευταία νύχτα',
            subtitle: shortDayDate(n.date),
            color: c.sleep,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: DurationValue(n.minutes, size: 30)),
              // Χωρίς βαθμολογία της νύχτας: όχι άδειο δαχτυλίδι «—» δίπλα στις βαθμολογίες των κομματιών (έλεγχος UX U8).
              if (n.score != null)
                ScoreRing(
                  value: n.score!.toDouble(),
                  size: 64,
                  stroke: 6,
                  color: c.sleep,
                  track: c.tint(c.sleep),
                  textColor: c.text,
                  // Round 1 (U1a-7): «βαθμολογία», όπως σε κάθε άλλη οθόνη (όχι «σκορ»)· σε δύο γραμμές, ώστε με μεγάλα
                  // γράμματα η λεζάντα να μη γίνεται φαρδύτερη από τη στήλη.
                  caption: 'βαθμολογία\nεκτίμηση',
                ),
            ],
          ),
          if (!n.staged) ...[
            const SizedBox(height: 6),
            Text(
              'Χωρίς φάσεις από τη Samsung· διάρκεια με τα ξυπνήματα. Δεν μετρά στους μέσους όρους.',
              style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
            ),
          ],
          if (n.partial) ...[
            const SizedBox(height: 6),
            Text(
              'Μερικώς χωρίς φάσεις: ένα κομμάτι της νύχτας ήρθε χωρίς φάσεις από τη Samsung. Η διάρκεια μετρά μόνο '
              'τα κομμάτια με φάσεις, γι’ αυτό δεν μετρά στους μέσους όρους.',
              style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
            ),
          ],
          if (n.estimatedMinutes > 0) ...[
            const SizedBox(height: 6),
            Text(
              // UX U3: ίδια φράση με τη Σήμερα και τη γραμμή πιο κάτω, και μετά η εξήγηση.
              '+${hoursMinutes(n.estimatedMinutes)} $possibleSleepPhrase: κενό της Samsung χωρίς βήματα, με παλμούς '
              'σαν του ύπνου. Ίσως κοιμόσουν, ίσως ήσουν ξαπλωμένος ξύπνιος.',
              style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
            ),
          ],
          const SizedBox(height: 14),
          // Round 1 (U1a-4α): στήλες στοιχισμένες πάνω (η τρίτη έχει δύο γραμμές και κατέβαζε τις άλλες).
          // Round 7 (R7-U1, «τουλάχιστο|ν»): στο ανοιχτό Fold η στήλη ήταν στενότερη από τη λέξη «τουλάχιστον» και η
          // Flutter την έκοβε στη μέση. Τώρα «3 λεπτά» με «τουλάχιστον» από κάτω (όπως η κάρτα του Oura), και στήλες μόνο
          // όταν χωράει κάθε λέξη· αλλιώς γραμμές «ετικέτα … τιμή».
          LayoutBuilder(builder: (context, box) {
            // Τα ρολόγια πιάνουν περίπου τον μισό χρόνο που είσαι ξύπνιος (κλινικός έλεγχος H1).
            final awake = n.awakeMinutes > 0 ? glued(hoursMinutes(n.awakeMinutes)) : null;
            const atLeastWord = 'τουλάχιστον';
            const awakeStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
            final col = box.maxWidth / 3 - 4;
            final fits = wordsFit(context, ['Κοιμήθηκες', 'Ξύπνησες', if (awake != null) ...['Ξύπνιος', atLeastWord]],
                    TextStyle(color: c.textSecondary, fontSize: 13), col) &&
                wordsFit(context, [hm(n.start), hm(n.end)],
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, fontFeatures: tabular), col) &&
                (awake == null || wordsFit(context, [awake], awakeStyle, col));
            if (!fits) {
              return Column(children: [
                InfoRow('Κοιμήθηκες', hm(n.start)),
                InfoRow('Ξύπνησες', hm(n.end)),
                if (awake != null) InfoRow('Ξύπνιος', '$atLeastWord $awake'),
              ]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                clock('Κοιμήθηκες', n.start),
                clock('Ξύπνησες', n.end),
                if (awake != null)
                  Expanded(
                    key: const ValueKey('sleep-awake'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ξύπνιος', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                        Text(awake, style: awakeStyle.copyWith(color: c.text)),
                        Text(atLeastWord, style: TextStyle(color: c.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
              ],
            );
          }),
          const SizedBox(height: 16),
          Text('Πώς κύλησε η νύχτα · εκτίμηση της Samsung',
              style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Hypnogram(night: n, height: 64),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(hm(n.start), style: TextStyle(color: c.textTertiary, fontSize: 11.5)),
              const Spacer(),
              Text(hm(n.end), style: TextStyle(color: c.textTertiary, fontSize: 11.5)),
            ],
          ),
          // Στάδια μίας νύχτας σε λεπτά και %: όχι (κλινικός έλεγχος H1)· ο μέσος όρος 7 νυχτών είναι στην επόμενη κάρτα.
          const Hairline(vertical: 14),
          if (n.sleepingHr != null) InfoRow('Παλμοί στον ύπνο', '${n.sleepingHr!.round()} bpm', dot: c.heart),
          if (n.spo2Avg != null) InfoRow(oxygenAvgLabel, '${spo2AvgText(n.spo2Avg!)}%', dot: c.sleep),
          if (n.spo2Min != null) InfoRow(oxygenMinLabel, '${lowestText(n.spo2Min!)}% · ενδεικτικό', dot: c.sleep),
          if (n.spo2Avg != null || n.spo2Min != null) ...[
            const SizedBox(height: 6),
            // Τρίτος κλινικός έλεγχος C2/F5: και εδώ το κείμενο για το τεστ άπνοιας (μία γραμμή κλειστό, όπως στην Καρδιά).
            const OxygenAbout(),
            OxygenNotes(
              guidance: oxygenGuidance(data.spo2MinByNight(n.date, history: oxHistory), n.date, today: today),
            ),
            const SizedBox(height: 6),
          ],
          if (n.parts.length > 1) InfoRow('Η Samsung τη χώρισε σε', '${n.parts.length} κομμάτια', dot: c.textTertiary),
          if (n.parts.length > 1 && n.parts.any((p) => p.score != null))
            InfoRow(
              'Βαθμολογία Samsung ανά κομμάτι',
              [for (final p in n.parts) p.score?.toString() ?? '—'].join(' · '),
              dot: c.textTertiary,
            ),
          if (n.estimatedMinutes > 0)
            InfoRow('Ίσως ύπνος χωρίς καταγραφή (δεν μετρά)', hoursMinutes(n.estimatedMinutes), dot: c.tint(c.sleep)),
          if (n.spanMinutes > n.minutes)
            InfoRow('Από τον ύπνο ως το ξύπνημα (με τα ξυπνήματα)', hoursMinutes(n.spanMinutes), dot: c.textTertiary),
          if (n.betweenMinutes > 0)
            InfoRow('Κενό ανάμεσα στα κομμάτια (δεν μετρά)', hoursMinutes(n.betweenMinutes), dot: c.textTertiary),
          if (n.napMinutes > 0) InfoRow('Υπνάκος ή χωριστός ύπνος (δεν μετρά)', hoursMinutes(n.napMinutes), dot: c.textTertiary),
        ],
      ),
    );
  }
}

/// Στάδια μόνο ως μέσος όρος 7 νυχτών (τουλάχιστον 4), όπως στο Oura (κλινικός έλεγχος H1, 4/11). Τα στάδια μίας
/// νύχτας έχουν μεγάλο λάθος (Galaxy Watch 5: κ = 0,42, Lee et al. JMIR 2023)· ο χρόνος ξύπνιος «τουλάχιστον».
class _WatchStagesCard extends StatelessWidget {
  const _WatchStagesCard({required this.nights});

  /// Οι νύχτες των 7 τελευταίων ημερών.
  final List<Night> nights;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final staged = [
      for (final n in nights)
        if (stageOrder.any((k) => (n.stageMinutes[k] ?? 0) > 0)) n,
    ];
    int avg(String k) => (staged.fold<int>(0, (s, n) => s + (n.stageMinutes[k] ?? 0)) / staged.length).round();
    final enough = staged.length >= minNightsForAverage;
    return AppCard(
      key: const ValueKey('watch-stages'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TitleRow(
            header: CardHeader(icon: Icons.layers_rounded, title: 'Φάσεις · μέσος όρος 7 νυχτών', color: c.sleep),
            trailing: const [LabelTag('εκτίμηση'), InfoButton(stagesInfoKey)],
          ),
          const SizedBox(height: 12),
          if (!enough)
            Text(
              'Χρειάζονται τουλάχιστον $minNightsForAverage νύχτες με στάδια μέσα σε μία εβδομάδα '
              '(τώρα ${countText(staged.length, 'νύχτα', 'νύχτες')}).',
              style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.4),
            )
          else ...[
            StackedBar(parts: [for (final k in ['DEEP', 'LIGHT', 'REM', 'AWAKE']) (avg(k).toDouble(), c.stage(k))]),
            const SizedBox(height: 6),
            // Round 1 (U1a-3): διάρκειες με ολόκληρες λέξεις· ο χρόνος ξύπνιος «τουλάχιστον», όπως παντού.
            InfoRow(stageLabel('DEEP'), hoursMinutes(avg('DEEP')), dot: c.stage('DEEP')),
            InfoRow(stageLabel('LIGHT'), hoursMinutes(avg('LIGHT')), dot: c.stage('LIGHT')),
            InfoRow(stageLabel('REM'), hoursMinutes(avg('REM')), dot: c.stage('REM')),
            InfoRow('Ξύπνιος', atLeast(avg('AWAKE')), dot: c.stage('AWAKE')),
          ],
        ],
      ),
    );
  }
}

class _ConsistencyCard extends StatelessWidget {
  const _ConsistencyCard({required this.nights});
  final List<Night> nights;

  /// Λεπτά μετά τις 18:00, ώστε τα μεσάνυχτα να μη «σπάνε» τον μέσο όρο.
  int _fromSix(DateTime t) => (t.hour * 60 + t.minute - 18 * 60 + 1440) % 1440;

  String _clock(double minutesFromSix) {
    final m = ((minutesFromSix.round() + 18 * 60) % 1440 + 1440) % 1440;
    return '${two(m ~/ 60)}:${two(m % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    if (nights.length < 3) return const SizedBox.shrink();
    // Κυκλικός μέσος όρος: σωστός και για ώρες εκατέρωθεν των 18:00 (έλεγχος υπολογισμών F13).
    List<double> around(List<double> v) {
      final center = circularMeanMinutes(v);
      return [for (final x in v) unwrapMinutes(x, center)];
    }

    final bed = around(nights.map((n) => _fromSix(n.start).toDouble()).toList());
    final wake = around(nights.map((n) => _fromSix(n.end).toDouble()).toList());
    final bedAvg = Dashboard.mean(bed)!;
    final wakeAvg = Dashboard.mean(wake)!;
    final spread = bed.map((b) => (b - bedAvg).abs()).reduce((a, b) => a + b) / bed.length;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(icon: Icons.schedule_rounded, title: 'Ωράριο · 14 νύχτες', color: c.sleep),
          const SizedBox(height: 8),
          InfoRow('Συνήθως κοιμάσαι', _clock(bedAvg)),
          InfoRow('Συνήθως ξυπνάς', _clock(wakeAvg)),
          InfoRow('Η ώρα ύπνου αλλάζει συνήθως', '± ${hoursMinutes(spread.round())}'),
        ],
      ),
    );
  }
}

class _NightRow extends StatelessWidget {
  const _NightRow({required this.night, required this.now});
  final Night night;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
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
                      relativeDay(night.date, now) == 'Σήμερα' ? 'Χθες βράδυ' : shortDayDate(night.date),
                      style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${hm(night.start)} – ${hm(night.end)}',
                      style: TextStyle(color: c.textSecondary, fontSize: 13.5, fontFeatures: tabular),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    nightRowDuration(night),
                    style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 15, fontFeatures: tabular),
                  ),
                  if (nightRowNote(night) case final note?)
                    Text(note, style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
                  if (night.score != null)
                    Text(
                      'βαθμολογία ${night.score}',
                      style: TextStyle(color: c.sleep, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          StageTimeline(night: night, height: 8),
        ],
      ),
    );
  }
}

/// Τελικός έλεγχος: μέρα χωρίς νύχτα, μόνο με υπνάκο. Χωρίς βαθμολογία, φάσεις, οξυγόνο ή παλμούς· ποτέ «χωρίς ύπνο».
class _NapOnlyRow extends StatelessWidget {
  const _NapOnlyRow({required this.day, required this.naps, required this.now});
  final DateTime day;
  final List<(DateTime, DateTime, int)> naps;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      key: ValueKey('nap-only-${day.year}-${day.month}-${day.day}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  relativeDay(day, now) == 'Σήμερα' ? 'Σήμερα' : shortDayDate(day),
                  style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(napOnlyText(naps), style: TextStyle(color: c.textSecondary, fontSize: 13.5, fontFeatures: tabular)),
              ],
            ),
          ),
          Text(napOnlyLabel, style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Η ετικέτα της μέρας με μόνο υπνάκο (ρολόι και Oura).
const napOnlyLabel = 'Μόνο υπνάκος';

/// «Υπνάκος 15:00–21:00 · 5 ώρες 40 λεπτά» (πολλοί: «Υπνάκοι 13:00–14:00, 16:00–17:00 · σύνολο»).
String napOnlyText(List<(DateTime, DateTime, int)> naps) {
  final total = naps.fold<int>(0, (s, x) => s + x.$3);
  return '${naps.length == 1 ? 'Υπνάκος' : 'Υπνάκοι'} ${[for (final x in naps) '${hm(x.$1)}–${hm(x.$2)}'].join(', ')} · '
      '${hoursMinutes(total)}';
}

/// Οι μέρες από το [from] με υπνάκο του ρολογιού και χωρίς νύχτα, μόνο όπου ο ύπνος είναι του ρολογιού (τρέχουσα
/// εποχή), παλιότερη πρώτη.
List<DateTime> napOnlyDays(Dashboard d, SourcePlan plan, DateTime from) {
  final today = dayOf(d.readAt);
  final seg = plan.segmentStart(K.sleepMin, today);
  return [
    for (final e in d.napTimes.entries)
      if (e.value.isNotEmpty &&
          !e.key.isBefore(dayOf(from)) &&
          !e.key.isAfter(today) &&
          plan.nightSource(e.key) == Source.watch &&
          (seg == null || !e.key.isBefore(seg)) &&
          !d.nights.any((n) => sameDay(n.date, e.key)))
        e.key,
  ]..sort();
}

/// Έλεγχος 2, C13: η στήλη μιας νύχτας στο γράφημα 14 νυχτών. Νύχτα χωρίς φάσεις: κενή (η διάρκεια της Samsung έχει
/// τα ξυπνήματα και δεν μπαίνει δίπλα στον πραγματικό ύπνο των άλλων νυχτών).
double? sleepBarHours(Night n) => n.staged ? n.minutes / 60 : null;

/// C13: η διάρκεια στη γραμμή «Νύχτα προς νύχτα»: «—» για νύχτα χωρίς φάσεις (ποτέ η διάρκεια της Samsung).
String nightRowDuration(Night n) => n.staged ? hoursMinutes(n.minutes) : '—';

/// C13: η σημείωση κάτω από τη διάρκεια («χωρίς φάσεις» / «μερικώς χωρίς φάσεις»), null αν δεν χρειάζεται.
String? nightRowNote(Night n) => !n.staged ? 'χωρίς φάσεις' : (n.partial ? 'μερικώς χωρίς φάσεις' : null);
