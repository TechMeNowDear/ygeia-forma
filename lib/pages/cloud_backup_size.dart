/// Μετρητής του αντιγράφου Google (18/11). Το Android σταματά το αυτόματο αντίγραφο ΣΙΩΠΗΛΑ όταν τα αρχεία της εφαρμογής
/// ξεπεράσουν τα 25 MB (developer.android.com, Auto Backup: «onQuotaExceeded … does not create a cloud backup»).
/// Μετριούνται μόνο τα αρχεία των κανόνων «cloud-backup» ([CloudBackupSize] στην Kotlin), μία φορά σε κάθε άνοιγμα.
library;

import 'package:flutter/material.dart';

import '../food/food_channel.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

/// Το όριο του Android.
const cloudBackupLimitBytes = 25 * 1024 * 1024;

/// Από εδώ και πάνω κάρτα στη «Σήμερα».
const cloudBackupWarnBytes = 20 * 1024 * 1024;

/// Η μέτρηση του ανοίγματος (null = δεν μετρήθηκε / όχι Android).
class CloudBackupMeter {
  static Future<int?>? _once;

  static Future<int?> bytes() => _once ??= () async {
        final r = await FoodChannel.cloudBackupSize();
        final b = r['bytes'];
        return r['ok'] == true && b is num && b >= 0 ? b.toInt() : null;
      }();

  /// Μόνο για δοκιμές.
  static void debugSet(int? bytes) => _once = Future.value(bytes);
}

/// «3,2 MB από 25 MB»
String cloudBackupText(int bytes) {
  var mb = bytes / (1024 * 1024);
  // Έλεγχος 19/11 (CB-3): κάτω από το όριο ποτέ «25 από 25» (στρογγύλεμα προς τα πάνω).
  if (bytes < cloudBackupLimitBytes && mb >= 24.95) mb = 24.9;
  return 'Αντίγραφο Google: ${dec(mb, mb < 10 || mb >= 24.9 && mb < 25 ? 1 : 0)} MB από 25 MB';
}

const cloudBackupStoppedText = 'Πάνω από τα 25 MB το Android δεν ενημερώνει πια το αντίγραφο Google, χωρίς να σε '
    'ειδοποιήσει. Κάνε «Εξαγωγή αντιγράφου» τώρα, και πες το στον developer.';

const cloudBackupWarnText = 'Πάνω από τα 25 MB το Android σταματά το αντίγραφο Google χωρίς να σε ειδοποιήσει. Χρειάζεται '
    'αλλαγή στην εφαρμογή πριν φτάσει εκεί· ως τότε κάνε «Εξαγωγή αντιγράφου» κάθε εβδομάδα.';

/// Η γραμμή στις Ρυθμίσεις (κάτω από «Εξαγωγή αντιγράφου»). Χωρίς μέτρηση: τίποτα.
class CloudBackupLine extends StatelessWidget {
  const CloudBackupLine({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return FutureBuilder<int?>(
      future: CloudBackupMeter.bytes(),
      builder: (context, s) {
        final b = s.data;
        if (b == null) return const SizedBox.shrink();
        final warn = b >= cloudBackupWarnBytes;
        return Padding(
          key: const ValueKey('settings-cloud-size'),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            warn ? '${cloudBackupText(b)}. ${b >= cloudBackupLimitBytes ? cloudBackupStoppedText : cloudBackupWarnText}' : cloudBackupText(b),
            style: TextStyle(color: warn ? c.warn : c.textSecondary, fontSize: 13, height: 1.35),
          ),
        );
      },
    );
  }
}

/// Κάρτα στη «Σήμερα», μόνο από [cloudBackupWarnBytes] και πάνω.
class CloudBackupWarningCard extends StatelessWidget with SelfSpaced {
  const CloudBackupWarningCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return FutureBuilder<int?>(
      future: CloudBackupMeter.bytes(),
      builder: (context, s) {
        final b = s.data;
        if (b == null || b < cloudBackupWarnBytes) return const SizedBox.shrink(key: ValueKey('today-cloud-none'));
        return Padding(
          padding: const EdgeInsets.only(bottom: PageFrame.gap),
          child: AppCard(
            key: const ValueKey('today-cloud-size'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardHeader(
                    icon: Icons.cloud_off_rounded,
                    title: b >= cloudBackupLimitBytes ? 'Το αντίγραφο Google σταμάτησε' : 'Το αντίγραφο Google γεμίζει',
                    color: c.warn),
                const SizedBox(height: 8),
                Text('${cloudBackupText(b)}.', style: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(b >= cloudBackupLimitBytes ? cloudBackupStoppedText : cloudBackupWarnText,
                    style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.35)),
              ],
            ),
          ),
        );
      },
    );
  }
}
