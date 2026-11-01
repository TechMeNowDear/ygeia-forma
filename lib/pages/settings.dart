import 'package:flutter/material.dart';

import '../backup.dart';
import '../data.dart';
import '../food/food_channel.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../theme.dart';
import '../ti_ftanei.dart';
import '../widgets.dart';
import 'appearance.dart';

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
                                    body: const TiFtaneiScreen(),
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
      final json = buildBackup(foodLog: raw.$1, myFoods: raw.$2, prefs: widget.store.prefsJson(), now: now);
      final r = await FoodChannel.saveBackup(json, name);
      if (r['ok'] != true || r['uri'] is! String) {
        _say('Δεν αποθηκεύτηκε το αντίγραφο: ${r['message'] ?? 'άγνωστο σφάλμα'}');
        return;
      }
      final uri = r['uri'] as String;
      _say(
        'Αποθηκεύτηκε στις Λήψεις: $name · ${raw.$1.length} καταχωρίσεις, ${raw.$2.length} προϊόντα',
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
        parsed = parseBackup(r['json'] as String? ?? '');
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
            'Αντίγραφο$when: ${b.entries.length} καταχωρίσεις φαγητού, ${b.myFoods.length} προϊόντα.\n\n'
            'Όσα υπάρχουν ήδη μένουν· όσα έχουν την ίδια ταυτότητα ενημερώνονται. Τίποτα δεν σβήνεται.'
            '${b.prefs.isEmpty ? '' : '\n\nΘα αντικατασταθούν οι ρυθμίσεις: «Η κουζίνα μου», οι κάρτες της Σήμερα και η εμφάνιση.'}'
            '${b.skipped == 0 ? '' : '\n\n${b.skipped} χαλασμένες εγγραφές θα παραλειφθούν.'}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Άκυρο')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Επαναφορά')),
          ],
        ),
      );
      if (ok != true) return;
      final (e, f, failed) = await widget.food.importBackup(b.entries, b.myFoods);
      final prefsOk = b.prefs.isEmpty || await widget.store.restorePrefs(b.prefs);
      _say([
        'Επαναφέρθηκαν $e καταχωρίσεις και $f προϊόντα.',
        if (failed > 0) '$failed δεν γράφτηκαν· δοκίμασε ξανά.',
        if (!prefsOk) 'Οι ρυθμίσεις δεν άλλαξαν.',
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
            'Το ημερολόγιο φαγητού, «Τα προϊόντα μου» και οι ρυθμίσεις υπάρχουν μόνο σε αυτό το κινητό. '
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
