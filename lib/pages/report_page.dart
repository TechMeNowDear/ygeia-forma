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
import '../shown.dart';
import '../sources.dart';
import '../theme.dart';
import '../training/session.dart';
import '../training/symptoms.dart';
import '../training/training_store.dart';
import '../training/wear_link.dart' show HrSummary;
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
    widget.store.setReportName(v.isEmpty ? null : v);
  }

  @override
  void dispose() {
    _keepName();
    _noteField.dispose();
    _nameField.dispose();
    super.dispose();
  }

  /// Από το Samsung Health Monitor (τεστ άπνοιας, ρυθμός, πίεση), όπως τα δίνει η Samsung· μόνο για αυτό το PDF.
  Map<String, dynamic>? _medical;

  @override
  void initState() {
    super.initState();
    // Σελίδα 4 (έλεγχος #2): συμπτώματα και άσκηση από την εφαρμογή, και τα αποτελέσματα του Samsung Health Monitor.
    TrainingStore.main.load().then((_) {
      if (mounted) setState(() {});
    });
    SamsungHealth.medical().then((m) {
      if (mounted) setState(() => _medical = m);
    });
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
      _PageThree(data: _data, name: name, stale: widget.store.prefs.staleMonths),
      _PageFour(data: _data, name: name, training: TrainingStore.main, medical: _medical),
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
                      'Οι τελευταίοι 3 μήνες σε τέσσερις σελίδες A4, για να τις δείξεις ή να τις στείλεις στον γιατρό σου. '
                      'Μετρήσεις από ρολόι και ζυγαριά, με σύγκριση με τους προηγούμενους μήνες, και στη σελίδα 4 τα '
                      'συμπτώματα, οι προπονήσεις και ό,τι δίνει το Samsung Health Monitor (τεστ άπνοιας, ειδοποιήσεις ρυθμού, '
                      'μετρήσεις πίεσης). Χωρίς διάγνωση. Δεν περιέχει ΗΚΓ: τα ΗΚΓ τα εξάγεις ως PDF από το Samsung Health Monitor.',
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
                        // Τρίτος κλινικός έλεγχος C11: και οι χαμηλές τιμές που είδες στο Samsung Health.
                        hintText: 'π.χ. φάρμακα και δόση, κάπνισμα, ροχαλητό, τεστ άπνοιας (ημερομηνία, αποτέλεσμα), '
                            'χαμηλό οξυγόνο που είδες στο Samsung Health (ημερομηνία, τιμή)',
                        hintMaxLines: 3,
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
                    // Περιμένει τη σελίδα 4 (Samsung Health Monitor), για να μη βγει PDF χωρίς αυτά.
                    onPressed: _saving || _medical == null ? null : _save,
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

/// Σελίδες: 1 σύνοψη και ορισμοί, 2 γραφήματα, 3 οξυγόνο και ζυγίσεις (από 4/11, για να χωρούν οι εξηγήσεις),
/// 4 συμπτώματα, άσκηση και Samsung Health Monitor (έλεγχος #2, 8/11).
const _pageCount = 4;

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
                      3 => 'Αναφορά υγείας · οξυγόνο και ζυγίσεις',
                      _ => 'Αναφορά υγείας · συμπτώματα και άσκηση',
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
    // Ποτέ στρογγυλοποίηση προς τα πάνω στο 90% (τρίτος έλεγχος F4): 89,5 → «89,5%».
    String pct(double v) => '${spo2AvgText(v)}%';
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
      ('Οξυγόνο στον ύπνο, μέσο νύχτας (%)${withOura ? ', ρολόι (νύχτες χωρίς δαχτυλίδι)' : ''}', K.spo2Avg, pct, _def(K.spo2Avg)),
      if (withOura) ('Οξυγόνο στον ύπνο, μέσο νύχτας από το δαχτυλίδι (%)', K.ringSpo2, pct, _def(K.ringSpo2)),
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
      // Αλλαγή συσκευής μέσα στις 90 μέρες (έλεγχος 4, C3): η συσκευή γράφεται σε κάθε γραμμή περιόδου.
      if (s.periods.isNotEmpty && reportDeviceKeys.contains(r.$2)) return r.$1;
      final since = s.since == null ? '' : ', από ${s.since!.day}/${s.since!.month}';
      return '${r.$1} · ${metricSourceName(r.$2, s.source)}$since';
    }

    // Οξυγόνο με αλλαγή ορισμού της νύχτας: μία γραμμή για κάθε ορισμό (δεύτερος κλινικός έλεγχος K1), όλες οι 90 μέρες.
    // Σύντομα, για να χωρά η σελίδα 1· ο πλήρης ορισμός είναι στη σελίδα 3.
    String night(ReportPeriod p) => p.oldRules
        ? 'παλιός κανόνας νύχτας'
        : (p.night == Source.oura ? 'νύχτα = ώρες ύπνου Oura' : 'νύχτα = ύπνος ρολογιού');
    String periodLabel(String key, ReportPeriod p, bool first) {
      final what = reportDeviceKeys.contains(key) ? reportPeriodDevice(p) : night(p);
      return first ? 'ως ${p.to.day}/${p.to.month}: $what' : '  ↳ από ${p.from.day}/${p.from.month}: $what';
    }

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

    final body = <Widget>[
      if (note.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Σημείωση: ${reportNoteText(note)}',
            key: const ValueKey('report-note-text'),
            // Ποτέ κομμένη σημείωση στον γιατρό (συγχώνευση 3): ολόκληρη, χωρίς όριο γραμμών και χωρίς «…». Αν μαζί με
            // τον πίνακα δεν χωρά, μικραίνει όλη η σελίδα 1 λίγο (παρακάτω), δεν κόβεται τίποτα.
            softWrap: true,
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
            // Έλεγχος #2 (M2-04): η εφαρμογή διαβάζει άπνοια, ρυθμό και πίεση· μόνο τα ΗΚΓ δεν φτάνουν σε εφαρμογές.
            const TextSpan(
              text: 'ΗΚΓ του ρολογιού (δεν φτάνουν σε άλλες εφαρμογές· δείτε τα στο Samsung Health Monitor). Τεστ άπνοιας, '
                  'ειδοποιήσεις ακανόνιστου ρυθμού και μετρήσεις πίεσης: στη σελίδα 4, όπως τα δίνει η Samsung. Ό,τι λείπει '
                  'εκεί δεν σημαίνει ότι ήταν φυσιολογικό.',
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
                      part == null
                          ? label(r)
                          : (i == 0 ? '${label(r)}\n${periodLabel(r.$2, part, true)}' : periodLabel(r.$2, part, false)),
                      style: cell,
                    )),
                    pad(Text(s.median == null ? '—' : f(s.median!), style: bold)),
                    pad(Text(s.p10 == null ? '—' : '${f(s.p10!)} – ${f(s.p90!)}', style: cell)),
                    pad(Text(s.low == null ? '—' : '${f(s.low!)} – ${f(s.high!)}', style: cell)),
                    pad(Text('${s.n}', style: cell)),
                    pad(Text(
                      !last
                          ? ''
                          : r.$2 == K.spo2Min
                              ? lowestDiffText(whole)
                              // Αλλαγή συσκευής μέσα στις 90 μέρες: ποτέ σύγκριση πάνω από την αλλαγή (και για την ώρα
                              // που ξύπνησε, που αλλιώς δεν έχει «Διαφορά»).
                              : (part != null && reportDeviceKeys.contains(r.$2) ? 'Αλλαγή συσκευής' : trendText(whole, r.$4)),
                      style: cell,
                    )),
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
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(data: d, page: 1, name: name),
        // Συγχώνευση 3: το σώμα της σελίδας 1 στο ύψος του A4. Συνήθως χωρά όπως είναι (κλίμακα 1)· με πολύ μεγάλη
        // σημείωση (400 φαρδιοί χαρακτήρες) μαζί με Oura και δύο ορισμούς οξυγόνου μικραίνει λίγο, αντί να κοπεί η
        // σημείωση ή να βγει έξω από τη σελίδα.
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => FittedBox(
              key: const ValueKey('report-page1-body'),
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: box.maxWidth,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
              ),
            ),
          ),
        ),
        _Footer(data: d, page: 1),
      ],
    );
  }
}

/// Η σημείωση όπως μπαίνει στο PDF: ολόκληρη. Οι αλλαγές γραμμής γίνονται « · » (μία σημείωση 400 χαρακτήρων με
/// 30 σύντομες γραμμές θα έπιανε μισή σελίδα), τα διπλά κενά ένα.
String reportNoteText(String note) =>
    note.trim().replaceAll(RegExp(r'\s*\n\s*'), ' · ').replaceAll(RegExp(r'[ \t]+'), ' ');

// --- Σελίδα 3: οξυγόνο και ζυγίσεις ---

class _PageThree extends StatelessWidget {
  const _PageThree({required this.data, this.name = '', this.stale = const []});
  final ReportData data;
  final String name;

  /// Κομμάτια του ιστορικού που κράτησαν τον παλιό ορισμό του ύπνου (τρίτος έλεγχος F4: σημείωση και στο PDF).
  final List<String> stale;

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
    final below80 = d.oxygenBelow(80);
    // Ως 30 στη λίστα του 85%, αλλά οι κάτω από 80% μπαίνουν πάντα (χρονολογικά).
    final listed85 = [
      ...below80,
      ...below85.where((n) => n.$2 >= 80).take(below80.length >= 30 ? 0 : 30 - below80.length),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
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
          // Τρίτος κλινικός έλεγχος C6: όπως το λέει η περίληψη της πηγής (όχι «οξύμετρο δαχτύλου»), με την ηλικία.
          'χρόνος κάτω από 90% (T90). Αναφορά: σε 350 υγιή άτομα (1 μηνός–85 ετών, ιατρικό οξύμετρο σε εργαστήριο ύπνου, '
          'χωρίς τα σφάλματα κίνησης) το ελάχιστο της νύχτας ήταν 90,4% ± 3,1% (Gries & Brooks, Chest 1996)· στους άνω '
          'των 60 οι τιμές ήταν χαμηλότερες. Δεν συγκρίνεται με τους προηγούμενους μήνες (μία ακραία τιμή ανά νύχτα)· '
          'μετρούν οι νύχτες κάτω από 90, 85 και 80%.',
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
        // Τρίτος κλινικός έλεγχος (F6): ΟΛΕΣ οι νύχτες κάτω από 80% των 90 ημερών, με ημερομηνία, πάντα (ποτέ κρυμμένες
        // στο «και N ακόμα»).
        if (below80.isNotEmpty) ...[
          Text(
            'Νύχτες κάτω από 80% (όλες): ${[for (final n in below80) '${dmy(n.$1)}: ${lowestText(n.$2)}%'].join(' · ')}',
            key: const ValueKey('report-oxygen-below80'),
            style: bold,
          ),
          const SizedBox(height: 4),
        ],
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
              for (final n in listed85) Text('${dmy(n.$1)}: ${lowestText(n.$2)}%', style: bold),
              if (below85.length > listed85.length)
                Text('και ${below85.length - listed85.length} ακόμα (γράφημα, σελίδα 2)', style: cell),
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
                    // Έλεγχος 3, E2: παλιά ζύγιση άλλης πηγής (πριν από την πρώτη της InBody), με την πηγή της.
                    d.otherWeighIns.contains(w.$1) ? pad(Text('όχι InBody', style: small)) : const SizedBox(),
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
                  'Βήματα: $samsungTotalLabel. Ζυγίσεις: InBody H40. Μετά από αλλαγή συσκευής: χωριστή γραμμή για '
                  'κάθε συσκευή, ποτέ ανάμειξη ή σύγκριση ανάμεσά τους.'
              : 'Galaxy Watch Ultra 2 (καρπός) και ζυγαριά InBody H40, μέσω Samsung Health. Οξυγόνο: '
                  'αισθητήρας καρπού· «χαμηλότερη μεμονωμένη μέτρηση», όχι οξυμετρία. Διάρκεια ύπνου: πραγματικός ύπνος '
                  'από τις φάσεις της Samsung, χωρίς τα ξυπνήματα. Βήματα: $samsungTotalLabel. Χωρίς HRV και παλμούς '
                  'ηρεμίας: η Samsung δεν τα δίνει σε άλλες εφαρμογές.',
          style: small,
        ),
        if (stale.isNotEmpty) ...[
          const SizedBox(height: 6),
          // Τρίτος έλεγχος F4: μήνες με τον παλιό ορισμό του ύπνου (όπως στις Τάσεις)· ο γιατρός το βλέπει κι εδώ.
          Text(staleMonthsNote(stale), key: const ValueKey('report-stale-months'), style: small),
        ],
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

/// Η ετικέτα της κάθετης γραμμής στην αρχή της περιόδου [p] στα γραφήματα: η συσκευή («Oura», «ρολόι») ή, για το
/// οξυγόνο (ίδιος αισθητήρας), ο νέος ορισμός της νύχτας.
String reportBreakLabel(String key, ReportPeriod p) {
  if (reportDeviceKeys.contains(key)) return reportPeriodDevice(p);
  if (p.oldRules) return 'παλιός κανόνας';
  return p.night == Source.oura ? 'νύχτα Oura' : 'νύχτα ρολογιού';
}

/// Η συσκευή μιας περιόδου στις γραμμές ύπνου και παλμών ύπνου ([reportDeviceKeys]).
String reportPeriodDevice(ReportPeriod p) {
  final device = switch (p.night) {
    Source.oura => 'Oura',
    Source.watch => 'ρολόι',
    _ => 'χωρίς πηγή',
  };
  return p.oldRules ? '$device, παλιός κανόνας νύχτας' : device;
}

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
          // Κομμένη σειρά (αλλαγή συσκευής): το λέει ο τίτλος, γιατί ο άξονας είναι πια οι ίδιες 90 μέρες για όλα (F6).
          _Title(s.since != null
              ? '$title · μόνο ${metricSourceName(key, s.source)}, από ${s.since!.day}/${s.since!.month}'
              // Αλλαγή συσκευής (έλεγχος 4, C3): κάθε κομμάτι με τη δική του μεσαία τιμή, γραμμένο στον τίτλο.
              : reportDeviceKeys.contains(key) && parts.isNotEmpty
                  ? '$title · ${[
                      for (final (i, p) in s.periods.indexed)
                        if (p.stat.n > 0)
                          '${reportPeriodDevice(p)} ${i == s.periods.length - 1 ? 'από ${p.from.day}/${p.from.month}' : 'ως ${p.to.day}/${p.to.month}'}',
                    ].join(', ')}'
                  : title),
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
              // Ίδιες 90 μέρες σε κάθε γράφημα (τρίτος κλινικός έλεγχος C8/F6): πριν, κάθε γράφημα είχε το δικό του διάστημα.
              from: d.from,
              to: d.to,
              // Έλεγχος 4 (review M1): κομμένη γραμμή και κάθετη ένδειξη σε κάθε αλλαγή συσκευής ή ορισμού.
              breaks: [for (final p in s.periods.skip(1)) (p.from, reportBreakLabel(key, p))],
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
        chart('Οξυγόνο στον ύπνο, μέσο ανά νύχτα (%)', K.spo2Avg, c.energy, spo2AvgText, 4),
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

/// Η «Διαφορά» της γραμμής «χαμηλότερη μέτρηση» (τρίτος κλινικός έλεγχος C9/F6): ποτέ σκέτη «—». Με αλλαγή ορισμού
/// της νύχτας, ίδια λέξη με τη γραμμή του μέσου οξυγόνου· αλλιώς «Δεν συγκρίνεται», με την εξήγηση στη σελίδα 3 (μία
/// ακραία τιμή ανά νύχτα δεν συγκρίνεται ως μεσαία τιμή· μετρούν οι νύχτες κάτω από 90/85/80%).
String lowestDiffText(ReportStat s) {
  if (s.periods.length > 1) {
    return s.periods.any((p) => p.oldRules) ? 'Ενημερώνεται το ιστορικό' : 'Αλλαγή ορισμού';
  }
  return 'Δεν συγκρίνεται (σελ. 3)';
}

// --- Σελίδα 4: συμπτώματα, άσκηση, Samsung Health Monitor (έλεγχος #2: M2-03, M2-04, X3) ---

class _PageFour extends StatelessWidget {
  const _PageFour({required this.data, required this.training, this.medical, this.name = ''});
  final ReportData data;
  final TrainingStore training;
  final Map<String, dynamic>? medical;
  final String name;

  static const _where = {'session': 'στην προπόνηση', 'walk': 'στο περπάτημα', 'watch': 'από το ρολόι', 'check': 'πριν την προπόνηση', 'day': 'στην καθημερινότητα'};

  static String _dt(DateTime d) => '${d.day}/${d.month} ${two(d.hour)}:${two(d.minute)}';

  /// «2026-11-03T02:14:00» → «3/11 02:14».
  static String _isoText(String s) {
    final d = DateTime.tryParse(s);
    return d == null ? s : _dt(d);
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.light;
    final t = training;
    final from = data.from;
    final small = TextStyle(fontSize: 8.6, color: c.textSecondary, height: 1.35);
    final header = TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: c.textSecondary);
    final cell = TextStyle(fontSize: 9, color: c.text, fontFeatures: tabular, height: 1.3);
    Widget pad(Widget w) => Padding(padding: const EdgeInsets.symmetric(vertical: 2.5, horizontal: 4), child: w);
    TableRow head(List<String> l) => TableRow(decoration: BoxDecoration(color: c.background), children: [for (final x in l) pad(Text(x, style: header))]);
    TableRow row(List<String> l, {bool red = false}) =>
        TableRow(children: [for (final (i, x) in l.indexed) pad(Text(x, style: i == 1 && red ? cell.copyWith(fontWeight: FontWeight.w700) : cell))]);
    Table table(Map<int, TableColumnWidth> w, List<TableRow> rows) => Table(
          columnWidths: w,
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder(horizontalInside: BorderSide(color: c.hairline, width: 0.8)),
          children: rows,
        );

    // Οδηγίες γιατρού όπως τις έγραψε ο χρήστης στην εφαρμογή.
    final state = t.approved
        ? 'Η άσκηση εγκρίθηκε${t.approvedAt == null ? '' : ' στις ${t.approvedAt!.day}/${t.approvedAt!.month}'}'
        : t.lockReason == 'red' || t.lockReason == 'amber2'
            ? 'Κλειδωμένη μετά από σύμπτωμα${t.lockedAt == null ? '' : ' (${t.lockedAt!.day}/${t.lockedAt!.month})'}'
            : t.lockReason == 'meds'
                ? 'Κλειδωμένη: νέο φάρμακο για καρδιά ή πίεση'
                : t.waitingTests
                    ? 'Δεν έχει εγκριθεί ακόμα: περιμένει εξετάσεις'
                    : 'Δεν έχει εγκριθεί ακόμα (περιμένει καρδιολόγο)';
    final doctor = [
      state,
      if (t.hrLimit != null) 'όριο παλμών ${t.hrLimit} bpm' else if (t.approved) 'χωρίς όριο παλμών (με την κούραση)',
      if (t.hrMeds) 'παίρνει φάρμακο που κόβει τους παλμούς',
      if (t.limits != null && t.limits!.isNotEmpty) 'περιορισμοί: ${t.limits}',
    ].join(' · ');

    final syms = [
      for (final x in t.symptoms.reversed)
        if (!x.at.isBefore(from)) x,
    ];
    final shownSyms = syms.take(12).toList();

    final sess = [
      for (final s in t.sessions.reversed)
        if (s.finished && !s.start.isBefore(from)) s,
    ];
    final shownSess = sess.take(14).toList();
    final walks = sess.where((s) => s.isCardio).length;

    String hrText(Session s) {
      final h = HrSummary(s, t.hrLimit);
      if (h.avg == null && h.max == null) return '—';
      return '${h.avg ?? '—'} / ${h.max ?? '—'}';
    }

    String overText(Session s) {
      if (t.hrLimit == null || s.hr.isEmpty) return '—';
      final sec = HrSummary(s, t.hrLimit).overSec;
      return sec == 0 ? '0' : '${(sec / 60).ceil()}′';
    }

    // Samsung Health Monitor: χωρίς ερμηνεία, ονόματα πεδίων όπως τα δίνει η Samsung.
    final med = medical;
    final types = (med?['types'] as Map?)?.cast<String, dynamic>();
    String fields(String key, Map<String, dynamic> f) {
      if (key == 'blood_pressure') {
        String? pick(String n) {
          for (final e in f.entries) {
            if (e.key.toUpperCase().contains(n)) return e.value.toString().replaceAll(RegExp(r'\.00$'), '');
          }
          return null;
        }

        final sys = pick('SYSTOLIC'), dia = pick('DIASTOLIC'), pulse = pick('PULSE');
        if (sys != null && dia != null) return '$sys/$dia mmHg${pulse == null ? '' : ' · σφυγμοί $pulse'}';
      }
      final keep = [
        for (final e in f.entries)
          if (!RegExp(r'TIME|ZONE|UID|OFFSET', caseSensitive: false).hasMatch(e.key)) '${e.key.toLowerCase()}: ${e.value}',
      ];
      return keep.isEmpty ? '(χωρίς πεδία)' : keep.take(4).join(' · ');
    }

    Widget samsung(String key, String title) {
      final o = (types?[key] as Map?)?.cast<String, dynamic>();
      final st = o?['state'] as String?;
      final items = [for (final i in (o?['items'] as List? ?? const [])) (i as Map).cast<String, dynamic>()];
      final String? line = med == null
          ? 'Διαβάζεται…'
          : med['ok'] != true
              ? 'Δεν διαβάστηκε από το Samsung Health (${med['message'] ?? 'σφάλμα'}).'
              : switch (st) {
                  'no_permission' => 'Δεν έχει δοθεί άδεια στην εφαρμογή.',
                  'unsupported' => 'Δεν υποστηρίζεται σε αυτή την έκδοση του Samsung Health.',
                  'error' => 'Δεν διαβάστηκε (σφάλμα).',
                  'empty' => 'Καμία καταγραφή στις ${med['days'] ?? 120} μέρες.',
                  _ => null,
                };
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(top: 5, bottom: 2),
          child: Text(title, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: c.text)),
        ),
        if (line != null)
          Text(line, style: small)
        else
          for (final i in items.take(key == 'blood_pressure' ? 8 : 6))
            Text('${_isoText(i['t'] as String? ?? '')} · ${fields(key, (i['f'] as Map? ?? const {}).cast<String, dynamic>())}', style: cell),
        if (line == null && items.length > (key == 'blood_pressure' ? 8 : 6))
          Text('και ${items.length - (key == 'blood_pressure' ? 8 : 6)} ακόμα', style: small),
      ]);
    }

    final body = <Widget>[
      _Title('Οδηγίες γιατρού στην εφαρμογή', top: 4),
      Text(doctor, key: const ValueKey('report-doctor'), style: cell),
      _Title('Συμπτώματα («Νιώθω κάτι»), τελευταίοι 3 μήνες'),
      if (syms.isEmpty)
        Text('Καμία καταγραφή.', style: small)
      else ...[
        table(const {0: FixedColumnWidth(62), 1: FlexColumnWidth(4), 2: FlexColumnWidth(1.6), 3: FixedColumnWidth(52)}, [
          head(['Πότε', 'Τι ένιωσε (όπως το διάλεξε)', 'Πού', 'Βαθμίδα']),
          for (final x in shownSyms)
            row([
              _dt(x.at),
              x.code == watchCode ? '«Νιώθω κάτι» στο ρολόι, χωρίς λεπτομέρειες ακόμα' : x.text,
              _where[x.where] ?? '',
              x.code == watchCode ? '—' : (x.red ? 'σοβαρό' : 'άλλο'),
            ], red: x.red),
        ]),
        if (syms.length > shownSyms.length) Text('και ${syms.length - shownSyms.length} παλαιότερα', style: small),
      ],
      _Title('Άσκηση με την εφαρμογή, τελευταίοι 3 μήνες'),
      Text(
        sess.isEmpty
            ? 'Καμία καταγραφή.'
            : '${sess.length - walks} προπονήσεις με βάρη, $walks περπατήματα. Παλμοί από το ρολόι (καρπός): στα βάρη ο '
                'καρπός συχνά μετρά πιο χαμηλά από τους πραγματικούς.',
        style: small,
      ),
      if (shownSess.isNotEmpty) ...[
        const SizedBox(height: 3),
        table(const {
          0: FixedColumnWidth(62),
          1: FlexColumnWidth(2.6),
          2: FixedColumnWidth(40),
          3: FixedColumnWidth(70),
          4: FixedColumnWidth(54),
          5: FixedColumnWidth(48),
        }, [
          head(['Πότε', 'Τι', 'Λεπτά', 'Παλμοί\nμέσος / υψηλ.', 'Πάνω από\nτο όριο', 'Μεγαλύτ.\nκενό']),
          for (final s in shownSess)
            row([
              _dt(s.start),
              '${s.isCardio ? 'Περπάτημα' : s.name}${s.isCardio || s.setsDone == 0 ? '' : ', ${s.setsDone} σετ'}'
                  '${s.stopped ? ' · σταμάτησε: σύμπτωμα' : ''}',
              '${s.isCardio ? (s.cardioMinutes ?? 0) : s.duration.inMinutes}',
              hrText(s),
              overText(s),
              s.hrGap == null ? '—' : (s.hrGap! < 120 ? '${s.hrGap}″' : '${(s.hrGap! / 60).round()}′'),
            ], red: s.stopped),
        ]),
        if (sess.length > shownSess.length) Text('και ${sess.length - shownSess.length} παλαιότερες', style: small),
        Text('«Μεγαλύτερο κενό»: πόση ώρα το πολύ δεν έφτασαν παλμοί από το ρολόι (τόσο μπορεί να άργησε η ειδοποίηση ορίου).',
            style: small),
      ],
      _Title('Από το Samsung Health Monitor (όπως τα δίνει η Samsung, χωρίς ερμηνεία)'),
      samsung('sleep_apnea', 'Τεστ άπνοιας ύπνου του ρολογιού'),
      samsung('irregular_heart_rhythm', 'Ειδοποιήσεις ακανόνιστου ρυθμού'),
      samsung('blood_pressure', 'Μετρήσεις πίεσης'),
      const SizedBox(height: 6),
      Text(
        'Το τεστ άπνοιας του ρολογιού ψάχνει μόνο αποφρακτική άπνοια και δεν την αποκλείει όταν είναι αρνητικό. Η πίεση από '
        'το ρολόι (χωρίς περιχειρίδα) θέλει βαθμονόμηση και δεν αρκεί για διάγνωση· οι μετρήσεις από πιεσόμετρο μπράτσου '
        'φαίνονται εδώ μόνο αν γράφτηκαν στο Samsung Health. Τα ΗΚΓ του ρολογιού δεν περιλαμβάνονται.',
        style: small,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(data: data, page: 4, name: name),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => FittedBox(
              key: const ValueKey('report-page4-body'),
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: box.maxWidth,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
              ),
            ),
          ),
        ),
        _Footer(data: data, page: 4),
      ],
    );
  }
}
