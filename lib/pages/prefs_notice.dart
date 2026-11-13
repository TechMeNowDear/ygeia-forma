import 'package:flutter/material.dart';

import '../data.dart';
import '../theme.dart';
import '../widgets.dart';

/// Round 1 (S3-2 / S9-1, S9-5 / S3-9 / S11-5): η κάρτα της Σήμερα για τις ρυθμίσεις (στόχοι διατροφής, «Τα στοιχεία
/// μου», ζώνη περπατήματος, μετρήσεις μέσης), μόνο όταν κάτι δεν πήγε καλά:
/// - το αρχείο ρυθμίσεων δεν διαβάζεται ([HealthStore.prefsCorrupt]): δεν γράφτηκε τίποτα από πάνω του· ο χρήστης
///   διαλέγει ρητά να ξεκινήσει με νέες ρυθμίσεις (το χαλασμένο αρχείο κρατιέται στο κινητό),
/// - η τελευταία αλλαγή δεν γράφτηκε στο κινητό ([HealthStore.prefsSaveError]): «Δοκίμασε ξανά».
/// Χωρίς πρόβλημα δεν φτιάχνεται καθόλου ([shows]).
class PrefsNoticeCard extends StatelessWidget {
  const PrefsNoticeCard({super.key, required this.store});
  final HealthStore store;

  /// Αν υπάρχει κάτι να πει.
  static bool shows(HealthStore store) => store.prefsCorrupt || store.prefsSaveError;

  void _say(BuildContext context, String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 8)));
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    if (store.prefsCorrupt) {
      return EmptyCard(
        key: const ValueKey('today-prefs-corrupt'),
        icon: Icons.tune_rounded,
        color: c.bad,
        title: 'Οι ρυθμίσεις δεν διαβάζονται',
        text: 'Το αρχείο με τις ρυθμίσεις σου (στόχοι διατροφής, τα στοιχεία σου, ζώνη περπατήματος, μετρήσεις μέσης) '
            'χάλασε. Δεν γράφτηκε τίποτα από πάνω του. Ώσπου να διαλέξεις, αλλαγές στις ρυθμίσεις δεν αποθηκεύονται· '
            'το φαγητό και οι προπονήσεις αποθηκεύονται κανονικά.\n\n'
            'Με το κουμπί, το χαλασμένο αρχείο κρατιέται στο κινητό και ξεκινούν νέες ρυθμίσεις. Μετά, αν έχεις '
            'αντίγραφο ασφαλείας: Ρυθμίσεις › Επαναφορά από αντίγραφο.',
        buttonText: 'Ξεκίνα με νέες ρυθμίσεις',
        onPressed: () async {
          final ok = await store.startFreshPrefs();
          // Με διαβασμένες ρυθμίσεις ξαναρχίζουν οι εγγραφές (ιστορικό, Oura): μία ανανέωση τώρα, χωρίς αναμονή.
          if (ok) store.refresh();
          if (!context.mounted) return;
          _say(
              context,
              ok
                  ? 'Ξεκίνησαν νέες ρυθμίσεις. Στόχοι, στοιχεία, ζώνη και μέση: Ρυθμίσεις › Επαναφορά από αντίγραφο.'
                  : 'Δεν έγινε. Δοκίμασε ξανά.');
        },
      );
    }
    return EmptyCard(
      key: const ValueKey('today-prefs-unsaved'),
      icon: Icons.sync_problem_rounded,
      color: c.bad,
      title: 'Η τελευταία αλλαγή δεν αποθηκεύτηκε',
      text: store.prefsLoaded
          ? 'Η τελευταία αλλαγή στις ρυθμίσεις (π.χ. στόχος, μέση, στοιχεία, ζώνη) δεν γράφτηκε στο κινητό· ίσως γέμισε '
              'ο χώρος. Τη βλέπεις στην οθόνη, αλλά αν κλείσει η εφαρμογή θα χαθεί.'
          : 'Οι ρυθμίσεις δεν διαβάστηκαν ακόμα από το κινητό, οπότε η τελευταία αλλαγή (π.χ. στόχος, μέση, στοιχεία, '
              'ζώνη) δεν έχει γραφτεί. Τη βλέπεις στην οθόνη, αλλά αν κλείσει η εφαρμογή θα χαθεί.',
      buttonText: 'Δοκίμασε ξανά',
      onPressed: () async {
        final ok = await store.retrySavePrefs();
        if (!context.mounted) return;
        _say(context, ok ? 'Αποθηκεύτηκε.' : 'Δεν αποθηκεύτηκε ακόμα. Αν γέμισε ο χώρος του κινητού, ελευθέρωσε λίγο και δοκίμασε ξανά.');
      },
    );
  }
}
