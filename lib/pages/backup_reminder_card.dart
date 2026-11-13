/// Υπενθύμιση αντιγράφου στη «Σήμερα» (έλεγχος 13/11, S9-3).
///
/// Φαγητό, «Τα προϊόντα μου», προπονήσεις, στόχοι και μέση υπάρχουν μόνο σε αυτό το κινητό. Το αντίγραφο της Google
/// (αν είναι ανοιχτό) κρατά μόνο την τελευταία κατάσταση, άρα η μόνη προστασία «με ημερομηνία» είναι το αρχείο της
/// «Εξαγωγής αντιγράφου», και ως τώρα τίποτα δεν τη θύμιζε. Μια μικρή, ήρεμη κάρτα, χαμηλά στη σελίδα (ποτέ πάνω από
/// τα δεδομένα υγείας): φαίνεται όταν το τελευταίο αντίγραφο είναι [backupReminderAfterDays] ημερών ή δεν βγήκε ποτέ,
/// και υπάρχει κάτι να χαθεί. «Αργότερα» την κρύβει για [backupSnoozeDays] μέρες. Χωρίς ειδοποίηση· μόνο κάρτα.
library;

import 'package:flutter/material.dart';

import '../backup.dart';
import '../data.dart';
import '../food/food_channel.dart';
import '../food/food_store.dart';
import '../theme.dart';
import '../training/training_store.dart';
import '../widgets.dart';
import 'settings.dart' show BackupExport, exportBackupNow;

/// Η θέση της κάρτας: ξαναχτίζεται μόνο αυτή όταν αλλάζει το φαγητό ή οι προπονήσεις. Χωρίς κάρτα: τίποτα, ούτε κενό.
class BackupReminderSlot extends StatelessWidget with SelfSpaced {
  const BackupReminderSlot({
    super.key,
    required this.store,
    required this.food,
    required this.training,
    required this.now,
    this.export,
    this.share,
  });
  final HealthStore store;
  final FoodStore food;
  final TrainingStore training;
  final DateTime now;

  /// Μόνο για δοκιμές (αλλιώς η κανονική εξαγωγή και το φύλλο κοινοποίησης του Android).
  final Future<BackupExport> Function()? export;
  final Future<void> Function(String uri)? share;

  /// Υπάρχει κάτι που έγραψε ο χρήστης και ζει μόνο σε αυτό το κινητό: καταχώριση φαγητού, δικό του προϊόν,
  /// προπόνηση που έγινε ή μέτρηση μέσης. (Ό,τι έρχεται από Samsung Health και Oura ξαναδιαβάζεται.)
  static bool hasOwnData(HealthStore store, FoodStore food, TrainingStore training) =>
      (food.loaded && (food.mine.isNotEmpty || food.recent(limit: 1).isNotEmpty)) ||
      (training.ready && !training.readError && training.sessions.isNotEmpty) ||
      store.waist.isNotEmpty;

  /// Μόνο με διαβασμένες ρυθμίσεις: πριν από αυτό δεν ξέρουμε πότε βγήκε το τελευταίο αντίγραφο.
  static bool shows(HealthStore store, FoodStore food, TrainingStore training, DateTime now) =>
      store.prefsLoaded &&
      backupReminderDue(
        last: store.lastExport,
        hasData: hasOwnData(store, food, training),
        now: now,
        snoozedUntil: store.backupSnoozedUntil,
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([food, training]),
        builder: (context, _) {
          if (!shows(store, food, training, now)) return const SizedBox.shrink(key: ValueKey('today-backup-none'));
          return Padding(
            padding: const EdgeInsets.only(bottom: PageFrame.gap),
            child: BackupReminderCard(store: store, food: food, now: now, export: export, share: share),
          );
        },
      );
}

/// Η κάρτα: πόσο παλιό είναι το τελευταίο αντίγραφο, «Εξαγωγή τώρα» (και αμέσως το φύλλο κοινοποίησης, για να φύγει το
/// αρχείο και από το κινητό) και «Αργότερα».
class BackupReminderCard extends StatefulWidget {
  const BackupReminderCard({super.key, required this.store, required this.food, required this.now, this.export, this.share});
  final HealthStore store;
  final FoodStore food;
  final DateTime now;
  final Future<BackupExport> Function()? export;
  final Future<void> Function(String uri)? share;

  @override
  State<BackupReminderCard> createState() => _BackupReminderCardState();
}

class _BackupReminderCardState extends State<BackupReminderCard> {
  bool _busy = false;

  Future<void> _export() async {
    // Μετά από πλήρες αντίγραφο η κάρτα φεύγει από τη σελίδα: ό,τι χρειάζεται κρατιέται πριν από την αναμονή.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final store = widget.store;
    final food = widget.food;
    final export = widget.export;
    final customShare = widget.share;
    Future<void> share(String uri) async {
      if (customShare != null) {
        await customShare(uri);
      } else {
        await FoodChannel.shareBackup(uri);
      }
    }

    setState(() => _busy = true);
    BackupExport r;
    try {
      r = export != null ? await export() : await exportBackupNow(store, food);
    } catch (_) {
      r = (ok: false, text: 'Δεν αποθηκεύτηκε το αντίγραφο. Δοκίμασε ξανά.', uri: null);
    }
    if (mounted) setState(() => _busy = false);
    final uri = r.uri;
    messenger?.showSnackBar(SnackBar(
      content: Text(r.text),
      duration: const Duration(seconds: 6),
      action: uri == null ? null : SnackBarAction(label: 'Αποστολή', onPressed: () => share(uri)),
    ));
    // Πλήρες αντίγραφο: κατευθείαν το φύλλο κοινοποίησης του Android, για να φύγει το αρχείο και από το κινητό.
    if (r.ok && uri != null) await share(uri);
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      key: const ValueKey('today-backup'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(icon: Icons.download_rounded, title: 'Αντίγραφο ασφαλείας', color: c.textSecondary),
          const SizedBox(height: 10),
          Text(
            backupReminderText(widget.store.lastExport, widget.now),
            style: TextStyle(color: c.text, fontSize: 14.5, height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(backupOffPhoneText, style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4)),
          const SizedBox(height: 12),
          // Wrap: σε στενή στήλη ή με μεγάλα γράμματα το «Αργότερα» πέφτει από κάτω, δεν ξεχειλίζει.
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                key: const ValueKey('today-backup-export'),
                onPressed: _busy ? null : _export,
                child: Text(_busy ? 'Αποθηκεύεται…' : 'Εξαγωγή τώρα'),
              ),
              TextButton(
                key: const ValueKey('today-backup-later'),
                onPressed: _busy ? null : () => widget.store.snoozeBackupReminder(backupSnoozeUntil(widget.now)),
                child: const Text('Αργότερα'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
