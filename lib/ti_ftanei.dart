import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'labels.dart';
import 'samsung.dart';
import 'theme.dart';

/// Βήμα 1 — «Τι φτάνει»: δείχνει τι διαβάζει η εφαρμογή από το Samsung Health,
/// για να αποφασίσουμε με πραγματικά δεδομένα τι θα χτίσουμε.
class TiFtaneiScreen extends StatefulWidget {
  const TiFtaneiScreen({super.key});

  @override
  State<TiFtaneiScreen> createState() => _TiFtaneiScreenState();
}

class _TiFtaneiScreenState extends State<TiFtaneiScreen> {
  static const _days = 30;

  bool _busy = false;
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _error;

  @override
  void initState() {
    super.initState();
    // Μετά το πρώτο σχέδιο της οθόνης, ώστε να μη μπλοκάρει το άνοιγμα.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh(askPermissions: false);
    });
  }

  int get _granted => (_status?['granted'] as num?)?.toInt() ?? 0;
  int get _total => (_status?['total'] as num?)?.toInt() ?? 0;
  bool get _hasAllPermissions => _status != null && _total > 0 && _granted >= _total;

  Future<void> _refresh({required bool askPermissions}) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final status = askPermissions
        ? await SamsungHealth.requestPermissions()
        : await SamsungHealth.status();
    if (status['ok'] != true) {
      _finish(error: status);
      return;
    }
    _status = status;

    if (((status['granted'] as num?)?.toInt() ?? 0) == 0) {
      _finish();
      return;
    }

    final data = await SamsungHealth.readAll(days: _days);
    if (data['ok'] != true) {
      _finish(error: data);
      return;
    }
    _finish(data: data);
  }

  void _finish({Map<String, dynamic>? data, Map<String, dynamic>? error}) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (data != null) _data = data;
      _error = error;
    });
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _buildReport()));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Αντιγράφηκε. Επικόλλησέ το στη συζήτηση με το Claude.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            const side = 16.0;
            final content = (constraints.maxWidth - side * 2).clamp(0.0, 1100.0);
            final twoColumns = content >= 640;
            final cardWidth = twoColumns ? (content - gap) / 2 : content;

            return ListView(
              padding: const EdgeInsets.fromLTRB(side, 20, side, 32),
              children: [
                Center(
                  child: SizedBox(
                    width: content,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Τι φτάνει',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: c.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Τι διαβάζει η εφαρμογή από το Samsung Health τις τελευταίες $_days μέρες.',
                          style: TextStyle(fontSize: 16, color: c.textSecondary),
                        ),
                        const SizedBox(height: 20),
                        _StatusCard(
                          busy: _busy,
                          status: _status,
                          error: _error,
                          hasAllPermissions: _hasAllPermissions,
                          granted: _granted,
                          total: _total,
                          onConnect: () => _refresh(askPermissions: true),
                          onCheck: () => _refresh(askPermissions: false),
                          onResolve: () async {
                            await SamsungHealth.resolve();
                          },
                        ),
                        if (_data != null) ...[
                          const SizedBox(height: gap),
                          _TodayCard(today: _data!['today'] as Map<String, dynamic>?),
                          const SizedBox(height: gap),
                          Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              for (final t in _types())
                                SizedBox(width: cardWidth, child: _TypeCard(type: t)),
                              SizedBox(width: cardWidth, child: const _HrvCard()),
                            ],
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton(
                            onPressed: _copyReport,
                            child: const Text('Αντιγραφή αναφοράς για το Claude'),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ανάγνωση: ${_formatDateTime(_data!['readAt'] as String?)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _types() {
    final list = (_data?['types'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .toList();
    // Πρώτα όσα έρχονται, μετά τα κενά, στο τέλος όσα δεν έχουν άδεια ή σφάλμα.
    int rank(Map<String, dynamic> t) => switch (t['state']) {
          'ok' => 0,
          'empty' => 1,
          _ => 2,
        };
    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }

  String _buildReport() {
    final b = StringBuffer()
      ..writeln('Υγεία & Φόρμα — αναφορά «Τι φτάνει»')
      ..writeln('Ανάγνωση: ${_data?['readAt']} · ${_data?['days']} μέρες')
      ..writeln('Άδειες: $_granted από $_total')
      ..writeln();

    final today = _data?['today'] as Map<String, dynamic>?;
    if (today != null) {
      b.writeln('ΣΗΜΕΡΑ: $today');
      b.writeln();
    }

    for (final t in _types()) {
      final key = t['key'] as String;
      b.writeln('## ${typeLabels[key] ?? key} [$key] — ${t['state']} (${t['days'] ?? ''} μέρες)');
      if (t['state'] == 'ok') {
        b.writeln(
          'Εγγραφές: ${t['count']}${t['capped'] == true ? '+' : ''} · τελευταία: ${t['latest']}',
        );
        if (t['counted'] is num) b.writeln('Μετρούν στην εφαρμογή: ${t['counted']} · αγνοούνται (άλλη πηγή): ${t['ignored']}');
        for (final s in (t['sources'] as List<dynamic>? ?? [])) {
          final m = s as Map<String, dynamic>;
          final counts = m['counts'] is bool ? (m['counts'] == true ? ' · μετρά' : ' · ΔΕΝ μετρά') : '';
          b.writeln('Πηγή: ${m['app']} · συσκευή: ${m['device']} · ${m['count']}$counts');
        }
        for (final f in (t['fields'] as List<dynamic>? ?? [])) {
          final m = f as Map<String, dynamic>;
          final seen = m['seen'] == true ? 'ΝΑΙ' : 'όχι';
          b.writeln('  ${m['name']} = ${m['value']} (έρχεται: $seen)');
        }
      } else if (t['state'] == 'error') {
        b.writeln('Σφάλμα: ${t['error']}');
      }
      b.writeln();
    }
    return b.toString();
  }
}

// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.busy,
    required this.status,
    required this.error,
    required this.hasAllPermissions,
    required this.granted,
    required this.total,
    required this.onConnect,
    required this.onCheck,
    required this.onResolve,
  });

  final bool busy;
  final Map<String, dynamic>? status;
  final Map<String, dynamic>? error;
  final bool hasAllPermissions;
  final int granted;
  final int total;
  final VoidCallback onConnect;
  final VoidCallback onCheck;
  final Future<void> Function() onResolve;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final onBlue = c.onPrimary;

    String title;
    String body;
    if (busy) {
      title = 'Διαβάζω…';
      body = 'Μπορεί να πάρει λίγα δευτερόλεπτα.';
    } else if (error != null) {
      title = 'Χρειάζεται κάτι από σένα';
      body = errorText(error!['kind'] as String? ?? 'other');
    } else if (status == null || granted == 0) {
      title = 'Σύνδεση με Samsung Health';
      body = 'Θα ανοίξει το παράθυρο του Samsung Health. Πάτα «Επιλογή όλων» και «Τέλος». '
          'Η εφαρμογή μόνο διαβάζει· δεν γράφει τίποτα.';
    } else if (!hasAllPermissions) {
      title = 'Άδειες: $granted από $total';
      body = 'Κάποια δεδομένα δεν διαβάζονται. Πάτα «Σύνδεση» και επίλεξε όλα.';
    } else {
      title = 'Συνδέθηκε';
      body = 'Όλες οι άδειες ($granted) δόθηκαν. Πιο κάτω φαίνεται τι έρχεται.';
    }

    final needsConnect = !busy && (status == null || !hasAllPermissions);
    final resolvable = error?['resolvable'] == true;

    return Container(
      decoration: BoxDecoration(
        color: c.primary,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(color: onBlue, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(body, style: TextStyle(color: onBlue, fontSize: 16, height: 1.35)),
          if (error != null && (error!['message'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Λεπτομέρεια: ${error!['message']} (${error!['code']})',
              style: TextStyle(color: onBlue.withValues(alpha: 0.8), fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          if (busy)
            Center(child: CircularProgressIndicator(color: onBlue))
          else
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: onBlue,
                foregroundColor: c.primary,
              ),
              onPressed: resolvable
                  ? () {
                      onResolve();
                    }
                  : (needsConnect ? onConnect : onCheck),
              child: Text(
                resolvable
                    ? 'Διόρθωση στο Samsung Health'
                    : (needsConnect ? 'Σύνδεση με Samsung Health' : 'Έλεγχος ξανά'),
              ),
            ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.today});

  final Map<String, dynamic>? today;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final steps = (today?['stepsByDay'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final todaySteps = steps.isNotEmpty ? steps.first['value'] : null;

    // Κενό ανάμεσα στις στήλες: στα 360 dp το «Θερμίδες που έκαψες» κολλούσε στο «Ενεργές θερμίδες».
    Widget tile(String label, Object? value) => Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value == null ? '—' : _round(value),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.text),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: c.textSecondary)),
            ],
          ),
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Σήμερα',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                tile('Βήματα', todaySteps),
                tile('Θερμίδες που έκαψες', today?['totalCalories']),
                tile('Ενεργές θερμίδες', today?['activeCalories']),
              ],
            ),
            if (steps.length > 1) ...[
              const SizedBox(height: 12),
              Text(
                'Βήματα 7 ημερών: ${steps.map((s) => '${_shortDate(s['date'] as String?)} ${s['value']}').join(' · ')}',
                style: TextStyle(color: c.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.type});

  final Map<String, dynamic> type;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final key = type['key'] as String? ?? '';
    final state = type['state'] as String? ?? '';

    final (chipText, chipColor) = switch (state) {
      'ok' => ('Έρχεται', c.olive),
      'empty' => ('Κενό', c.wheat),
      'no_permission' => ('Χωρίς άδεια', c.terracotta),
      'unsupported' => ('Δεν υποστηρίζεται', c.textSecondary),
      _ => ('Σφάλμα', c.terracotta),
    };

    String line;
    switch (state) {
      case 'ok':
        final capped = type['capped'] == true ? '+' : '';
        line = '${type['count']}$capped εγγραφές · τελευταία ${_formatDateTime(type['latest'] as String?)}';
      case 'empty':
        line = 'Καμία εγγραφή τις τελευταίες ${type['days'] ?? 30} μέρες.';
      case 'no_permission':
        line = 'Δεν δόθηκε άδεια ανάγνωσης.';
      case 'unsupported':
        line = 'Το SDK δεν επιτρέπει ανάγνωση εγγραφών εδώ.';
      default:
        final e = type['error'] as Map<String, dynamic>?;
        line = errorText(e?['kind'] as String? ?? 'other');
    }

    final sources = (type['sources'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final fields = (type['fields'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    typeLabels[key] ?? key,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: chipColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    chipText,
                    style: TextStyle(color: chipColor, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(line, style: TextStyle(color: c.textSecondary)),
            // A2: ύπνος/παλμοί/οξυγόνο/θερμοκρασία μόνο από ρολόι, ζυγίσεις μόνο InBody· οι άλλες πηγές φαίνονται εδώ.
            if (type['counted'] is num && (type['ignored'] as num? ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Μετρούν ${type['counted']} · αγνοούνται ${type['ignored']} από άλλη πηγή '
                  '(${key == 'body_composition' ? 'μόνο InBody' : 'μόνο ρολόι'})',
                  style: TextStyle(color: c.text, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            for (final s in sources)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Από: ${appLabel(s['app'] as String? ?? '')}'
                  '${(s['device'] as String? ?? '').isNotEmpty ? ' · ${s['device']}' : ''}'
                  ' · ${s['count']}'
                  '${s['counts'] == false ? ' · δεν μετρά' : ''}',
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                ),
              ),
            if (fields.isNotEmpty)
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text(
                    'Πεδία (${fields.where((f) => f['seen'] == true).length} από ${fields.length} έρχονται)',
                    style: TextStyle(color: c.primary, fontWeight: FontWeight.w600),
                  ),
                  children: [
                    for (final f in fields) _FieldRow(field: f),
                  ],
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field});

  final Map<String, dynamic> field;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final seen = field['seen'] == true;
    final value = field['value'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              seen ? '✓' : '—',
              style: TextStyle(
                color: seen ? c.olive : c.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              fieldLabel(field['name'] as String? ?? ''),
              style: TextStyle(color: c.text),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value == null ? (seen ? '' : 'δεν έρχεται') : value.toString(),
              textAlign: TextAlign.end,
              style: TextStyle(color: seen ? c.text : c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _HrvCard extends StatelessWidget {
  const _HrvCard();

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'HRV (μεταβλητότητα παλμών)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text),
            ),
            const SizedBox(height: 6),
            Text(
              'Η Samsung δεν το δίνει σε άλλες εφαρμογές. Έρχεται από το Oura, όταν συνδεθεί.',
              style: TextStyle(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// «2026-10-24T07:12:00» → «24/10 07:12».
String _formatDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

/// «2026-10-24» → «24/10».
String _shortDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.day}/${d.month}';
}

String _round(Object value) {
  final n = num.tryParse(value.toString());
  if (n == null) return value.toString();
  return n.round().toString();
}
