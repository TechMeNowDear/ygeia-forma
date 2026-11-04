import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../oxygen_note.dart' show lowestText;
import '../report.dart';
import '../samsung.dart';
import '../sources.dart';
import '../theme.dart';
import '../trends.dart';
import '../widgets.dart';

/// Αναφορά για γιατρό: προεπισκόπηση των σελίδων A4 και αποθήκευση ως PDF στις Λήψεις.
class ReportPage extends StatefulWidget {
  const ReportPage({super.key, required this.store, this.now, this.note = '', this.end});
  final HealthStore store;
  final DateTime? now;

  /// Η τελευταία μέρα του διαστήματος (από τις Τάσεις: η ίδια μέρα με αυτές, έλεγχος υπολογισμών C12).
  final DateTime? end;

  /// Αρχική σημείωση (για δοκιμές· στην εφαρμογή γράφεται στην οθόνη).
  final String note;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final _keys = [for (var i = 0; i < _pageCount; i++) GlobalKey()];
  bool _saving = false;
  String? _uri;
  String? _error;

  /// Σημείωση για τον γιατρό (φάρμακα, κάπνισμα…). Δεν αποθηκεύεται: γράφεται μόνο στο PDF.
  late String _note = widget.note;
  late final _noteField = TextEditingController(text: widget.note);

  /// Όνομα στην αναφορά (προαιρετικό, δεύτερος κλινικός έλεγχος M6): μένει ΜΟΝΟ στο κινητό (στις ρυθμίσεις, όχι
  /// στο αρχείο αντιγράφου ασφαλείας, ποτέ σε αναφορά σφάλματος), για να μη γράφεται κάθε φορά.
  late String _name = widget.store.prefs.reportName ?? '';
  late final _nameField = TextEditingController(text: _name);

  void _keepName() {
    final v = _name.trim();
    final stored = widget.store.prefs.reportName ?? '';
    if (v == stored) return;
    widget.store.prefs.reportName = v.isEmpty ? null : v;
    widget.store.savePrefsNow();
  }

  @override
  void dispose() {
    _keepName();
    _noteField.dispose();
    _nameField.dispose();
    super.dispose();
  }

  late final ReportData _data =
      buildReport(widget.store.history, widget.now ?? DateTime.now(), plan: widget.store.analysisPlan, end: widget.end);

  String get _fileName {
    final t = _data.created;
    return 'Αναφορά υγείας ${t.year}-${two(t.month)}-${two(t.day)}.pdf';
  }

  Future<void> _save() async {
    _keepName();
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
    final name = _name.trim();
    final pages = [
      _PageOne(data: _data, note: _note.trim(), name: name),
      _PageTwo(data: _data, name: name),
      _PageThree(data: _data, name: name),
    ];

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
                      'Οι τελευταίοι 3 μήνες σε τρεις σελίδες A4, για να τις δείξεις ή να τις στείλεις στον γιατρό σου. '
                      'Μετρήσεις από ρολόι και ζυγαριά, με σύγκριση με τους προηγούμενους μήνες. Χωρίς διάγνωση. '
                      // Κλινικός έλεγχος H2 και M6 (4/11).
                      'Δεν περιέχει ΗΚΓ, ειδοποιήσεις ρυθμού, τεστ άπνοιας ή μετρήσεις πίεσης· τα αποτελέσματα του Samsung '
                      'Health Monitor τα δείχνεις από εκεί.',
                      style: TextStyle(color: c.textSecondary, fontSize: 14.5, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('report-name'),
                      controller: _nameField,
                      maxLength: reportNameMax,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Όνομα στην αναφορά (προαιρετικά)',
                        helperText: 'Μένει μόνο σε αυτό το κινητό.',
                      ),
                      onChanged: (v) => setState(() {
                        _name = v;
                        _uri = null;
                      }),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('report-note'),
                      controller: _noteField,
                      maxLength: reportNoteMax,
                      maxLines: 4,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Σημείωση για τον γιατρό (προαιρετικά)',
                        // Δεύτερος κλινικός έλεγχος M6: φάρμακα, ροχαλητό και τεστ άπνοιας χωράνε και φαίνονται.
                        hintText: 'π.χ. φάρμακα και δόση, κάπνισμα, ροχαλητό, τεστ άπνοιας (ημερομηνία, αποτέλεσμα)',
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

/// Σημείωση ως 400 χαρακτήρες (πριν 160: δεν χωρούσαν φάρμακα, ροχαλητό και τεστ άπνοιας μαζί) και όνομα ως 60.
const reportNoteMax = 400;
const reportNameMax = 60;

/// Σελίδες: 1 σύνοψη και ορισμοί, 2 γραφήματα, 3 οξυγόνο και ζυγίσεις (από 4/11, για να χωρούν οι εξηγήσεις).
const _pageCount = 3;

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
  const _Header({required this.data, required this.page, this.name = ''});
  final ReportData data;
  final int page;

  /// Το όνομα (αν γράφτηκε), σε κάθε σελίδα: οι σελίδες τυπώνονται και μπαίνουν χωριστά στον φάκελο.
  final String name;

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
                    switch (page) {
                      1 => 'Αναφορά υγείας',
                      2 => 'Αναφορά υγείας · γραφήματα',
                      _ => 'Αναφορά υγείας · οξυγόνο και ζυγίσεις',
                    },
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${name.isEmpty ? '' : '$name · '}${dayMonth(data.from)} – ${dayMonthYear(data.to)} · $reportDays ημέρες',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
            data.plan?.hasOura == true
                ? 'Μετρήσεις από ρολόι, δαχτυλίδι και ζυγαριά· δεν είναι ιατρικές μετρήσεις.'
                : 'Μετρήσεις από ρολόι και ζυγαριά μέσω Samsung Health· δεν είναι ιατρικές μετρήσεις.',
            style: TextStyle(fontSize: 8, color: c.textTertiary),
          ),
        ),
        Text(
          'Δημιουργήθηκε ${t.day}/${t.month}/${t.year} · σελίδα $page από $_pageCount',
          style: TextStyle(fontSize: 8, color: c.textTertiary),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text, {this.top = 14});
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.light;
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 6),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.text)),
    );
  }
}

// --- Σελίδα 1: πίνακας ---

class _PageOne extends StatelessWidget {
  const _PageOne({required this.data, this.note = '', this.name = ''});
  final ReportData data;
  final String note;
  final String name;

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

    final plan = d.plan ?? SourcePlan.samsungOnly;
    final withOura = plan.hasOura;
    // Ορισμοί και μονάδες σε κάθε γραμμή (κλινικός έλεγχος H3/H4, 4/11).
    final rows = <(String, String, String Function(double), MetricDef?)>[
      ('Παλμοί στον ύπνο, μέσος όρος νύχτας (bpm)', K.sleepHr, num0, _def(K.sleepHr)),
      if (withOura) ('Χαμηλότεροι παλμοί στον ύπνο (bpm)', K.lowHr, num0, _def(K.lowHr)),
      if (withOura) ('HRV νύχτας, RMSSD, μέσος όρος (ms)', K.hrv, num0, _def(K.hrv)),
      if (withOura) ('Αναπνοές στον ύπνο (ανά λεπτό)', K.breath, (v) => dec(v), _def(K.breath)),
      ('Οξυγόνο στον ύπνο, μέσο νύχτας (%)', K.spo2Avg, pct, _def(K.spo2Avg)),
      // Ποτέ στρογγυλοποίηση προς τα πάνω (έλεγχος υπολογισμών C5, κλινικός L2): μεσαία 89,5 → «89,5%», όχι «90%».
      ('Οξυγόνο, χαμηλότερη μεμονωμένη μέτρηση νύχτας (%)', K.spo2Min, (v) => '${lowestText(v)}%', null),
      ('Διάρκεια ύπνου, χωρίς τα ξυπνήματα (ώρες:λεπτά)', K.sleepMin, dur, _def(K.sleepMin)),
      ('Ώρα που κοιμήθηκε (ώρα:λεπτά)', K.bedtime, clockFromSix, _def(K.bedtime)),
      ('Ώρα που ξύπνησε (ώρα:λεπτά)', K.wake, clockFromSix, null),
      ('Βήματα ανά μέρα', K.steps, (v) => thousands(v), _def(K.steps)),
    ];
    // Η πηγή κάθε δείκτη, γραμμένη στη γραμμή του (απόφαση 2/11· από 4/11 και χωρίς Oura). Μετά από αλλαγή πηγής:
    // «από τις …». Τα βήματα είναι το σύνολο της Samsung Health (ρολόι και κινητό, χωρίς διπλομέτρηση).
    String label((String, String, String Function(double), MetricDef?) r) {
      final s = d.stat(r.$2);
      final since = s.since == null ? '' : ', από ${s.since!.day}/${s.since!.month}';
      return '${r.$1} · ${metricSourceName(r.$2, s.source)}$since';
    }

    // Οξυγόνο με αλλαγή ορισμού της νύχτας: μία γραμμή για κάθε ορισμό (δεύτερος κλινικός έλεγχος K1), όλες οι 90 μέρες.
    // Σύντομα, για να χωρά η σελίδα 1· ο πλήρης ορισμός είναι στη σελίδα 3.
    String night(ReportPeriod p) => p.oldRules
        ? 'παλιός κανόνας νύχτας'
        : (p.night == Source.oura ? 'νύχτα = ώρες ύπνου Oura' : 'νύχτα = ύπνος ρολογιού');
    String periodLabel(ReportPeriod p, bool first) =>
        first ? 'ως ${p.to.day}/${p.to.month}: ${night(p)}' : '  ↳ από ${p.from.day}/${p.from.month}: ${night(p)}';

    final header = TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: c.textSecondary);
    final cell = TextStyle(fontSize: 9.5, color: c.text, fontFeatures: tabular);
    final bold = cell.copyWith(fontWeight: FontWeight.w700);
    final small = TextStyle(fontSize: 8.8, color: c.textSecondary, height: 1.4);

    // Πυκνότερες γραμμές (3 αντί 4,5): με Oura, δύο γραμμές οξυγόνου ανά ορισμό και σημείωση 400 χαρακτήρων η σελίδα
    // 1 πρέπει να χωρά.
    Widget pad(Widget w) => Padding(padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4), child: w);

    String trendText(ReportStat s, MetricDef? def) {
      final t = s.trend;
      if (def == null || t == null || t.status == TrendStatus.insufficient) return '—';
      if (t.status == TrendStatus.stable) return 'Σταθερό';
      if (t.status == TrendStatus.sourceChange && t.rereading) return 'Ενημερώνεται το ιστορικό';
      if (t.status == TrendStatus.sourceChange) return definitionMetrics.contains(def.key) ? 'Αλλαγή ορισμού' : 'Αλλαγή συσκευής';
      final up = t.status == TrendStatus.up;
      if (def.kind == ValueKind.clock) return '${def.formatDiff(t.displayDiff!)} ${up ? 'αργότερα' : 'νωρίτερα'}';
      return '${up ? '↑' : '↓'} ${def.formatDiff(t.displayDiff!)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(data: d, page: 1, name: name),
        if (note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Σημείωση: $note',
              key: const ValueKey('report-note-text'),
              // 400 χαρακτήρες χωράνε σε 5 γραμμές· ποτέ κομμένη σημείωση στον γιατρό.
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, color: c.text, height: 1.25),
            ),
          ),
        // Κλινικός έλεγχος H2 (4/11): η απουσία ρυθμού/άπνοιας εδώ δεν σημαίνει ότι ήταν φυσιολογικά.
        Container(
          key: const ValueKey('report-not-included'),
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(4)),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Δεν περιλαμβάνονται: ', style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
              // Δεύτερος κλινικός έλεγχος M6: και η πίεση (η πρώτη ερώτηση του καρδιολόγου).
              const TextSpan(
                text: 'ΗΚΓ, ειδοποιήσεις ακανόνιστου ρυθμού και τεστ άπνοιας του Samsung Health Monitor, και μετρήσεις '
                    'πίεσης. Η εφαρμογή δεν έχει πρόσβαση σε αυτά, άρα η απουσία τους εδώ δεν σημαίνει ότι ήταν '
                    'φυσιολογικά. Αν υπάρχουν, δείτε τα αποτελέσματα στο Samsung Health Monitor.',
              ),
            ]),
            style: TextStyle(fontSize: 9, color: c.text, height: 1.35),
          ),
        ),
        _Title('Σύνοψη', top: 10),
        Table(
          columnWidths: const {
            0: FlexColumnWidth(3.0),
            1: FlexColumnWidth(1.1),
            2: FlexColumnWidth(1.6),
            3: FlexColumnWidth(1.6),
            4: FlexColumnWidth(0.8),
            5: FlexColumnWidth(1.4),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder(horizontalInside: BorderSide(color: c.hairline, width: 0.8)),
          children: [
            TableRow(
              decoration: BoxDecoration(color: c.background),
              children: [
                pad(Text('Δείκτης · πηγή', style: header)),
                pad(Text('Μεσαία τιμή', style: header)),
                pad(Text('Συνήθως\n(8 στις 10 μέρες)', style: header)),
                pad(Text('Χαμηλότερη –\nυψηλότερη', style: header)),
                // Μία λέξη: το «Μέρες με / μέτρηση» έσπαγε στη μέση της λέξης (έλεγχος UX U3).
                pad(Text('Μέρες', style: header)),
                pad(Text('Διαφορά από τους\n3 προηγ. μήνες', style: header)),
              ],
            ),
            for (final r in rows)
              for (final (i, part) in <ReportPeriod?>[if (d.stat(r.$2).periods.isEmpty) null else ...d.stat(r.$2).periods].indexed)
                () {
                  final whole = d.stat(r.$2);
                  final s = part?.stat ?? whole;
                  final f = r.$3;
                  final last = part == null || i == whole.periods.length - 1;
                  return TableRow(
                    children: [
                      pad(Text(
                        part == null ? label(r) : (i == 0 ? '${label(r)}\n${periodLabel(part, true)}' : periodLabel(part, false)),
                        style: cell,
                      )),
                      pad(Text(s.median == null ? '—' : f(s.median!), style: bold)),
                      pad(Text(s.p10 == null ? '—' : '${f(s.p10!)} – ${f(s.p90!)}', style: cell)),
                      pad(Text(s.low == null ? '—' : '${f(s.low!)} – ${f(s.high!)}', style: cell)),
                      pad(Text('${s.n}', style: cell)),
                      pad(Text(last ? trendText(whole, r.$4) : '', style: cell)),
                    ],
                  );
                }(),
          ],
        ),
        _Title('Πώς διαβάζεται', top: 8),
        Text(
          // Έλεγχος υπολογισμών F9 (4/11): χωρίς ισχυρισμό «1%»· είναι ένδειξη ανά δείκτη.
          // Δεύτερος έλεγχος υπολογισμών C4 (D8): ο έλεγχος είναι κατά προσέγγιση· στους 3 μήνες πιάνει και αργές μεταβολές.
          'Μεσαία τιμή: οι μισές μέρες πάνω, οι μισές κάτω. «Συνήθως»: εκεί βρίσκονται 8 στις 10 μέρες. «Διαφορά»: '
          'ένδειξη αλλαγής ανά δείκτη, μόνο όταν η διαφορά των μεσαίων τιμών ξεπερνά ένα ελάχιστο και, κατά προσέγγιση, '
          'τις συνηθισμένες μέρα-με-μέρα διακυμάνσεις (στατιστικός έλεγχος με διόρθωση για τη συσχέτιση διαδοχικών '
          'ημερών)· μπορεί να είναι και αργή μεταβολή εβδομάδων. Αλλιώς «Σταθερό» (δεν φάνηκε καθαρή αλλαγή), ή «—» όταν '
          'οι μετρήσεις είναι λίγες. Δεν είναι κλινικό όριο, και με πολλούς δείκτες μαζί κάποια ένδειξη μπορεί να είναι '
          'τυχαία. Οι νύχτες έχουν την ημερομηνία του πρωινού. Πώς μετρήθηκαν, ορισμοί, οξυγόνο και ζυγίσεις: σελίδα 3.',
          style: small.copyWith(fontSize: 8.2, height: 1.35),
        ),
        const Spacer(),
        _Footer(data: d, page: 1),
      ],
    );
  }
}

// --- Σελίδα 3: οξυγόνο και ζυγίσεις ---

class _PageThree extends StatelessWidget {
  const _PageThree({required this.data, this.name = ''});
  final ReportData data;
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.light;
    final d = data;
    final header = TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: c.textSecondary);
    final cell = TextStyle(fontSize: 9.5, color: c.text, fontFeatures: tabular);
    final bold = cell.copyWith(fontWeight: FontWeight.w700);
    final small = TextStyle(fontSize: 8.8, color: c.textSecondary, height: 1.4);
    Widget pad(Widget w) => Padding(padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4), child: w);
    final minN = d.stat(K.spo2Min).n;
    final avgN = d.stat(K.spo2Avg).n;
    final plan = d.plan ?? SourcePlan.samsungOnly;
    final withOura = plan.hasOura;
    final below85 = d.oxygenBelow(85);
    final periods = d.stat(K.spo2Min).periods;
    String dmy(DateTime t) => '${t.day}/${t.month}/${t.year}';
    // Έλεγχος 2, C4: πριν από το όριο της επανανάγνωσης, ο παλιός κανόνας της νύχτας («Ενημερώνεται το ιστορικό»).
    String definition(ReportPeriod p) => p.oldRules
        ? 'τον παλιό κανόνα ύπνου του ρολογιού (ενημερώνεται το ιστορικό)'
        : (p.night == Source.oura ? 'τις ώρες ύπνου του Oura' : 'τον ύπνο του ρολογιού');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(data: d, page: 3, name: name),
        // Δεύτερος κλινικός έλεγχος M4: ζώνες 90/85/80%, νύχτες κάτω από 85% με χρονολογική σειρά, αναφορά με SD.
        _Title('Χαμηλότερη μεμονωμένη μέτρηση οξυγόνου ανά νύχτα (ρολόι, καρπός)'),
        Text(
          'Μία τιμή ανά νύχτα από τον αισθητήρα του καρπού: όχι ιατρική οξυμετρία, όχι δείκτης αποκορεσμών (ODI), όχι '
          'χρόνος κάτω από 90% (T90). Αναφορά: σε 350 υγιή άτομα (1 μηνός–85 ετών, οξύμετρο δαχτύλου, χωρίς τα σφάλματα '
          'κίνησης) το ελάχιστο της νύχτας ήταν 90,4% ± 3,1% (Gries & Brooks, Chest 1996).',
          style: TextStyle(fontSize: 9.5, color: c.text, height: 1.4),
        ),
        const SizedBox(height: 6),
        Text(
          'Νύχτες με μέτρηση: $minN · κάτω από 90%: ${d.lowOxygenNights.length} · κάτω από 85%: ${below85.length} · '
          'κάτω από 80%: ${d.oxygenBelow(80).length}.',
          key: const ValueKey('report-oxygen-counts'),
          style: cell,
        ),
        const SizedBox(height: 4),
        if (below85.isEmpty)
          Text('Καμία νύχτα κάτω από 85%.', style: cell)
        else ...[
          Text('Νύχτες κάτω από 85%:', style: cell),
          const SizedBox(height: 2),
          Wrap(
            key: const ValueKey('report-oxygen-below85'),
            spacing: 14,
            runSpacing: 2,
            children: [
              // Ποτέ στρογγυλοποίηση προς τα πάνω (έλεγχος υπολογισμών F16): 84,6 → «84,6%».
              for (final n in below85.take(30)) Text('${dmy(n.$1)}: ${lowestText(n.$2)}%', style: bold),
              if (below85.length > 30) Text('και ${below85.length - 30} ακόμα (γράφημα, σελίδα 2)', style: cell),
            ],
          ),
        ],
        if (periods.length > 1) ...[
          const SizedBox(height: 6),
          // Δεύτερος κλινικός έλεγχος K1: ίδιος αισθητήρας, άλλος ορισμός της νύχτας· όλες οι νύχτες φαίνονται.
          Text(
            '${[
              for (final (i, p) in periods.indexed)
                i == 0
                    ? 'Ως ${p.to.day}/${p.to.month} η νύχτα ορίζεται από ${definition(p)}'
                    : 'από ${p.from.day}/${p.from.month} από ${definition(p)}',
            ].join('· ')}. Ο αισθητήρας οξυγόνου είναι ο ίδιος (καρπός).',
            key: const ValueKey('report-oxygen-definition'),
            style: small,
          ),
        ],
        if (minN != avgN) ...[
          const SizedBox(height: 6),
          Text(
            'Μέσο οξυγόνο: $avgN νύχτες· χαμηλότερη μέτρηση: $minN. Η χαμηλότερη λείπει όταν η Samsung δεν δίνει '
            'αναλυτικές τιμές για τη νύχτα.',
            style: small,
          ),
        ],
        _Title('Ζυγίσεις (InBody H40)'),
        if (d.weighIns.isEmpty)
          Text('Δεν υπάρχουν ζυγίσεις.', style: cell)
        else
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1.6),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(1.6),
              3: FlexColumnWidth(2.0),
              4: FlexColumnWidth(1.6),
            },
            border: TableBorder(horizontalInside: BorderSide(color: c.hairline, width: 0.8)),
            children: [
              TableRow(
                decoration: BoxDecoration(color: c.background),
                children: [
                  pad(Text('Ημερομηνία', style: header)),
                  pad(Text('Βάρος (kg)', style: header)),
                  // Κλινικός έλεγχος M5 (4/11).
                  pad(Text('Λίπος (BIA, εκτίμηση)', style: header)),
                  pad(Text('Σκελετικοί μύες (BIA, εκτίμηση)', style: header)),
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
        const SizedBox(height: 6),
        Text(
          'Λίπος και μύες: εκτίμηση βιοηλεκτρικής αντίστασης (BIA) της ζυγαριάς InBody H40, όχι DXA. Επηρεάζονται από '
          'το νερό, το φαγητό και την άσκηση.',
          style: small,
        ),
        _Title('Πώς μετρήθηκαν'),
        Text(
          // Ένας ορισμός διάρκειας ύπνου παντού (έλεγχος 4/11): πραγματικός ύπνος, χωρίς τα ξυπνήματα. Βήματα: το σύνολο
          // της Samsung Health, όχι «μόνο ρολόι» (A2).
          withOura
              ? 'Κάθε δείκτης από μία συσκευή, ποτέ ανάμειξη. Ύπνος, παλμοί ύπνου, HRV, αναπνοές: '
                  'Oura Ring 5 (δάχτυλο) από ${plan.ouraFrom!.day}/${plan.ouraFrom!.month}/${plan.ouraFrom!.year}· πριν, '
                  'Galaxy Watch Ultra 2. Διάρκεια ύπνου: πραγματικός ύπνος, χωρίς τα ξυπνήματα (και στις δύο συσκευές). '
                  'Οξυγόνο: Galaxy Watch Ultra 2 (αισθητήρας καρπού)· «χαμηλότερη μεμονωμένη μέτρηση», όχι οξυμετρία. '
                  'Βήματα: $samsungTotalLabel. Ζυγίσεις: InBody H40. Μετά από αλλαγή συσκευής μετρούν μόνο οι μέρες '
                  'της νέας.'
              : 'Galaxy Watch Ultra 2 (καρπός) και ζυγαριά InBody H40, μέσω Samsung Health. Οξυγόνο: '
                  'αισθητήρας καρπού· «χαμηλότερη μεμονωμένη μέτρηση», όχι οξυμετρία. Διάρκεια ύπνου: πραγματικός ύπνος '
                  'από τις φάσεις της Samsung, χωρίς τα ξυπνήματα. Βήματα: $samsungTotalLabel. Χωρίς HRV και παλμούς '
                  'ηρεμίας: η Samsung δεν τα δίνει σε άλλες εφαρμογές.',
          style: small,
        ),
        if (d.nightsWithoutStages > 0) ...[
          const SizedBox(height: 6),
          // Δεύτερος έλεγχος υπολογισμών C10: η διάρκεια μετρά μόνο νύχτες με φάσεις· το λέμε, με πόσες λείπουν.
          Text(
            'Νύχτες χωρίς φάσεις δεν μετρούν στη διάρκεια ύπνου (${countText(d.nightsWithoutStages, 'νύχτα', 'νύχτες')}).',
            key: const ValueKey('report-unstaged'),
            style: small,
          ),
        ],
        const SizedBox(height: 6),
        Text(
          // Κλινικός έλεγχος H4 (4/11).
          'Παλμοί στον ύπνο = μέσος όρος όλου του ύπνου, όχι παλμοί ηρεμίας σε εγρήγορση.'
          '${withOura ? ' HRV = RMSSD, μέσος όρος της νύχτας από το Oura· δεν συγκρίνεται με τιμές Holter 24ώρου.' : ''}',
          style: small,
        ),
        const Spacer(),
        _Footer(data: d, page: 3),
      ],
    );
  }
}

MetricDef? _def(String key) => metricDef(key);

// --- Σελίδα 2: γραφήματα ---

class _PageTwo extends StatelessWidget {
  const _PageTwo({required this.data, this.name = ''});
  final ReportData data;
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.light;
    final d = data;

    Widget chart(String title, String key, Color color, String Function(double) fmt, double minRange,
        {double? reference, String? note}) {
      final s = d.stat(key);
      final med = s.median;
      // Οξυγόνο με αλλαγή ορισμού της νύχτας: μία μεσαία τιμή για κάθε ορισμό (όχι μία πάνω από την αλλαγή).
      final parts = s.periods.where((p) => p.stat.n > 0).toList();
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
                if (parts.isEmpty && med != null) (s.values.first.$1, s.values.last.$1, med, c.textSecondary),
                for (final p in parts) (p.stat.values.first.$1, p.stat.values.last.$1, p.stat.median!, c.textSecondary),
              ],
              // Διάστικτη με ετικέτα, ώστε να ξεχωρίζει από τη διακεκομμένη μεσαία τιμή (δεύτερος κλινικός έλεγχος M5).
              reference: reference == null ? null : (reference, '${reference.round()}%', c.textTertiary),
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
        _Header(data: d, page: 2, name: name),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Μία τιμή ανά νύχτα ή μέρα. Γκρι διακεκομμένη: η μεσαία τιμή του διαστήματος.',
            style: TextStyle(fontSize: 8.8, color: c.textSecondary),
          ),
        ),
        chart('Παλμοί στον ύπνο, μέσος όρος νύχτας (bpm)', K.sleepHr, c.heart, (v) => v.round().toString(), 8),
        chart('Οξυγόνο στον ύπνο, μέσο ανά νύχτα (%)', K.spo2Avg, c.energy, (v) => v.round().toString(), 4),
        chart(
          'Οξυγόνο, χαμηλότερη μεμονωμένη μέτρηση ανά νύχτα (%, καρπός)',
          K.spo2Min,
          c.energy,
          lowestText,
          8,
          reference: 90,
          // Κλινικός έλεγχος H6 και M5: γκρι διάστικτη γραμμή αναφοράς, όχι κόκκινο «όριο».
          note: 'Διάστικτη γραμμή: αναφορά 90% (όχι διαγνωστικό όριο). Διακεκομμένη: η μεσαία τιμή'
              '${d.stat(K.spo2Min).periods.length > 1 ? ' κάθε ορισμού της νύχτας (ίδιος αισθητήρας· ορισμοί: σελίδα 3)' : ''}.',
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
