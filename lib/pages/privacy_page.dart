/// Ρυθμίσεις: γραμμές με ενότητες, «Απόρρητο» (αναφορές σφαλμάτων, πολιτική) και «Διαγραφή όλων των δεδομένων»
/// (έλεγχος 9/11, E3-05 / V-A-23), όπως τα εγκεκριμένα σχέδια Settings / SettingsDelete.
///
/// Διαγραφή: δύο επιβεβαιώσεις (το κουμπί στις Ρυθμίσεις, μετά «Κατάλαβα· δεν γίνεται αναίρεση» + «Διαγραφή όλων»).
/// Ό,τι ΔΕΝ σβήνεται λέγεται πριν πατήσεις.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart';
import '../error_report.dart';
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

/// Τι ΔΕΝ σβήνεται, και πότε σβήνει το ρολόι.
const wipeKeepsText = 'Μένουν: ό,τι έχουν το Samsung Health και το Oura στις δικές τους εφαρμογές, αντίγραφα που έχεις '
    'ήδη εξάγει στις Λήψεις και το αντίγραφο της Google. Στο ρολόι σβήνονται μόλις ανοίξεις την εφαρμογή του.';

const wipeFailedText = 'Δεν έγινε η διαγραφή. Κάν\' την από τις Ρυθμίσεις Android › Εφαρμογές › Υγεία & Φόρμα › '
    'Αποθηκευτικός χώρος › Διαγραφή δεδομένων.';

const errorsOnText = 'Όταν κάτι χαλάσει, στέλνεται μόνο τι χάλασε και σε ποια οθόνη. Ποτέ φαγητά, μετρήσεις υγείας ή ονόματα.';
const errorsOffText = 'Κλειστές: δεν στέλνεται τίποτα, και όσες περίμεναν σβήστηκαν.';

/// Η διαγραφή: πρώτα ό,τι θέλει δίκτυο (ανάκληση της Oura, με όριο χρόνου), μετά η πλευρά Android σβήνει τα πάντα
/// (και στέλνει στο ρολόι «σβήσε») και κλείνει την εφαρμογή. `false` αν δεν έγινε (η εφαρμογή δεν έκλεισε).
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
        child: Text(text.toUpperCase(),
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
  final Future<bool> Function()? wipe;
  final Future<void> Function()? export;

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

Future<void> showDeleteAllSheet(BuildContext context, {HealthStore? store, Future<bool> Function()? wipe, Future<void> Function()? export}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: 'Διαγραφή όλων'),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .92),
        child: DeleteAllSheet(store: store, wipe: wipe, export: export),
      ),
    );

/// Το φύλλο επιβεβαίωσης (SettingsDelete): τι σβήνεται, τι μένει, «Πρώτα εξαγωγή αντιγράφου», «Κατάλαβα» και το
/// κόκκινο «Διαγραφή όλων», που ανοίγει μόνο με το «Κατάλαβα».
class DeleteAllSheet extends StatefulWidget {
  const DeleteAllSheet({super.key, this.store, this.wipe, this.export, this.understood = false});
  final HealthStore? store;

  /// Μόνο για δοκιμές και στιγμιότυπα.
  final Future<bool> Function()? wipe;
  final Future<void> Function()? export;
  final bool understood;

  @override
  State<DeleteAllSheet> createState() => _DeleteAllSheetState();
}

class _DeleteAllSheetState extends State<DeleteAllSheet> {
  late bool _ok = widget.understood;
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

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('wipe-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: _busy ? null : () => widget.export!(),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Πρώτα εξαγωγή αντιγράφου', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const ValueKey('wipe-understood'),
                value: _ok,
                onChanged: _busy ? null : (v) => setState(() => _ok = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: c.bad,
                title: Text('Κατάλαβα· δεν γίνεται αναίρεση.', style: TextStyle(fontSize: 15.5, color: c.text)),
              ),
              if (_failed) ...[
                const SizedBox(height: 4),
                Text(wipeFailedText, key: const ValueKey('wipe-failed'), style: TextStyle(fontSize: 14, height: 1.4, color: c.bad)),
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
                onPressed: _ok && !_busy ? _wipe : null,
                child: Text(_busy ? 'Σβήνω…' : 'Διαγραφή όλων', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 4),
              TextButton(
                key: const ValueKey('wipe-cancel'),
                onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
                child: Text('Άκυρο', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
              ),
              if (_busy) const LinearProgressIndicator(),
            ]),
          ),
        ),
      ),
    );
  }
}
