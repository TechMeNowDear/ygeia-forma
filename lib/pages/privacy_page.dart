/// Ρυθμίσεις: γραμμές με ενότητες, «Απόρρητο» (αναφορές σφαλμάτων, πολιτική) και «Διαγραφή όλων των δεδομένων»
/// (έλεγχος 9/11, E3-05 / V-A-23), όπως τα εγκεκριμένα σχέδια Settings / SettingsDelete.
///
/// Διαγραφή: δύο επιβεβαιώσεις (το κουμπί στις Ρυθμίσεις, μετά «Κατάλαβα· δεν γίνεται αναίρεση» + «Διαγραφή όλων»).
/// Ό,τι ΔΕΝ σβήνεται λέγεται πριν πατήσεις.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart';
import '../error_report.dart';
import '../format.dart' show upperGr;
import '../theme.dart';
import '../widgets.dart';

const _privacy = MethodChannel('ygeia/privacy');

/// Τι σβήνεται (στο σχέδιο: τέσσερις γραμμές).
const wipeDeletes = <String>[
  'Φαγητά και τα προϊόντα σου',
  'Ζυγίσεις, ύπνος και μετρήσεις που κρατά η εφαρμογή',
  'Προπονήσεις, περπατήματα, πρόγραμμα, όριο παλμών',
  'Ρυθμίσεις και η σύνδεση με το Oura',
];

/// Τι ΔΕΝ σβήνεται, και πότε σβήνει το ρολόι. Μόνο ό,τι ισχύει (έλεγχος του fix-accuracy, M4/S5/N7).
const wipeKeepsText = 'Μένουν: ό,τι έχουν το Samsung Health και το Oura στις δικές τους εφαρμογές, οι άδειες που έδωσες '
    'στο Samsung Health, αρχεία που έβγαλες στις Λήψεις (αντίγραφα, PDF), το αντίγραφο της Google και η επιλογή για τις '
    'αναφορές σφαλμάτων. Το ρολόι σβήνεται όταν ανοίξεις την εφαρμογή του (όχι στη μέση άσκησης).';

/// Η διαγραφή δεν ξεκίνησε στο κινητό (η Kotlin δεν έγραψε καν το σημάδι της): τίποτα δεν σβήστηκε εδώ ή στο ρολόι.
String wipeNotStartedText({required bool ouraClosed}) =>
    'Η διαγραφή δεν ξεκίνησε: τίποτα δεν σβήστηκε από το κινητό και το ρολόι. Δοκίμασε ξανά.'
    '${ouraClosed ? ' Η σύνδεση με το Oura όμως έκλεισε· ξανασυνδέεσαι από τις Ρυθμίσεις › Πηγές.' : ''}';

/// Στο φύλλο, για την εξαγωγή πριν από τη διαγραφή.
const wipeNoBackupText = 'Χωρίς αντίγραφο: όσα υπάρχουν μόνο σε αυτό το κινητό (φαγητό, προϊόντα, προπονήσεις) χάνονται.';

/// Η Oura δεν απάντησε στην ανάκληση (π.χ. χωρίς ίντερνετ): τα tokens σβήστηκαν μόνο από το κινητό (S4).
const wipeOuraNotRevokedText = 'Η πρόσβαση στο Oura δεν ακυρώθηκε στην Oura (ίσως δεν είχες ίντερνετ). '
    'Ακύρωσέ τη από την εφαρμογή Oura.';

const wipeWatchDoneText = 'Ρολόι: σβήστηκε.';
const wipeWatchWaitingText = 'Ρολόι: περιμένει. Σβήνεται μόλις συνδεθεί και ανοίξεις την εφαρμογή του.';

const errorsOnText = 'Όταν κάτι χαλάσει, στέλνεται μόνο τι χάλασε και σε ποια οθόνη. Ποτέ φαγητά, μετρήσεις υγείας ή ονόματα.';
const errorsOffText = 'Κλειστές: δεν στέλνεται τίποτα, και όσες περίμεναν σβήστηκαν.';

/// Αποτέλεσμα μιας εξαγωγής αντιγράφου: [ok] μόνο για πλήρες αντίγραφο που γράφτηκε· [text] για τον χρήστη.
typedef BackupResult = ({bool ok, String text});

/// Η διαγραφή (έλεγχος 9/11, E3-05· ξανασχεδιασμένη στον έλεγχο του fix-accuracy, M1/M4):
/// 1. Oura: ανάκληση της πρόσβασης (με όριο χρόνου)· αν η Oura δεν απαντήσει, τα tokens σβήνονται μόνο εδώ και το λέμε.
/// 2. Android (`DataWipe.kt`): σημάδι «διαγραφή» πρώτα, «σβήσε» προς το ρολόι, widgets χωρίς τιμές, σβήσιμο όλων των
///    αρχείων της εφαρμογής από την ίδια (όχι «Διαγραφή δεδομένων» του συστήματος: θα έσβηνε και το σημάδι) και νέα
///    εκκίνηση. Στην εκκίνηση το σβήσιμο γίνεται ξανά πριν ξεκινήσει η Flutter (τίποτα δεν μένει από εγγραφές της στιγμής).
/// Με επιτυχία η εφαρμογή ξεκινά από την αρχή και αυτή η συνάρτηση δεν επιστρέφει ποτέ. Αλλιώς: τι να πει το φύλλο.
Future<String> wipeAllData(HealthStore? store) async {
  var oura = 'none';
  if (store != null && store.ouraHasTokens) {
    var revoked = false;
    try {
      revoked = await store.ouraLink.disconnect().timeout(const Duration(seconds: 15));
    } catch (_) {}
    oura = revoked ? 'revoked' : 'failed';
  }
  try {
    await _privacy.invokeMethod<Object?>('wipe', {'oura': oura});
  } catch (_) {}
  return wipeNotStartedText(ouraClosed: oura != 'none');
}

/// Η κατάσταση μετά από μια «Διαγραφή όλων» (από την πλευρά Android, αρχείο «ygeia_wipe»).
class WipeStatus {
  const WipeStatus({required this.at, required this.done, required this.seen, required this.watchPending, required this.oura});

  /// Πότε έγινε.
  final DateTime at;

  /// Σβήστηκαν όλα τα αρχεία του κινητού (αλλιώς: «η διαγραφή δεν τελείωσε»).
  final bool done;

  /// Ο χρήστης είδε ήδη την οθόνη «Όλα διαγράφηκαν».
  final bool seen;

  /// Το ρολόι δεν επιβεβαίωσε ακόμα.
  final bool watchPending;

  /// «revoked», «failed» ή «none» (δεν ήταν συνδεδεμένο).
  final String oura;

  /// Η οθόνη «Όλα διαγράφηκαν» (ή «δεν τελείωσε») στην εκκίνηση.
  bool get show => !done || !seen;

  static WipeStatus? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'];
    if (at is! num || at <= 0) return null;
    return WipeStatus(
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      done: raw['stage'] == 'done',
      seen: raw['seen'] == true,
      watchPending: raw['pending'] != false,
      oura: raw['oura'] is String ? raw['oura'] as String : 'none',
    );
  }
}

/// Στην εκκίνηση: έγινε «Διαγραφή όλων»; Με όριο χρόνου, ώστε να μην καθυστερεί ποτέ το άνοιγμα. Αν το ρολόι δεν έχει
/// επιβεβαιώσει ακόμα, η Kotlin ξαναστέλνει το «σβήσε» (μόνο αν λείπει) και κοιτά για την επιβεβαίωση, στο παρασκήνιο.
Future<WipeStatus?> readWipeStatus() async {
  try {
    final st = WipeStatus.fromMap(await _privacy.invokeMethod<Object?>('wipeStatus').timeout(const Duration(seconds: 2)));
    if (st != null && st.watchPending) unawaited(wipeWatchState());
    return st;
  } catch (_) {
    return null;
  }
}

/// Το ρολόι επιβεβαίωσε τη διαγραφή; («acked» / «waiting»).
Future<String> wipeWatchState() async {
  try {
    return await _privacy.invokeMethod<String>('wipeWatch') ?? 'waiting';
  } catch (_) {
    return 'waiting';
  }
}

Future<void> markWipeSeen() async {
  try {
    await _privacy.invokeMethod<bool>('wipeSeen');
  } catch (_) {}
}

/// «Συνέχεια διαγραφής»: ξανά το σβήσιμο των αρχείων (με επιτυχία νέα εκκίνηση· αλλιώς επιστρέφει).
Future<void> retryWipe() async {
  try {
    await _privacy.invokeMethod<Object?>('wipeRetry');
  } catch (_) {}
}

/// Αντιγραφή με σήμανση «ευαίσθητο» (έλεγχος 9/11, E3-20): το Android 13+ δεν δείχνει το κείμενο στην προεπισκόπηση
/// και πληκτρολόγια σαν το Samsung Keyboard δεν το κρατούν στο ιστορικό προχείρου. Αν δεν γίνει, κανονική αντιγραφή.
Future<void> copySensitive(String text) async {
  try {
    if (await _privacy.invokeMethod<bool>('copy', text) == true) return;
  } catch (_) {}
  await Clipboard.setData(ClipboardData(text: text));
}

/// Άδειες λογισμικού (έλεγχος 9/11, E3-21): η Flutter δείχνει μόνες τους τις άδειες των πακέτων Dart· εδώ μπαίνουν
/// η γραμματοσειρά Inter (SIL OFL 1.1, το κείμενό της ταξιδεύει στο APK) και οι βιβλιοθήκες Android (Apache 2.0).
void registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Inter (γραμματοσειρά)'], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
    yield const LicenseEntryWithLineBreaks(
      ['AndroidX', 'Kotlin coroutines', 'Gson', 'Health Services', 'Wear Ongoing'],
      'Apache License, Version 2.0. https://www.apache.org/licenses/LICENSE-2.0',
    );
  });
}

void openLicenses(BuildContext context) => showLicensePage(context: context, applicationName: 'Υγεία & Φόρμα');

Future<void> openPrivacyPolicy() async {
  try {
    await _privacy.invokeMethod<bool>('openPolicy');
  } catch (_) {}
}

// ---------------------------------------------------------------- γραμμές των Ρυθμίσεων

/// Τίτλος ενότητας («ΑΠΟΡΡΗΤΟ»).
class SettingsSection extends StatelessWidget {
  const SettingsSection(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(upperGr(text),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .3, color: Aigaio.of(context).textSecondary)),
      );
}

/// Κάρτα με γραμμές, χωρισμένες με λεπτή γραμμή.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: c.hairline),
          children[i],
        ],
      ]),
    );
  }
}

/// Μία γραμμή: εικονίδιο, τίτλος, γκρι υπότιτλος (έως 3 γραμμές), δεξιά βέλος ή διακόπτης.
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.trailing, this.color, this.danger = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? color;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final tint = danger ? c.bad : (color ?? c.primary);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconBadge(icon, tint, size: 38),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: danger ? c.bad : c.text)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: TextStyle(fontSize: 13.5, height: 1.35, color: c.textSecondary)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          trailing ?? (onTap == null ? const SizedBox.shrink() : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
          )),
        ]),
      ),
    );
  }
}

/// «ΑΠΟΡΡΗΤΟ»: ο διακόπτης για τις αναφορές σφαλμάτων και η πολιτική απορρήτου.
class PrivacyGroup extends StatelessWidget {
  const PrivacyGroup({super.key, this.reporter});

  /// Μόνο για δοκιμές (αλλιώς ο αναφορέας της εφαρμογής).
  final ErrorReporter? reporter;

  @override
  Widget build(BuildContext context) {
    final r = reporter ?? errors;
    return SettingsGroup(key: const ValueKey('settings-privacy'), children: [
      ValueListenableBuilder<bool>(
        valueListenable: r.sending,
        builder: (context, on, _) => SettingsRow(
          icon: Icons.shield_outlined,
          title: 'Αναφορές σφαλμάτων',
          subtitle: on ? errorsOnText : errorsOffText,
          trailing: Switch(
            key: const ValueKey('privacy-errors'),
            value: on,
            onChanged: (v) async {
              final ok = await r.setEnabled(v);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Η επιλογή δεν αποθηκεύτηκε. Δοκίμασε ξανά.')));
              }
            },
          ),
        ),
      ),
      const SettingsRow(
        key: ValueKey('privacy-policy'),
        icon: Icons.inventory_2_outlined,
        title: 'Πολιτική απορρήτου',
        subtitle: 'Τι κρατάμε, πού, για πόσο',
        onTap: openPrivacyPolicy,
      ),
    ]);
  }
}


/// Η γραμμή «Διαγραφή όλων των δεδομένων» (μέσα στο «ΤΑ ΔΕΔΟΜΕΝΑ ΜΟΥ»).
class DeleteAllRow extends StatelessWidget {
  const DeleteAllRow({super.key, required this.store, this.wipe, this.export});
  final HealthStore? store;
  final Future<String> Function()? wipe;
  final Future<BackupResult> Function()? export;

  @override
  Widget build(BuildContext context) => SettingsRow(
        key: const ValueKey('privacy-delete'),
        icon: Icons.delete_outline_rounded,
        title: 'Διαγραφή όλων των δεδομένων',
        subtitle: 'Από αυτό το κινητό και το ρολόι',
        danger: true,
        onTap: () => showDeleteAllSheet(context, store: store, wipe: wipe, export: export),
      );
}

/// Το φύλλο: δεν κλείνει με σύρσιμο, και όσο δουλεύει (εξαγωγή ή διαγραφή) ούτε με «πίσω»/πάτημα έξω (S3).
Future<void> showDeleteAllSheet(BuildContext context,
        {HealthStore? store, Future<String> Function()? wipe, Future<BackupResult> Function()? export}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      showDragHandle: false,
      routeSettings: const RouteSettings(name: 'Διαγραφή όλων'),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .92),
        child: DeleteAllSheet(store: store, wipe: wipe, export: export),
      ),
    );

/// Το φύλλο επιβεβαίωσης (SettingsDelete): τι σβήνεται, τι μένει, «Πρώτα εξαγωγή αντιγράφου» (με το αποτέλεσμα μέσα
/// στο φύλλο) ή ρητά «Χωρίς αντίγραφο», «Κατάλαβα» και το κόκκινο «Διαγραφή όλων», που ανοίγει μόνο όταν έχουν γίνει
/// και τα δύο (έλεγχος του fix-accuracy, M2).
class DeleteAllSheet extends StatefulWidget {
  const DeleteAllSheet({super.key, this.store, this.wipe, this.export, this.understood = false, this.noBackup = false});
  final HealthStore? store;

  /// Μόνο για δοκιμές και στιγμιότυπα.
  final Future<String> Function()? wipe;
  final Future<BackupResult> Function()? export;
  final bool understood;
  final bool noBackup;

  @override
  State<DeleteAllSheet> createState() => _DeleteAllSheetState();
}

class _DeleteAllSheetState extends State<DeleteAllSheet> {
  late bool _ok = widget.understood;
  late bool _noBackup = widget.noBackup;
  bool _busy = false;
  bool _exporting = false;
  BackupResult? _backup;
  String? _failed;

  /// Χωρίς εξαγωγή στη σελίδα (π.χ. δεν φορτώθηκε το φαγητό): δεν ζητείται.
  bool get _backupDecided => widget.export == null || _noBackup || (_backup?.ok ?? false);

  bool get _working => _busy || _exporting;

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _backup = null;
    });
    BackupResult r;
    try {
      r = await widget.export!();
    } catch (_) {
      r = (ok: false, text: 'Δεν αποθηκεύτηκε το αντίγραφο. Δοκίμασε ξανά.');
    }
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _backup = r;
      if (r.ok) _noBackup = false;
    });
  }

  Future<void> _wipe() async {
    setState(() {
      _busy = true;
      _failed = null;
    });
    final text = await (widget.wipe ?? () => wipeAllData(widget.store))();
    // Με επιτυχία η εφαρμογή ξεκινά από την αρχή· αν φτάσουμε εδώ, δεν έγινε.
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final backup = _backup;
    return PopScope(
      canPop: !_working,
      child: SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('wipe-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Η λαβή του σχεδίου (μόνο εικόνα: το φύλλο δεν κλείνει με σύρσιμο).
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 20),
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(color: c.textTertiary, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  IconBadge(Icons.delete_outline_rounded, c.bad, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Διαγραφή όλων των δεδομένων;',
                        style: TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w800, color: c.text)),
                  ),
                ]),
                const SizedBox(height: 16),
                Text('Σβήνονται από αυτό το κινητό και το ρολόι:',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.text)),
                for (final t in wipeDeletes)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Container(width: 7, height: 7, decoration: BoxDecoration(color: c.bad, shape: BoxShape.circle)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t, style: TextStyle(fontSize: 15.5, height: 1.4, color: c.text))),
                    ]),
                  ),
                const SizedBox(height: 16),
                Container(
                  key: const ValueKey('wipe-keeps'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(12)),
                  child: Text(wipeKeepsText, style: TextStyle(fontSize: 13.5, height: 1.45, color: c.textSecondary)),
                ),
                if (widget.export != null) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    key: const ValueKey('wipe-export'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: _working ? null : _export,
                    icon: _exporting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(backup?.ok == true ? Icons.check_rounded : Icons.download_rounded),
                    label: Text(_exporting ? 'Αποθηκεύεται…' : 'Πρώτα εξαγωγή αντιγράφου',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (backup != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(backup.text,
                          key: const ValueKey('wipe-export-result'),
                          style: TextStyle(fontSize: 13.5, height: 1.4, color: backup.ok ? c.good : c.bad)),
                    ),
                  if (backup?.ok != true)
                    CheckboxListTile(
                      key: const ValueKey('wipe-no-backup'),
                      value: _noBackup,
                      onChanged: _working ? null : (v) => setState(() => _noBackup = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: c.bad,
                      title: Text('Χωρίς αντίγραφο', style: TextStyle(fontSize: 15.5, color: c.text)),
                    ),
                  if (_noBackup && backup?.ok != true)
                    Text(wipeNoBackupText, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.bad)),
                ],
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const ValueKey('wipe-understood'),
                  value: _ok,
                  onChanged: _working ? null : (v) => setState(() => _ok = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  activeColor: c.bad,
                  title: Text('Κατάλαβα· δεν γίνεται αναίρεση.', style: TextStyle(fontSize: 15.5, color: c.text)),
                ),
                if (_failed != null) ...[
                  const SizedBox(height: 4),
                  Text(_failed!, key: const ValueKey('wipe-failed'), style: TextStyle(fontSize: 14, height: 1.4, color: c.bad)),
                ],
                const SizedBox(height: 8),
                FilledButton(
                  key: const ValueKey('wipe-confirm'),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.bad,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _ok && _backupDecided && !_working ? _wipe : null,
                  child: Text(_busy ? 'Σβήνω…' : 'Διαγραφή όλων', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 4),
                TextButton(
                  key: const ValueKey('wipe-cancel'),
                  onPressed: _working ? null : () => Navigator.of(context).maybePop(),
                  child: Text('Άκυρο', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
                ),
                if (_busy) const LinearProgressIndicator(),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Όλα διαγράφηκαν» (σχέδιο SettingsDeleted), στην πρώτη εκκίνηση μετά τη διαγραφή. Λέει μόνο ό,τι ισχύει: το κινητό
/// είναι καθαρό· το ρολόι «σβήστηκε» μόνο όταν το επιβεβαιώσει, αλλιώς «περιμένει»· η Oura αν δεν πήρε την ανάκληση.
/// Αν το σβήσιμο των αρχείων δεν τελείωσε: «Συνέχεια διαγραφής» (όχι «όλα διαγράφηκαν»).
class WipedPage extends StatefulWidget {
  const WipedPage({super.key, required this.status, required this.onStart, required this.onRestore, this.watch, this.retry});
  final WipeStatus status;
  final VoidCallback onStart;
  final VoidCallback onRestore;

  /// Μόνο για δοκιμές και στιγμιότυπα.
  final Future<String> Function()? watch;
  final Future<void> Function()? retry;

  @override
  State<WipedPage> createState() => _WipedPageState();
}

class _WipedPageState extends State<WipedPage> {
  late bool _watchDone = !widget.status.watchPending;
  bool _retrying = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (!_watchDone && widget.status.done) {
      _check();
      // Μόνο όσο φαίνεται αυτή η οθόνη, κάθε 15″, ώσπου να απαντήσει το ρολόι.
      _poll = Timer.periodic(const Duration(seconds: 15), (_) => _check());
    }
  }

  Future<void> _check() async {
    final s = await (widget.watch ?? wipeWatchState)();
    if (!mounted || s != 'acked') return;
    _poll?.cancel();
    setState(() => _watchDone = true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final done = widget.status.done;
    Widget line(IconData icon, String text, Color color, Key key) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(key: key, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(fontSize: 15, height: 1.4, color: c.text))),
          ]),
        );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 64),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(color: c.hairline, shape: BoxShape.circle),
                          child: Icon(done ? Icons.check_rounded : Icons.hourglass_bottom_rounded, size: 40, color: c.text),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(done ? 'Όλα διαγράφηκαν' : 'Η διαγραφή δεν τελείωσε',
                          key: const ValueKey('wiped-title'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 30, height: 1.15, fontWeight: FontWeight.w800, color: c.text)),
                      const SizedBox(height: 10),
                      Text(
                          done
                              ? 'Η εφαρμογή σε αυτό το κινητό είναι όπως την πρώτη μέρα.'
                              : 'Κάποια αρχεία στο κινητό δεν σβήστηκαν ακόμα. Πάτα «Συνέχεια διαγραφής». Αν δεν γίνει: '
                                  'Ρυθμίσεις Android › Εφαρμογές › Υγεία & Φόρμα › Αποθηκευτικός χώρος › Διαγραφή δεδομένων.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, height: 1.4, color: c.textSecondary)),
                      const SizedBox(height: 8),
                      if (done)
                        line(Icons.watch_outlined, _watchDone ? wipeWatchDoneText : wipeWatchWaitingText,
                            _watchDone ? c.good : c.textSecondary, const ValueKey('wiped-watch')),
                      if (widget.status.oura == 'failed')
                        line(Icons.error_outline_rounded, wipeOuraNotRevokedText, c.bad, const ValueKey('wiped-oura')),
                      const SizedBox(height: 16),
                      Text(
                          'Το Samsung Health και το Oura κρατούν τα δικά τους δεδομένα. Για να σβηστούν κι εκεί, γίνεται από '
                          'τις δικές τους εφαρμογές.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary)),
                    ]),
                  ),
                ),
                if (done) ...[
                  FilledButton(
                    key: const ValueKey('wiped-start'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: widget.onStart,
                    child: const Text('Ξεκίνα από την αρχή', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    key: const ValueKey('wiped-restore'),
                    onPressed: widget.onRestore,
                    child: const Text('Επαναφορά από αντίγραφο', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                  ),
                ] else
                  FilledButton(
                    key: const ValueKey('wiped-retry'),
                    style: FilledButton.styleFrom(
                        backgroundColor: c.bad,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: _retrying
                        ? null
                        : () async {
                            setState(() => _retrying = true);
                            await (widget.retry ?? retryWipe)();
                            if (mounted) setState(() => _retrying = false);
                          },
                    child: Text(_retrying ? 'Σβήνω…' : 'Συνέχεια διαγραφής', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
