import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../oura/oura_model.dart';
import '../oura/oura_view.dart';
import '../shown.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import 'source_widgets.dart';

/// Οι νύχτες για τη σύγκριση: Oura δίπλα στο ρολόι, μόνο στο διάστημα της σύγκρισης, η νεότερη πρώτη.
/// Οι νύχτες του ρολογιού έρχονται ΜΟΝΟ από το [Dashboard.compareNights] (δεν φαίνονται πουθενά αλλού).
List<CompareRow> buildCompareRows({
  required SourcePlan plan,
  required List<OuraNight> oura,
  required List<Night> watch,
  required DateTime today,
}) {
  final from = plan.ouraFrom;
  final until = plan.compareUntil;
  if (from == null || until == null) return const [];
  final rows = <CompareRow>[];
  final last = today.isBefore(until) ? today : until;
  for (var d = dayOf(last); !d.isBefore(from); d = DateTime(d.year, d.month, d.day - 1)) {
    if (plan.nightSource(d) != Source.oura) continue;
    OuraSleep? o;
    OuraNight? on;
    for (final n in oura) {
      if (sameDay(n.day, d)) {
        o = n.main;
        on = n;
      }
    }
    Night? w;
    for (final n in watch) {
      if (sameDay(n.date, d)) w = n;
    }
    if (o == null && w == null) continue;
    // Νύχτα σε κομμάτια (κοινός κανόνας με το ρολόι): διάρκεια, ώρες, ξύπνιος και «με τα ξυπνήματα» από ΟΛΑ τα
    // κομμάτια που μετρούν, όπως στον Ύπνο και στο ιστορικό· το κενό ανάμεσα δεν μετρά. Παλμοί: της κύριας περιόδου.
    final parts = on?.counted ?? const <OuraSleep>[];
    // Έλεγχος 3, E7: «ξύπνιος μέσα» χωρίς τον χρόνο ως τον ύπνο (το awake_time της Oura τον περιέχει), όπως στο ρολόι.
    final awakeParts =
        parts.any((x) => x.awakeInSleep == null) ? null : parts.fold<int>(0, (a, x) => a + x.awakeInSleep!);
    final onset = parts.isEmpty ? null : parts.first.onset;
    int? span;
    if (onset != null) {
      var secs = 0;
      for (final (i, x) in parts.indexed) {
        secs += x.end.difference(i == 0 ? onset : x.start).inSeconds;
      }
      span = (secs / 60).round();
      // Συγχώνευση 3: ύπνος + ξύπνιος = «με τα ξυπνήματα» (E7)· η Oura δίνει δευτερόλεπτα, και τρεις χωριστές
      // στρογγυλοποιήσεις έβγαζαν «7:16 + 22′ = 7:37». Διαφορά μόνο από στρογγυλοποίηση (≤ 1′): το άθροισμα.
      final sleep = on?.nightMinutes;
      final awake = awakeParts == null ? null : (awakeParts / 60).round();
      if (sleep != null && awake != null && (sleep + awake - span).abs() <= 1) span = sleep + awake;
    }
    rows.add(CompareRow(
      day: d,
      // Νύχτα σε κομμάτια: όλα τα κομμάτια που μετρούν (ίδιο με τον Ύπνο και το ιστορικό, U12).
      ouraMinutes: on?.nightMinutes,
      ouraStart: parts.isEmpty ? null : (onset ?? parts.first.start),
      ouraEnd: parts.isEmpty ? null : parts.last.end,
      ouraHr: o?.avgHr,
      ouraAwake: parts.isEmpty || awakeParts == null ? null : (awakeParts / 60).round(),
      // Ίδιος ορισμός και στις δύο: πραγματικός ύπνος (χωρίς τα ξυπνήματα). Ρολόι: Night.minutes, που είναι
      // βαθύς + ελαφρύς + REM από τα στάδια· νύχτα χωρίς στάδια: «—» (η διάρκειά της έχει τα ξυπνήματα).
      // Νύχτα «μερικώς χωρίς φάσεις» (C3): τα λεπτά της είναι μόνο τα κομμάτια με φάσεις, όχι όλη η νύχτα — δεν μπαίνουν
      // δίπλα στον πραγματικό ύπνο του Oura.
      watchMinutes: w != null && w.staged && !w.partial ? w.minutes : null,
      ouraSpan: span,
      watchSpan: w?.spanMinutes,
      watchEstimated: w?.estimatedMinutes ?? 0,
      watchStart: w?.start,
      watchEnd: w?.end,
      watchParts: w?.parts.length ?? 0,
      ouraParts: parts.length,
      watchHr: w?.sleepingHr,
      watchAwake: w == null || w.stageMinutes.isEmpty ? null : w.awakeMinutes,
    ));
  }
  return rows;
}

/// «Σύγκριση πηγών»: μόνο για έλεγχο, τις πρώτες 14 μέρες μετά τη σύνδεση. Δεν τροφοδοτεί κανένα άλλο νούμερο.
class ComparePage extends StatelessWidget {
  const ComparePage({super.key, required this.store, this.now});
  final HealthStore store;
  final DateTime? now;

  static const routeName = 'Σύγκριση πηγών';

  static Route<void> route(HealthStore store, {DateTime? now}) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: routeName),
        builder: (_) => ComparePage(store: store, now: now),
      );

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Σύγκριση πηγών'), backgroundColor: c.background, surfaceTintColor: Colors.transparent),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final today = dayOf(now ?? DateTime.now());
          final plan = store.plan;
          final rows = buildCompareRows(
            plan: plan,
            oura: store.ouraNights,
            watch: store.data?.compareNights ?? const [],
            today: today,
          );
          final summary = compareSummary(rows);
          final until = plan.compareUntil;

          final intro = AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  until == null || !plan.compareActive(today)
                      ? 'Η σύγκριση έκλεισε.'
                      : 'Μόνο για έλεγχο ·\u00A0κλείνει μόνη της ${shortDayDate(until)}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ο ύπνος στην εφαρμογή έρχεται μόνο από το Oura. Ο ύπνος του ρολογιού φαίνεται μόνο εδώ, για να δεις '
                  'αν το δαχτυλίδι μετρά λογικά. Τίποτα από εδώ δεν μπαίνει στις Τάσεις ή αλλού.',
                  style: TextStyle(fontSize: 14, color: c.textSecondary, height: 1.4),
                ),
              ],
            ),
          );

          final mean = summary.meanDiff;
          final head = AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  summary.nights == 0
                      ? 'Δεν υπάρχει ακόμα νύχτα με δαχτυλίδι και ρολόι'
                      : '${countText(summary.nights, 'νύχτα', 'νύχτες')} με δαχτυλίδι και ρολόι',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textSecondary),
                ),
                if (mean != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    mean.abs() < 5
                        ? 'Το ρολόι μετρά κατά μέσο όρο σχεδόν τον ίδιο ύπνο'
                        : 'Το ρολόι μετρά κατά μέσο όρο ${hoursMinutes(mean.abs())} ${mean < 0 ? 'λιγότερο' : 'περισσότερο'} ύπνο',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text, height: 1.25),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ρολόι σε κομμάτια: ${summary.splitNights} από ${countText(summary.nights, 'νύχτα', 'νύχτες')}',
                    style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                  ),
                ],
                const SizedBox(height: 10),
                // Έλεγχος υπολογισμών F7 (4/11): δύο διαφορετικοί ορισμοί, γραμμένοι ρητά.
                Text(
                  'Τι συγκρίνεται: πραγματικός ύπνος και στις δύο, χωρίς τα ξυπνήματα (ρολόι: βαθύς + ελαφρύς + REM της '
                  'Samsung· νύχτα χωρίς φάσεις: «—»). Χωριστά ο χρόνος ξύπνιος και ο χρόνος «με τα ξυπνήματα» (από τον '
                  'ύπνο ως το ξύπνημα)· και οι δύο συσκευές μετρούν λιγότερα ξυπνήματα απ\' όσα είναι.',
                  style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 8),
                Text(
                  'Καμία συσκευή δεν είναι «η σωστή». Εδώ βλέπεις πόσο διαφέρουν· οι φάσεις ύπνου διαφέρουν πολύ ακόμα '
                  'και ανάμεσα σε καλές συσκευές, γι\' αυτό δεν τις συγκρίνουμε.',
                  style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4),
                ),
              ],
            ),
          );

          final list = [for (final r in rows) _CompareCard(row: r)];

          return LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 760;
            Widget col(List<Widget> items) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final (i, w) in items.indexed) ...[if (i > 0) const SizedBox(height: 12), w]],
                );
            final left = [intro, head];
            final right = list.isEmpty
                ? <Widget>[
                    EmptyCard(
                      icon: Icons.compare_arrows_rounded,
                      color: c.sleep,
                      title: 'Νύχτα με νύχτα',
                      text: 'Μετά την πρώτη νύχτα με δαχτυλίδι και ρολόι θα δεις εδώ τις δύο μετρήσεις δίπλα δίπλα.',
                    ),
                  ]
                : list;
            return ListView(
              padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 8, wide ? 28 : 16, 32),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wide ? 1080 : 640),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [Expanded(child: col(left)), const SizedBox(width: 16), Expanded(child: col(right))],
                          )
                        : col([...left, ...right]),
                  ),
                ),
              ],
            );
          });
        },
      ),
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({required this.row});
  final CompareRow row;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final r = row;
    // Σύντομη μορφή: στα 400 dp το «7 ώρες 16 λεπτά» έσπαγε σε 2 γραμμές σε κάθε κελί.
    String dur(int? m) => m == null ? '—' : hoursMinutesShort(m);
    String t(DateTime? x) => x == null ? '—' : hm(x);
    String hr(double? x) => x == null ? '—' : '${x.round()} bpm';

    TableRow line(String label, String oura, String watch) => TableRow(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 7, 8, 7),
            child: Text(label, style: TextStyle(fontSize: 14, color: c.textSecondary)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 7, 10, 7),
            child: Text(oura, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.text, fontFeatures: tabular)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Text(watch, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.text, fontFeatures: tabular)),
          ),
        ]);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(longDate(r.day), style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text)),
              ),
              if (r.diff != null)
                TrendPill(r.diff!.abs() < 5 ? 'σχεδόν ίδια' : 'διαφορά ${hoursMinutes(r.diff!.abs())}'),
            ],
          ),
          const SizedBox(height: 8),
          Table(
            columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.2)},
            children: [
              TableRow(children: [
                const SizedBox(),
                const Align(alignment: Alignment.centerLeft, child: SourceTag(Source.oura)),
                const Align(alignment: Alignment.centerLeft, child: SourceTag(Source.watch)),
              ]),
              // Ίδιο με ίδιο (έλεγχος 4/11): πραγματικός ύπνος με πραγματικό, «με τα ξυπνήματα» με «με τα ξυπνήματα».
              // Οι ορισμοί είναι γραμμένοι στην κάρτα «Τι συγκρίνεται»· εδώ σύντομες ετικέτες.
              line('Πραγματικός ύπνος', dur(r.ouraMinutes), dur(r.watchMinutes)),
              line('Ξύπνιος μέσα', dur(r.ouraAwake), dur(r.watchAwake)),
              line('Με τα ξυπνήματα', dur(r.ouraSpan), dur(r.watchSpan)),
              line('Κοιμήθηκες', t(r.ouraStart), t(r.watchStart)),
              line('Ξύπνησες', t(r.ouraEnd), t(r.watchEnd)),
              line('Κομμάτια', r.ouraMinutes == null || r.ouraParts == 0 ? '—' : '${r.ouraParts}', r.watchParts == 0 ? '—' : '${r.watchParts}'),
              line('Παλμοί ύπνου', hr(r.ouraHr), hr(r.watchHr)),
            ],
          ),
          if (r.watchEstimated > 0)
            Text(
              // UX U3: ίδια φράση σε όλες τις οθόνες.
              'Ρολόι: +${hoursMinutes(r.watchEstimated)} $possibleSleepPhrase.',
              style: TextStyle(fontSize: 12.5, color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}
