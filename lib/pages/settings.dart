import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../backup.dart';
import '../data.dart';
import '../food/food_channel.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../history.dart' show otherDeviceNights;
import '../theme.dart';
import '../sources.dart';
import '../ti_ftanei.dart';
import '../training/training_store.dart';
import '../widgets.dart';
import 'appearance.dart';
import 'sources_page.dart';
import 'me_page.dart';
import '../profile.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store, this.food});
  final HealthStore store;

  /// Για το αντίγραφο ασφαλείας (ημερολόγιο φαγητού και προϊόντα).
  final FoodStore? food;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ρυθμίσεις'),
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final d = store.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppCard(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(settings: const RouteSettings(name: 'Εμφάνιση'), builder: (_) => AppearancePage(store: store)),
                        ),
                        child: Row(
                          children: [
                            IconBadge(Icons.palette_outlined, c.primary, size: 40),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Εμφάνιση', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(
                                    switch (store.prefs.themeMode) {
                                      'light' => 'Πάντα ανοιχτό · ${Aigaio.day(store.prefs.dayTheme).name}',
                                      'dark' => 'Πάντα σκοτεινό · ${Aigaio.night(store.prefs.nightTheme).name}',
                                      _ => 'Μέρα ${Aigaio.day(store.prefs.dayTheme).name} · '
                                          'νύχτα ${Aigaio.night(store.prefs.nightTheme).name}',
                                    },
                                    style: TextStyle(color: c.textSecondary, fontSize: 13.5),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: c.textTertiary),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      AppCard(
                        key: const ValueKey('settings-me'),
                        onTap: () => Navigator.of(context).push(MePage.route(store)),
                        child: Row(
                          children: [
                            IconBadge(Icons.person_rounded, c.body, size: 40),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Τα στοιχεία μου', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Ηλικία, φύλο, ύψος για τα εύρη · ζύγιση κάθε ${weekdayNames[store.profile.weighDay - 1]}',
                                    style: TextStyle(color: c.textSecondary, fontSize: 13.5),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: c.textTertiary),
                          ],
                        ),
                      ),                      const SizedBox(height: 12),
                      AppCard(
                        key: const ValueKey('settings-sources'),
                        onTap: () => Navigator.of(context).push(SourcesPage.route(store)),
                        child: Row(
                          children: [
                            IconBadge(Icons.device_hub_rounded, c.sleep, size: 40),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Πηγές', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Ύπνος: ${sourceDevice(store.plan.nightSource(DateTime.now()))} · '
                                    'βήματα: Samsung Health · βάρος: InBody',
                                    style: TextStyle(color: c.textSecondary, fontSize: 13.5),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: c.textTertiary),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      AppCard(
                        padding: const EdgeInsets.fromLTRB(18, 16, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SectionLabel('Τι βλέπω στο «Σήμερα»'),
                            const SizedBox(height: 4),
                            Text(
                              'Τα δεδομένα διαβάζονται όλα· εδώ διαλέγεις μόνο τι εμφανίζεται.',
                              style: TextStyle(color: c.textSecondary, fontSize: 13),
                            ),
                            for (final card in todayCards)
                              SwitchListTile(
                                contentPadding: const EdgeInsets.only(right: 4),
                                title: Text(card.label),
                                value: store.prefs.show(card.key),
                                onChanged: (on) => store.setCard(card.key, on),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SectionLabel('Samsung Health'),
                            const SizedBox(height: 6),
                            InfoRow('Άδειες', d == null ? '—' : '${d.granted} από ${d.total}'),
                            InfoRow('Τελευταία ανάγνωση', d == null ? '—' : '${relativeDay(d.readAt, DateTime.now())} ${hm(d.readAt)}'),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              onPressed: () => store.refresh(askPermissions: true),
                              child: const Text('Άδειες Samsung Health'),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  settings: const RouteSettings(name: 'Έλεγχος δεδομένων'),
                                  builder: (_) => Scaffold(
                                    appBar: AppBar(title: const Text('Έλεγχος δεδομένων')),
                                    body: TiFtaneiScreen(otherDeviceNights: otherDeviceNights(store.history)),
                                  ),
                                ),
                              ),
                              child: const Text('Έλεγχος δεδομένων («Τι φτάνει»)'),
                            ),
                          ],
                        ),
                      ),
                      if (food != null) ...[
                        const SizedBox(height: 12),
                        _BackupCard(store: store, food: food!),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Υγεία & Φόρμα · προσωπική έκδοση. Η εφαρμογή διαβάζει δεδομένα μόνο όταν την ανοίγεις.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Αντίγραφο ασφαλείας: όσα υπάρχουν μόνο σε αυτό το κινητό.
class _BackupCard extends StatefulWidget {
  const _BackupCard({required this.store, required this.food});
  final HealthStore store;
  final FoodStore food;

  @override
  State<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<_BackupCard> {
  bool _busy = false;

  void _say(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), action: action, duration: const Duration(seconds: 6)));
  }

  /// Οι προπονήσεις για το αντίγραφο (μόνο αν διαβάστηκαν σωστά).
  Future<Map<String, dynamic>?> _training() async {
    final t = TrainingStore.main;
    await t.load();
    return t.ready && !t.readError ? t.toJson() : null;
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final raw = await widget.food.exportRaw();
      if (raw == null) {
        _say('Δεν διαβάστηκαν τα δεδομένα. Δοκίμασε ξανά.');
        return;
      }
      final now = DateTime.now();
      final name = backupFileName(now);
      // Οι ρυθμίσεις μπαίνουν μόνο αν έχουν διαβαστεί (αλλιώς θα έμπαιναν οι αρχικές).
      final json = buildBackup(
        foodLog: raw.$1,
        myFoods: raw.$2,
        prefs: widget.store.prefsLoaded ? widget.store.prefsJson() : const {},
        now: now,
        sources: await widget.store.sourcesForBackup(),
        training: await _training(),
      );
      final r = await FoodChannel.saveBackup(json, name);
      if (r['ok'] != true || r['uri'] is! String) {
        _say('Δεν αποθηκεύτηκε το αντίγραφο: ${r['message'] ?? 'άγνωστο σφάλμα'}');
        return;
      }
      final uri = r['uri'] as String;
      final saved = r['name'] is String ? r['name'] as String : name;
      _say(
        'Αποθηκεύτηκε στις Λήψεις: $saved · ${entriesText(raw.$1.length)}, ${productsText(raw.$2.length)}',
        action: SnackBarAction(label: 'Αποστολή', onPressed: () => FoodChannel.shareBackup(uri)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final r = await FoodChannel.pickBackup();
      if (r['ok'] != true) {
        if (r['kind'] != 'cancelled') _say('Δεν άνοιξε το αρχείο: ${r['message'] ?? 'άγνωστο σφάλμα'}');
        return;
      }
      BackupContents? parsed;
      try {
        // Σε ξεχωριστό νήμα: ένα αντίγραφο χρόνων είναι αρκετά MB και δεν πρέπει να «παγώσει» η οθόνη.
        parsed = await compute(parseBackup, r['json'] as String? ?? '');
      } on BackupError catch (e) {
        _say(e.message);
      }
      if (parsed == null) return;
      final b = parsed;
      if (!mounted) return;
      final when = b.created == null ? '' : ' της ${shortDayDate(b.created!.toLocal())}';
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Επαναφορά αντιγράφου'),
          content: Text(
            'Αντίγραφο$when: ${entriesText(b.entries.length)} φαγητού, ${productsText(b.myFoods.length)}.\n\n'
            'Μπαίνουν μόνο όσα λείπουν από το κινητό. Όσα υπάρχουν ήδη μένουν όπως είναι, με όσες αλλαγές τους έκανες. '
            'Τίποτα δεν σβήνεται· καταχωρίσεις που έσβησες μετά το αντίγραφο ξαναμπαίνουν.'
            '${b.prefs.isEmpty ? '' : '\n\nΘα αντικατασταθούν οι ρυθμίσεις: «Η κουζίνα μου», οι κάρτες της Σήμερα και η εμφάνιση.'}'
            '${b.sources == null ? '' : '\n\nΠηγές ύπνου (π.χ. από πότε μετρά το Oura): από το αντίγραφο, μόνο αν το κινητό δεν έχει νεότερες.'}'
            '${b.training == null ? '' : '\n\nΠροπονήσεις: μπαίνουν όσες λείπουν. Το όριο παλμών του γιατρού δεν μπαίνει· το ξαναγράφεις.'}'
            '${b.skipped == 0 ? '' : '\n\n${countText(b.skipped, 'χαλασμένη εγγραφή θα παραλειφθεί', 'χαλασμένες εγγραφές θα παραλειφθούν')}.'}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Άκυρο')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Επαναφορά')),
          ],
        ),
      );
      if (ok != true) return;
      final res = await widget.food.importBackup(b.entries, b.myFoods);
      if (res == null) {
        _say('Δεν διαβάστηκε τι υπάρχει ήδη στο κινητό, οπότε δεν άλλαξε τίποτα. Δοκίμασε ξανά.');
        return;
      }
      final (e, f, failed, existing) = res;
      final prefsOk = b.prefs.isEmpty || await widget.store.restorePrefs(b.prefs);
      final sourcesIn = b.sources != null && await widget.store.restoreSources(b.sources!);
      var trainingIn = 0;
      if (b.training != null) {
        await TrainingStore.main.load();
        trainingIn = TrainingStore.main.mergeBackup(b.training!);
      }
      _say([
        'Επαναφορά: ${entriesText(e)} και ${productsText(f)}.',
        if (existing > 0)
          existing == 1 ? '1 εγγραφή υπήρχε ήδη και έμεινε όπως ήταν.' : '$existing εγγραφές υπήρχαν ήδη και έμειναν όπως ήταν.',
        if (failed > 0) '${countText(failed, 'δεν γράφτηκε', 'δεν γράφτηκαν')}· δοκίμασε ξανά.',
        if (!prefsOk) 'Οι ρυθμίσεις δεν άλλαξαν.',
        if (sourcesIn) 'Οι πηγές ύπνου μπήκαν από το αντίγραφο.',
        if (trainingIn > 0) countText(trainingIn, 'προπόνηση μπήκε από το αντίγραφο.', 'προπονήσεις μπήκαν από το αντίγραφο.'),
        if (b.sources != null && !sourcesIn) 'Οι πηγές ύπνου του κινητού είναι νεότερες και έμειναν.',
      ].join(' '));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Αντίγραφο ασφαλείας'),
          const SizedBox(height: 6),
          Text(
            'Το ημερολόγιο φαγητού, «Τα προϊόντα μου», οι προπονήσεις και οι ρυθμίσεις υπάρχουν μόνο σε αυτό το κινητό. '
            'Κράτα ένα αντίγραφο (π.χ. μία φορά την εβδομάδα). Τα δεδομένα της Samsung δεν χρειάζονται: ξαναδιαβάζονται.',
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.save_alt_rounded),
            label: const Text('Εξαγωγή αντιγράφου'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Επαναφορά από αντίγραφο'),
          ),
          if (_busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}
