import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../report.dart';
import '../samsung.dart';
import '../theme.dart';
import '../trends.dart';
import '../widgets.dart';

/// Αναφορά για γιατρό: προεπισκόπηση των δύο σελίδων A4 και αποθήκευση ως PDF στις Λήψεις.
class ReportPage extends StatefulWidget {
  const ReportPage({super.key, required this.store, this.now});
  final HealthStore store;
  final DateTime? now;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final _keys = [GlobalKey(), GlobalKey()];
  bool _saving = false;
  String? _uri;
  String? _error;

  /// Σημείωση για τον γιατρό (φάρμακα, κάπνισμα…). Δεν αποθηκεύεται: γράφεται μόνο στο PDF.
  String _note = '';

  late final ReportData _data = buildReport(widget.store.history, widget.now ?? DateTime.now());

  String get _fileName {
    final t = _data.created;
    return 'Αναφορά υγείας ${t.year}-${two(t.month)}-${two(t.day)}.pdf';
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      final pages = <Uint8List>[];
      for (final k in _keys) {
        final boundary = k.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        // 595 στιγμές × 3 ≈ 250 dpi: καθαρό στην εκτύπωση, λογικό μέγεθος αρχείου.
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        pages.add(bytes!.buffer.asUint8List());
      }
      final r = await SamsungHealth.savePdf(pages, _fileName);
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (r['ok'] == true) {
          _uri = r['uri'] as String?;
        } else {
          _error = r['message']?.toString() ?? 'Άγνωστο σφάλμα';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final pages = [_PageOne(data: _data, note: _note.trim()), _PageTwo(data: _data)];

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Αναφορά για γιατρό'),
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final width = (box.maxWidth - 36).clamp(0.0, 640.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 160),
            child: Center(
              child: SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Οι τελευταίοι 3 μήνες σε δύο σελίδες A4, για να τις δείξεις ή να τις στείλεις στον γιατρό σου. '
                      'Μετρήσεις από ρολόι και ζυγαριά, με σύγκριση με τους προηγούμενους μήνες. Χωρίς διάγνωση.',
                      style: TextStyle(color: c.textSecondary, fontSize: 14.5, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      maxLength: 160,
                      maxLines: 2,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Σημείωση για τον γιατρό (προαιρετικά)',
                        hintText: 'π.χ. φάρμακα και δόση, κάπνισμα, συμπτώματα',
                      ),
                      onChanged: (v) => setState(() {
                        _note = v;
                        _uri = null; // το αποθηκευμένο PDF δεν έχει πια την ίδια σημείωση
                      }),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < pages.length; i++) ...[
                      if (i > 0) const SizedBox(height: 16),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          boxShadow: const [
                            BoxShadow(color: Color(0x220F172A), blurRadius: 18, offset: Offset(0, 6)),
                          ],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: AspectRatio(
                            aspectRatio: _a4.width / _a4.height,
                            child: FittedBox(
                              child: RepaintBoundary(
                                key: _keys[i],
                                child: _Paper(child: pages[i]),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Δεν αποθηκεύτηκε: $_error', style: TextStyle(color: c.bad, fontSize: 13.5)),
                  ),
                if (_uri != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: c.good, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Αποθηκεύτηκε στις Λήψεις: $_fileName',
                            style: TextStyle(color: c.text, fontSize: 13.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => SamsungHealth.openPdf(_uri!),
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Άνοιγμα'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => SamsungHealth.sharePdf(_uri!),
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: const Text('Αποστολή'),
                        ),
                      ),
                    ],
                  ),
                ] else
                  FilledButton.icon(
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.picture_as_pdf_rounded, size: 20),
                    label: Text(_saving ? 'Φτιάχνω το PDF…' : 'Αποθήκευση PDF στις Λήψεις'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Σελίδες A4 (595 × 842 στιγμές), πάντα σε ανοιχτό θέμα.
// ---------------------------------------------------------------------------

const _a4 = Size(595, 842);

class _Paper extends StatelessWidget {
  const _Paper({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildTheme(Brightness.light),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: Container(
          width: _a4.width,
          height: _a4.height,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(40, 36, 40, 26),
          child: DefaultTextStyle(
            style: const TextStyle(fontFamily: fontFamily, fontSize: 9.5, color: Color(0xFF1B2433), height: 1.35),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data, required this.page});
  final ReportData data;
  final int page;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.light;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    page == 1 ? 'Αναφορά υγείας' : 'Αναφορά υγείας · γραφήματα',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${dayMonth(data.from)} – ${dayMonthYear(data.to)} · $reportDays ημέρες',
                    style: TextStyle(fontSize: 10.5, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              'Υγεία & Φόρμα',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.primary),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(height: 1.2, color: c.primary.withValues(alpha: 0.5)),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.data, required this.page});
  final ReportData data;
  final int page;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.light;
    final t = data.created;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Μετρήσεις από ρολόι και ζυγαριά μέσω Samsung Health· δεν είναι ιατρικές μετρήσεις.',
            style: TextStyle(fontSize: 8, color: c.textTertiary),
          ),
        ),
        Text(
          'Δημιουργήθηκε ${t.day}/${t.month}/${t.year} · σελίδα $page από 2',
          style: TextStyle(fontSize: 8, color: c.textTertiary),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.light;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.text)),
    );
  }
}

// --- Σελίδα 1: πίνακας ---

class _PageOne extends StatelessWidget {
  const _PageOne({required this.data, this.note = ''});
  final ReportData data;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.light;
    final d = data;

    String num0(double v) => v.round().toString();
    String pct(double v) => '${v.round()}%';
    String dur(double v) {
      final m = v.round();
      return '${m ~/ 60}:${two(m % 60)}';
    }

    final rows = <(String, String, String Function(double), MetricDef?)>[
      ('Παλμοί στον ύπνο (bpm)', K.sleepHr, num0, _def(K.sleepHr)),
      ('Οξυγόνο στον ύπνο, μέσο', K.spo2Avg, pct, _def(K.spo2Avg)),
      ('Οξυγόνο στον ύπνο, ελάχιστο της νύχτας', K.spo2Min, pct, null),
      ('Διάρκεια ύπνου (ώρες:λεπτά)', K.sleepMin, dur, _def(K.sleepMin)),
      ('Ώρα που κοιμήθηκε', K.bedtime, clockFromSix, _def(K.bedtime)),
      ('Ώρα που ξύπνησε', K.wake, clockFromSix, null),
      ('Βήματα ανά μέρα', K.steps, (v) => thousands(v), _def(K.steps)),
    ];

    final header = TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: c.textSecondary);
    final cell = TextStyle(fontSize: 9.5, color: c.text, fontFeatures: tabular);
    final bold = cell.copyWith(fontWeight: FontWeight.w700);

    Widget pad(Widget w) => Padding(padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4), child: w);

    String trendText(ReportStat s, MetricDef? def) {
      final t = s.trend;
      if (def == null || t == null || t.status == TrendStatus.insufficient) return '—';
      if (t.status == TrendStatus.stable) return 'Σταθερό';
      final up = t.status == TrendStatus.up;
      if (def.kind == ValueKind.clock) return '${def.formatDiff(t.displayDiff!)} ${up ? 'αργότερα' : 'νωρίτερα'}';
      return '${up ? '↑' : '↓'} ${def.formatDiff(t.displayDiff!)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(data: d, page: 1),
        if (note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Σημείωση: $note',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9.5, color: c.text, height: 1.35),
            ),
          ),
        _Title('Σύνοψη'),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(2.5),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1.7),
            3: FlexColumnWidth(1.7),
            4: FlexColumnWidth(0.8),
            5: FlexColumnWidth(1.5),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder(horizontalInside: BorderSide(color: c.hairline, width: 0.8)),
          children: [
            TableRow(
              decoration: BoxDecoration(color: c.background),
              children: [
                pad(Text('Δείκτης', style: header)),
                pad(Text('Μεσαία τιμή', style: header)),
                pad(Text('Συνήθως\n(8 στις 10 μέρες)', style: header)),
                pad(Text('Χαμηλότερη –\nυψηλότερη', style: header)),
                pad(Text('Μέρες με\nμέτρηση', style: header)),
                pad(Text('Διαφορά από τους\n3 προηγ. μήνες', style: header)),
              ],
            ),
            for (final r in rows)
              () {
                final s = d.stat(r.$2);
                final f = r.$3;
                return TableRow(
                  children: [
                    pad(Text(r.$1, style: cell)),
                    pad(Text(s.median == null ? '—' : f(s.median!), style: bold)),
                    pad(Text(s.p10 == null ? '—' : '${f(s.p10!)} – ${f(s.p90!)}', style: cell)),
                    pad(Text(s.low == null ? '—' : '${f(s.low!)} – ${f(s.high!)}', style: cell)),
                    pad(Text('${s.n}', style: cell)),
                    pad(Text(trendText(s, r.$4), style: cell)),
                  ],
                );
              }(),
          ],
        ),
        _Title('Νύχτες με μία τουλάχιστον μέτρηση οξυγόνου κάτω από 90%'),
        if (d.lowOxygenNights.isEmpty)
          Text('Καμία στο διάστημα (${d.stat(K.spo2Min).n} νύχτες με μέτρηση).', style: cell)
        else ...[
          Text(
            '${d.lowOxygenNights.length} από ${d.stat(K.spo2Min).n} νύχτες με μέτρηση. Οι χαμηλότερες:',
            style: cell,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 14,
            runSpacing: 2,
            children: [
              for (final n in d.lowOxygenNights.take(12))
                Text('${dayMonthYear(n.$1)}: ${n.$2.round()}%', style: bold),
            ],
          ),
        ],
        _Title('Ζυγίσεις (InBody)'),
        if (d.weighIns.isEmpty)
          Text('Δεν υπάρχουν ζυγίσεις.', style: cell)
        else
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1.6),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(1.2),
              3: FlexColumnWidth(1.6),
              4: FlexColumnWidth(2.4),
            },
            border: TableBorder(horizontalInside: BorderSide(color: c.hairline, width: 0.8)),
            children: [
              TableRow(
                decoration: BoxDecoration(color: c.background),
                children: [
                  pad(Text('Ημερομηνία', style: header)),
                  pad(Text('Βάρος', style: header)),
                  pad(Text('Λίπος', style: header)),
                  pad(Text('Σκελετικοί μύες', style: header)),
                  const SizedBox(),
                ],
              ),
              for (final w in d.weighIns)
                TableRow(
                  children: [
                    pad(Text(dayMonthYear(w.$1), style: cell)),
                    pad(Text(w.$2 == null ? '—' : '${dec(w.$2!)} kg', style: bold)),
                    pad(Text(w.$3 == null ? '—' : '${dec(w.$3!)}%', style: cell)),
                    pad(Text(w.$4 == null ? '—' : '${dec(w.$4!)} kg', style: cell)),
                    const SizedBox(),
                  ],
                ),
            ],
          ),
        _Title('Πώς διαβάζεται'),
        Text(
          'Μεσαία τιμή: οι μισές μέρες είναι πάνω και οι μισές κάτω από αυτή. «Συνήθως»: το εύρος όπου βρίσκονται '
          '8 στις 10 μέρες. «Διαφορά από τους 3 προηγούμενους μήνες»: γράφεται μόνο όταν περνά στατιστικό έλεγχο '
          '(επίπεδο 1%, με διόρθωση για τη συσχέτιση διαδοχικών ημερών)· αλλιώς «Σταθερό», και «—» όταν δεν υπάρχουν '
          'αρκετές μετρήσεις. Οι νύχτες χρονολογούνται με την ημερομηνία του πρωινού.',
          style: TextStyle(fontSize: 8.8, color: c.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 6),
        Text(
          'Πώς μετρήθηκαν: ρολόι Samsung Galaxy Watch Ultra 2 (καρπός) και ζυγαριά InBody H40 (ρεύμα στο σώμα), '
          'μέσω Samsung Health. Παλμοί στον ύπνο: μέσος όρος των μετρήσεων του ρολογιού στον ύπνο. Οξυγόνο: αισθητήρας '
          'καρπού· το «ελάχιστο» είναι μία μεμονωμένη μέτρηση, όχι οξυμετρία. Διάρκεια ύπνου: όπως τη μέτρησε η Samsung, '
          'χωρίς εκτιμήσεις της εφαρμογής. Δεν περιλαμβάνονται HRV και παλμοί ηρεμίας: η Samsung δεν τα δίνει σε άλλες εφαρμογές.',
          style: TextStyle(fontSize: 8.8, color: c.textSecondary, height: 1.4),
        ),
        const Spacer(),
        _Footer(data: d, page: 1),
      ],
    );
  }
}

MetricDef? _def(String key) {
  for (final m in trendMetrics) {
    if (m.key == key) return m;
  }
  return null;
}

// --- Σελίδα 2: γραφήματα ---

class _PageTwo extends StatelessWidget {
  const _PageTwo({required this.data});
  final ReportData data;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.light;
    final d = data;

    Widget chart(String title, String key, Color color, String Function(double) fmt, double minRange,
        {double? reference, String? note}) {
      final s = d.stat(key);
      final med = s.median;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title(title),
          if (s.n < 2)
            SizedBox(
              height: 96,
              child: Center(
                child: Text('Λίγες μετρήσεις για γράφημα.', style: TextStyle(color: c.textTertiary)),
              ),
            )
          else
            LineChart(
              height: 96,
              points: s.values,
              color: color,
              format: fmt,
              minRange: minRange,
              dateLabel: dayMonth,
              levels: [
                if (med != null) (s.values.first.$1, s.values.last.$1, med, c.textSecondary),
                if (reference != null) (s.values.first.$1, s.values.last.$1, reference, c.bad),
              ],
            ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(note, style: TextStyle(fontSize: 8, color: c.textTertiary)),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(data: d, page: 2),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Μία τιμή ανά νύχτα ή μέρα. Γκρι διακεκομμένη: η μεσαία τιμή του διαστήματος.',
            style: TextStyle(fontSize: 8.8, color: c.textSecondary),
          ),
        ),
        chart('Παλμοί στον ύπνο (bpm)', K.sleepHr, c.heart, (v) => v.round().toString(), 8),
        chart('Οξυγόνο στον ύπνο, μέσο ανά νύχτα (%)', K.spo2Avg, c.energy, (v) => v.round().toString(), 4),
        chart(
          'Οξυγόνο στον ύπνο, ελάχιστο ανά νύχτα (%)',
          K.spo2Min,
          c.energy,
          (v) => v.round().toString(),
          8,
          reference: 90,
          note: 'Κόκκινη διακεκομμένη: 90%.',
        ),
        chart('Διάρκεια ύπνου (ώρες:λεπτά)', K.sleepMin, c.sleep, (v) {
          final m = v.round();
          return '${m ~/ 60}:${two(m % 60)}';
        }, 120),
        chart('Βήματα ανά μέρα', K.steps, c.move, (v) => thousands(v), 4000),
        const Spacer(),
        _Footer(data: d, page: 2),
      ],
    );
  }
}
