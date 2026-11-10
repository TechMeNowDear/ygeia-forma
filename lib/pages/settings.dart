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
import 'devices_page.dart';
import 'sources_page.dart';
import 'me_page.dart';
import 'privacy_page.dart';
import '../profile.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store, this.food});
  final HealthStore store;

  /// Για το αντίγραφο ασφαλείας (ημερολόγιο φαγητού και προϊόντα).
  final FoodStore? food;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    // Σχέδιο «Settings» (premium, 10/11): γραμμές σε ενότητες, με «Τι μετράει κάθε συσκευή» (DevicesPage του premium).
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
          void push(String name, Widget Function(BuildContext) b) =>
              Navigator.of(context).push(MaterialPageRoute<void>(settings: RouteSettings(name: name), builder: b));
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 32 + MediaQuery.paddingOf(context).bottom),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SettingsGroup(children: [
                        SettingsRow(
                          icon: Icons.palette_outlined,
                          title: 'Εμφάνιση',
                          subtitle: switch (store.prefs.themeMode) {
                            'light' => 'Πάντα ανοιχτό · ${Aigaio.day(store.prefs.dayTheme).name}',
                            'dark' => 'Πάντα σκοτεινό · ${Aigaio.night(store.prefs.nightTheme).name}',
                            _ => 'Μέρα ${Aigaio.day(store.prefs.dayTheme).name} · '
                                'νύχτα ${Aigaio.night(store.prefs.nightTheme).name}',
                          },
                          onTap: () => push('Εμφάνιση', (_) => AppearancePage(store: store)),
                        ),
                        SettingsRow(
                          key: const ValueKey('settings-me'),
                          icon: Icons.person_outline_rounded,
                          title: 'Τα στοιχεία μου',
                          // Σχέδιο Settings + premium: η κουζίνα και τα προϊόντα μου είναι πια μέσα στα «Τα στοιχεία μου».
                          subtitle: 'Ηλικία, ύψος, ζύγιση κάθε ${weekdayNames[store.profile.weighDay - 1]} · η κουζίνα μου · τα προϊόντα μου',
                          onTap: () => Navigator.of(context).push(MePage.route(store)),
                        ),
                        SettingsRow(
                          key: const ValueKey('settings-sources'),
                          icon: Icons.link_rounded,
                          title: 'Πηγές',
                          subtitle: 'Ύπνος: ${sourceDevice(store.plan.nightSource(DateTime.now()))} · '
                              'βήματα: Samsung Health · βάρος: InBody',
                          onTap: () => Navigator.of(context).push(SourcesPage.route(store)),
                        ),
                        SettingsRow(
                          key: const ValueKey('settings-devices'),
                          icon: Icons.layers_rounded,
                          title: 'Τι μετράει κάθε συσκευή',
                          subtitle: 'Μέτρηση, εκτίμηση, ενδεικτικό',
                          onTap: () => Navigator.of(context).push(DevicesPage.route()),
                        ),
                        SettingsRow(
                          key: const ValueKey('settings-today-cards'),
                          icon: Icons.grid_view_rounded,
                          title: 'Κάρτες της «Σήμερα»',
                          subtitle: 'Τι εμφανίζεται',
                          onTap: () => push('Κάρτες της Σήμερα', (_) => _TodayCardsPage(store: store)),
                        ),
                      ]),
                      const SettingsSection('Απόρρητο'),
                      const PrivacyGroup(),
                      const SettingsSection('Τα δεδομένα μου'),
                      _DataGroup(store: store, food: food),
                      const SettingsSection('Για προχωρημένους'),
                      SettingsGroup(children: [
                        SettingsRow(
                          icon: Icons.build_outlined,
                          color: c.textSecondary,
                          title: 'Έλεγχος δεδομένων',
                          subtitle: '«Τι φτάνει» από κάθε πηγή',
                          onTap: () => push(
                            'Έλεγχος δεδομένων',
                            (_) => Scaffold(
                              appBar: AppBar(title: const Text('Έλεγχος δεδομένων')),
                              body: TiFtaneiScreen(otherDeviceNights: otherDeviceNights(store.history)),
                            ),
                          ),
                        ),
                        SettingsRow(
                          icon: Icons.watch_outlined,
                          color: c.textSecondary,
                          title: 'Άδειες Samsung Health',
                          subtitle: d == null
                              ? '—'
                              : '${d.granted} από ${d.total} · ανάγνωση ${relativeDay(d.readAt, DateTime.now())} ${hm(d.readAt)}',
                          onTap: () => store.refresh(askPermissions: true),
                        ),
                        SettingsRow(
                          key: const ValueKey('settings-licenses'),
                          icon: Icons.description_outlined,
                          color: c.textSecondary,
                          title: 'Άδειες λογισμικού',
                          subtitle: 'Γραμματοσειρά Inter, βιβλιοθήκες',
                          onTap: () => openLicenses(context),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      Text(
                        'Υγεία & Φόρμα · προσωπική έκδοση\nΗ εφαρμογή διαβάζει δεδομένα μόνο όταν την ανοίγεις.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.45),
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

/// «Κάρτες της Σήμερα»: τι εμφανίζεται (πριν: κάρτα με διακόπτες μέσα στις Ρυθμίσεις).
class _TodayCardsPage extends StatelessWidget {
  const _TodayCardsPage({required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Κάρτες της «Σήμερα»'), backgroundColor: c.background, surfaceTintColor: Colors.transparent),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(padding: EdgeInsets.fromLTRB(16, 4, 16, 32 + MediaQuery.paddingOf(context).bottom), children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Τα δεδομένα διαβάζονται όλα· εδώ διαλέγεις μόνο τι εμφανίζεται.',
                      style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4)),
                  for (final card in todayCards)
                    SwitchListTile(
                      contentPadding: const EdgeInsets.only(right: 4),
                      title: Text(card.label),
                      value: store.prefs.show(card.key),
                      onChanged: (on) => store.setCard(card.key, on),
                    ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// «ΤΑ ΔΕΔΟΜΕΝΑ ΜΟΥ»: αντίγραφο ασφαλείας (όσα υπάρχουν μόνο σε αυτό το κινητό) και «Διαγραφή όλων».
class _DataGroup extends StatefulWidget {
  const _DataGroup({required this.store, required this.food});
  final HealthStore store;
  final FoodStore? food;

  @override
  State<_DataGroup> createState() => _DataGroupState();
}

class _DataGroupState extends State<_DataGroup> {
  bool _busy = false;

  void _say(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), action: action, duration: const Duration(seconds: 6)));
  }

  /// Οι προπονήσεις για το αντίγραφο, με τους παλμούς τους (μόνο αν διαβάστηκαν σωστά).
  Future<Map<String, dynamic>?> _training() async {
    final t = TrainingStore.main;
    await t.load();
    return t.ready && !t.readError ? await t.backupJson() : null;
  }

  /// Η εξαγωγή χωρίς μηνύματα: (πλήρες αντίγραφο γράφτηκε, κείμενο για τον χρήστη, πού). Τη χρησιμοποιούν η γραμμή
  /// «Εξαγωγή αντιγράφου» (μήνυμα κάτω) και το φύλλο «Διαγραφή όλων» (μέσα στο φύλλο, έλεγχος του fix-accuracy, M2).
  Future<({bool ok, String text, String? uri})> _exportNow() async {
    final raw = await widget.food!.exportRaw();
    if (raw == null) return (ok: false, text: 'Δεν διαβάστηκαν τα δεδομένα. Δοκίμασε ξανά.', uri: null);
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
    final trainingOut = TrainingStore.main.readError;
    final hrMissing = trainingOut ? 0 : TrainingStore.main.backupHrMissing;
    final r = await FoodChannel.saveBackup(json, name);
    if (r['ok'] != true || r['uri'] is! String) {
      return (ok: false, text: 'Δεν αποθηκεύτηκε το αντίγραφο: ${r['message'] ?? 'άγνωστο σφάλμα'}', uri: null);
    }
    final saved = r['name'] is String ? r['name'] as String : name;
    return (
      // Πλήρες μόνο αν μπήκαν και οι προπονήσεις με τους παλμούς τους.
      ok: !trainingOut && hrMissing == 0,
      text: 'Αποθηκεύτηκε στις Λήψεις: $saved · ${entriesText(raw.$1.length)}, ${productsText(raw.$2.length)}'
          // Έλεγχος 9/11 (V-A-10): να μη λείπουν σιωπηλά.
          '${trainingOut ? '. Οι προπονήσεις δεν μπήκαν: το αρχείο τους δεν διαβάζεται.' : ''}'
          // Έλεγχος του #91 (S5): προπονήσεις των οποίων οι παλμοί δεν διαβάστηκαν, να μη λείπουν σιωπηλά.
          '${hrMissing > 0 ? '. ${countText(hrMissing, 'προπόνηση μπήκε χωρίς παλμούς', 'προπονήσεις μπήκαν χωρίς παλμούς')}: τα αρχεία τους δεν διαβάστηκαν.' : ''}',
      uri: r['uri'] as String,
    );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final r = await _exportNow();
      final uri = r.uri;
      _say(r.text, action: uri == null ? null : SnackBarAction(label: 'Αποστολή', onPressed: () => FoodChannel.shareBackup(uri)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Για το φύλλο «Διαγραφή όλων»: το αποτέλεσμα γυρίζει στο φύλλο (το SnackBar θα ήταν κάτω από αυτό).
  Future<BackupResult> _exportForWipe() async {
    try {
      final r = await _exportNow();
      return (ok: r.ok, text: r.text);
    } catch (_) {
      return (ok: false, text: 'Δεν αποθηκεύτηκε το αντίγραφο. Δοκίμασε ξανά.');
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
      final res = await widget.food!.importBackup(b.entries, b.myFoods);
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
        if (b.training != null && TrainingStore.main.mergeProblem != null) TrainingStore.main.mergeProblem!,
        if (b.sources != null && !sourcesIn) 'Οι πηγές ύπνου του κινητού είναι νεότερες και έμειναν.',
      ].join(' '));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFood = widget.food != null;
    return SettingsGroup(key: const ValueKey('settings-data'), children: [
      if (hasFood) ...[
        SettingsRow(
          key: const ValueKey('backup-export'),
          icon: Icons.download_rounded,
          title: 'Εξαγωγή αντιγράφου',
          // Φαγητό, προϊόντα, προπονήσεις και ρυθμίσεις υπάρχουν μόνο σε αυτό το κινητό· η Samsung ξαναδιαβάζεται.
          subtitle: 'Ένα αρχείο στις Λήψεις: φαγητό, προϊόντα, προπονήσεις, ρυθμίσεις',
          onTap: _busy ? null : _export,
        ),
        SettingsRow(
          key: const ValueKey('backup-import'),
          icon: Icons.upload_rounded,
          title: 'Επαναφορά από αντίγραφο',
          onTap: _busy ? null : _import,
        ),
      ],
      if (_busy) const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: LinearProgressIndicator()),
      DeleteAllRow(store: widget.store, export: hasFood ? _exportForWipe : null),
    ]);
  }
}
