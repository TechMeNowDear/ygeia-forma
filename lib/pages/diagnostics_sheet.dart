import 'dart:convert';

import 'package:flutter/material.dart';

import '../data.dart';
import '../diagnostics.dart';
import '../error_report.dart';
import '../food/food_channel.dart';
import '../food/food_store.dart';
import '../theme.dart';
import '../training/training_device.dart';
import '../training/training_store.dart';

/// «Αναφορά για έλεγχο» (αίτημα χρήστη 12/11): σημείωση + ένα αρχείο στις Λήψεις, και κοινοποίηση. Τίποτα δεν φεύγει
/// μόνο του από το κινητό.
///
/// Round 7 (R7-A11-2): τα κείμενα λένε την αλήθεια για το αρχείο: έχει ΟΛΑ τα δεδομένα (και του Oura), μένει στις Λήψεις
/// χωρίς κλείδωμα, και όποιος το λάβει (π.χ. μια υπηρεσία AI) τα βλέπει. Το ίδιο λέει η πολιτική απορρήτου.
const diagnosticsIntroText = 'Ένα αρχείο με ό,τι έχεις γράψει και ό,τι διάβασε και υπολόγισε η εφαρμογή: φαγητό, '
    'ζυγίσεις, μέση, ύπνο και παλμούς (και του Oura), βήματα, στόχους, διόρθωση θερμίδων, ζώνη, προπονήσεις, και '
    'αυτόματους ελέγχους για λάθη. Στείλ’ το σε όποιον θα το ελέγξει, π.χ. στη συζήτηση με τον Claude.';

const diagnosticsPrivacyText = 'Έχει όλα τα δεδομένα υγείας σου και μένει στις Λήψεις χωρίς κλείδωμα: όποιος το ανοίξει, '
    'τα διαβάζει. Η εφαρμογή δεν το στέλνει πουθενά μόνη της· αν το στείλεις σε μια υπηρεσία AI (π.χ. τον Claude), '
    'εκείνη βλέπει όλα όσα έχει, και τα δεδομένα του Oura. Δεν έχει κωδικούς ή κλειδιά σύνδεσης.';

Future<void> openDiagnostics(BuildContext context, HealthStore store, FoodStore food) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: 'Αναφορά για έλεγχο'),
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => DiagnosticsSheet(store: store, food: food),
    );

class DiagnosticsSheet extends StatefulWidget {
  const DiagnosticsSheet({super.key, required this.store, required this.food, this.save});
  final HealthStore store;
  final FoodStore food;

  /// Για τις δοκιμές: αντί για το Android (αποθήκευση στις Λήψεις).
  final Future<Map<String, dynamic>> Function(String json, String name)? save;

  @override
  State<DiagnosticsSheet> createState() => _DiagnosticsSheetState();
}

class _DiagnosticsSheetState extends State<DiagnosticsSheet> {
  final _note = TextEditingController();
  bool _busy = false;
  String? _result;
  String? _uri;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    final mq = MediaQuery.of(context);
    final c = Aigaio.of(context);
    setState(() {
      _busy = true;
      _result = null;
      _uri = null;
    });
    try {
      final now = DateTime.now();
      final report = await buildDiagnostics(
        store: widget.store,
        food: widget.food,
        training: TrainingStore.main,
        now: now,
        note: _note.text.trim(),
        reporter: errors,
        rest: await TrainingDevice.restStats(),
        screen: {
          'w': mq.size.width.round(),
          'h': mq.size.height.round(),
          'dpr': mq.devicePixelRatio,
          'textScale': mq.textScaler.scale(1),
          'dark': c.dark,
        },
      );
      final name = diagnosticsFileName(now);
      final r = await (widget.save ?? FoodChannel.saveBackup)(jsonEncode(report), name);
      if (!mounted) return;
      if (r['ok'] == true && r['uri'] is String) {
        final checks = report['checks'] as List;
        final bad = checks.where((x) => (x as Map)['ok'] != true).length;
        setState(() {
          _uri = r['uri'] as String;
          _result = 'Αποθηκεύτηκε στις Λήψεις: ${r['name'] ?? name}. '
              '${bad == 0 ? 'Οι αυτόματοι έλεγχοι δεν βρήκαν τίποτα.' : 'Οι αυτόματοι έλεγχοι βρήκαν $bad θέματα· θα φανούν στον έλεγχο.'}';
        });
        if (widget.save == null) await FoodChannel.shareBackup(_uri!);
      } else {
        // Round 7 (R7-A9-5): ελληνικό μήνυμα από το είδος του σφάλματος, ποτέ το κείμενο της Java.
        setState(() => _result = r['kind'] == 'full'
            ? 'Δεν αποθηκεύτηκε: δεν χωράει στο κινητό. Ελευθέρωσε χώρο και δοκίμασε ξανά.'
            : 'Δεν αποθηκεύτηκε. Δοκίμασε ξανά.');
      }
    } catch (e, s) {
      errors.report(e, s);
      if (mounted) setState(() => _result = 'Δεν φτιάχτηκε η αναφορά. Δοκίμασε ξανά.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final body = TextStyle(fontSize: 14.5, height: 1.45, color: c.text);
    final small = TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Αναφορά για έλεγχο', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.text)),
        const SizedBox(height: 8),
        // Round 7 (R7-A11-2): όλα όσα έχει πράγματι το αρχείο (και ύπνος/παλμοί του Oura, βήματα, μέση: diagnostics.dart).
        Text(diagnosticsIntroText, key: const ValueKey('diag-intro'), style: body),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('diag-note'),
          controller: _note,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Τι πρόσεξες; (προαιρετικά)',
            hintText: 'π.χ. «Το μεσημεριανό δεν φαίνεται στο σύνολο»',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const ValueKey('diag-make'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _busy ? null : _make,
          icon: const Icon(Icons.ios_share_rounded, size: 20),
          label: Text(_busy ? 'Φτιάχνεται…' : 'Φτιάξε και στείλε'),
        ),
        if (_result != null) ...[
          const SizedBox(height: 12),
          Text(_result!, key: const ValueKey('diag-result'), style: body),
          if (_uri != null && widget.save == null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => FoodChannel.shareBackup(_uri!), child: const Text('Στείλε ξανά')),
            ),
        ],
        const SizedBox(height: 12),
        Text(diagnosticsPrivacyText, key: const ValueKey('diag-privacy'), style: small),
      ]),
    );
  }
}
