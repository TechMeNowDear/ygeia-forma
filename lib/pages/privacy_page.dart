/// Απόρρητο (έλεγχος 9/11, E3-05 / V-A-23): ο διακόπτης για τις αναφορές σφαλμάτων και η «Διαγραφή όλων των
/// δεδομένων» με δύο επιβεβαιώσεις. Ό,τι ΔΕΝ σβήνεται λέγεται ρητά, πριν πατήσεις.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart';
import '../error_report.dart';
import '../theme.dart';
import '../widgets.dart';

const _privacy = MethodChannel('ygeia/privacy');

/// Τι σβήνεται από αυτό το κινητό (ό,τι κρατά η εφαρμογή).
const wipeDeletes = <String>[
  'Το ιστορικό που κράτησε η εφαρμογή: ύπνος, παλμοί, οξυγόνο, βήματα, ζυγίσεις.',
  'Το ημερολόγιο φαγητού και «Τα προϊόντα μου».',
  'Οι προπονήσεις και τα περπατήματα με τους παλμούς τους, το πρόγραμμα και το όριο παλμών.',
  'Οι ρυθμίσεις, «Τα στοιχεία μου» και οι πηγές.',
  'Η σύνδεση με το Oura (ανακαλείται και στον λογαριασμό σου, αν υπάρχει ίντερνετ).',
  'Οι τιμές στα widgets της αρχικής οθόνης και οι αναφορές σφαλμάτων που δεν έχουν σταλεί.',
];

/// Τι ΔΕΝ σβήνεται (δεν είναι στο κινητό ή δεν το ελέγχει η εφαρμογή).
const wipeKeeps = <String>[
  'Τα δεδομένα στο Samsung Health μένουν εκεί. Τις άδειες τις αφαιρείς από τις ρυθμίσεις του Samsung Health.',
  'Τα δεδομένα στον λογαριασμό σου στην Oura.',
  'Αρχεία που αποθήκευσες στις Λήψεις: αντίγραφα και PDF για τον γιατρό.',
  'Το αντίγραφο της Google (Google Drive › Αντίγραφα ασφαλείας).',
  'Ό,τι έχει ακόμα το ρολόι (πρόγραμμα, όριο, περπατήματα που δεν έφτασαν): σβήνεται από τις ρυθμίσεις του ρολογιού, '
      'στις Εφαρμογές, ή με απεγκατάσταση.',
  'Αναφορές σφαλμάτων που έχουν ήδη σταλεί: σβήνονται μόνες τους σε 90 μέρες.',
];

const wipeFailedText = 'Δεν έγινε η διαγραφή. Κάν\' την από τις Ρυθμίσεις Android › Εφαρμογές › Υγεία & Φόρμα › '
    'Αποθηκευτικός χώρος › Διαγραφή δεδομένων.';

/// Η διαγραφή: πρώτα ό,τι θέλει δίκτυο (ανάκληση της Oura, με όριο χρόνου), μετά η πλευρά Android σβήνει τα πάντα και
/// κλείνει την εφαρμογή. `false` αν δεν έγινε (η εφαρμογή δεν έκλεισε).
Future<bool> wipeAllData(HealthStore? store) async {
  if (store != null && store.ouraHasTokens) {
    try {
      // Μόνο ανάκληση και σβήσιμο των tokens· το σχέδιο πηγών σβήνεται ούτως ή άλλως με όλα τα υπόλοιπα.
      await store.ouraLink.disconnect().timeout(const Duration(seconds: 15));
    } catch (_) {}
  }
  try {
    return await _privacy.invokeMethod<bool>('wipe') == true;
  } catch (_) {
    return false;
  }
}

/// Η κάρτα «Απόρρητο» στις Ρυθμίσεις.
class PrivacyCard extends StatelessWidget {
  const PrivacyCard({super.key, required this.store, this.reporter, this.wipe});
  final HealthStore? store;

  /// Μόνο για δοκιμές (αλλιώς ο αναφορέας της εφαρμογής).
  final ErrorReporter? reporter;
  final Future<bool> Function()? wipe;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final r = reporter ?? errors;
    return AppCard(
      key: const ValueKey('settings-privacy'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Απόρρητο'),
          ValueListenableBuilder<bool>(
            valueListenable: r.sending,
            builder: (context, on, _) => SwitchListTile(
              key: const ValueKey('privacy-errors'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Αναφορές σφαλμάτων'),
              subtitle: Text(
                on
                    ? 'Όταν κάτι χαλάσει, στέλνεται στο Sentry (ΕΕ) μόνο τι χάλασε και σε ποια οθόνη· ποτέ δεδομένα υγείας ή φαγητού.'
                    : 'Κλειστές: δεν στέλνεται τίποτα, και όσες περίμεναν σβήστηκαν.',
                style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
              ),
              value: on,
              onChanged: (v) async {
                final ok = await r.setEnabled(v);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Η επιλογή δεν αποθηκεύτηκε. Δοκίμασε ξανά.')));
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('privacy-delete'),
            style: OutlinedButton.styleFrom(foregroundColor: c.bad, side: BorderSide(color: c.bad.withValues(alpha: .5))),
            onPressed: () => Navigator.of(context).push(DeleteAllPage.route(store, wipe: wipe)),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Διαγραφή όλων των δεδομένων'),
          ),
        ],
      ),
    );
  }
}

/// Δύο βήματα: (1) τι σβήνεται και τι όχι, (2) «Σίγουρα;» με το κόκκινο κουμπί.
class DeleteAllPage extends StatefulWidget {
  const DeleteAllPage({super.key, required this.store, this.wipe, this.initialStep = 1});
  final HealthStore? store;

  /// Μόνο για δοκιμές και στιγμιότυπα.
  final Future<bool> Function()? wipe;
  final int initialStep;

  static Route<void> route(HealthStore? store, {Future<bool> Function()? wipe}) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'Διαγραφή όλων'),
        builder: (_) => DeleteAllPage(store: store, wipe: wipe),
      );

  @override
  State<DeleteAllPage> createState() => _DeleteAllPageState();
}

class _DeleteAllPageState extends State<DeleteAllPage> {
  late int _step = widget.initialStep;
  bool _busy = false;
  bool _failed = false;

  Future<void> _wipe() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await (widget.wipe ?? () => wipeAllData(widget.store))();
    // Με επιτυχία η εφαρμογή κλείνει από το σύστημα. Αν φτάσουμε εδώ με «όχι», το λέμε.
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = !ok;
    });
  }

  Widget _line(BuildContext context, IconData icon, Color color, String text) {
    final c = Aigaio.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: color)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 14.5, height: 1.4, color: c.text))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final children = <Widget>[];
    if (_step == 1) {
      children.addAll([
        AppCard(
          key: const ValueKey('wipe-deletes'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionLabel('Τι σβήνεται από αυτό το κινητό'),
            for (final t in wipeDeletes) _line(context, Icons.delete_outline_rounded, c.bad, t),
          ]),
        ),
        const SizedBox(height: 12),
        AppCard(
          key: const ValueKey('wipe-keeps'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SectionLabel('Τι ΔΕΝ σβήνεται'),
            for (final t in wipeKeeps) _line(context, Icons.info_outline_rounded, c.textSecondary, t),
          ]),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            'Αν θέλεις να κρατήσεις κάτι, φτιάξε πρώτα αντίγραφο: Ρυθμίσεις › Αντίγραφο ασφαλείας › Εξαγωγή.',
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('wipe-next'),
          style: FilledButton.styleFrom(backgroundColor: c.bad, foregroundColor: Colors.white),
          onPressed: () => setState(() => _step = 2),
          child: const Text('Συνέχεια'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Άκυρο')),
      ]);
    } else {
      children.addAll([
        AppCard(
          key: const ValueKey('wipe-confirm-card'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              IconBadge(Icons.warning_amber_rounded, c.bad, size: 40),
              const SizedBox(width: 12),
              const Expanded(child: SectionLabel('Σίγουρα;')),
            ]),
            const SizedBox(height: 12),
            Text(
              'Η διαγραφή δεν αναιρείται. Η εφαρμογή θα κλείσει· όταν την ξανανοίξεις, θα είναι σαν καινούργια, με τις '
              'αρχικές ρυθμίσεις.',
              style: TextStyle(fontSize: 15, height: 1.45, color: c.text),
            ),
            if (_failed) ...[
              const SizedBox(height: 12),
              Text(wipeFailedText, key: const ValueKey('wipe-failed'), style: TextStyle(fontSize: 14, height: 1.4, color: c.bad)),
            ],
          ]),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('wipe-confirm'),
          style: FilledButton.styleFrom(backgroundColor: c.bad, foregroundColor: Colors.white),
          onPressed: _busy ? null : _wipe,
          icon: const Icon(Icons.delete_forever_rounded),
          label: Text(_busy ? 'Σβήνω…' : 'Διαγραφή όλων'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey('wipe-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
          child: const Text('Ακύρωση'),
        ),
        if (_busy) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
      ]);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Διαγραφή όλων'),
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
