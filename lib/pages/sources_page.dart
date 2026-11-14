import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../oura/oura_store.dart';
import '../plan_file.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import 'oura_pages.dart';
import 'oxygen_widgets.dart';
import 'source_widgets.dart';

/// Ρυθμίσεις › Πηγές: οι συσκευές, και ο πίνακας «Από πού παίρνουμε τι» — φτιαγμένος ΑΠΟ τον πίνακα
/// του κώδικα (sources.dart), ώστε η οθόνη να μη διαφωνεί ποτέ με ό,τι πραγματικά υπολογίζεται.
class SourcesPage extends StatelessWidget {
  const SourcesPage({super.key, required this.store, this.now});
  final HealthStore store;

  /// Για τα στιγμιότυπα δοκιμών.
  final DateTime? now;

  static const routeName = 'Πηγές';

  static Route<void> route(HealthStore store, {DateTime? now}) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: routeName),
        builder: (_) => SourcesPage(store: store, now: now),
      );

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Πηγές'), backgroundColor: c.background, surfaceTintColor: Colors.transparent),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final today = dayOf(now ?? DateTime.now());
          final plan = store.plan;
          final d = store.data;
          final nightSrc = plan.nightSource(today);
          final unknownPlan = store.planState == PlanState.unknown;
          // Round 1 (U2b-02): χωρίς πηγή ύπνου (μετά την αποσύνδεση) η γραμμή του Oura ανοίγει τη σελίδα «Oura», όπου
          // είναι το «Ο ύπνος ξανά από το ρολόι»· πριν άνοιγε τη «Σύνδεση Oura» και η κάρτα έστελνε σε αδιέξοδο.
          final manage = store.ouraActive || store.ouraHasTokens || nightSrc == Source.none;
          // Round 1 (U2b-14): «ο ύπνος του ρολογιού δεν διαβάζεται» μόνο όσο πράγματι δεν διαβάζεται (ο ίδιος κανόνας
          // με τον κώδικα, [SourcePlan.watchSleepCutoff])· μετά το «ξανά από το ρολόι» διαβάζεται.
          final watchSleepOff = plan.hasOura && plan.watchSleepCutoff(today) != null;

          final devices = AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Συσκευές'),
                const SizedBox(height: 6),
                _DeviceRow(
                  icon: Icons.radio_button_unchecked_rounded,
                  name: sourceDevice(Source.oura),
                  status: _ouraStatus(store, today),
                  action: manage ? 'Διαχείριση' : 'Σύνδεση',
                  onTap: () => Navigator.of(context).push(
                    manage ? OuraManagePage.route(store, now: now) : OuraConnectPage.route(store, now: now),
                  ),
                ),
                const Hairline(vertical: 4),
                _DeviceRow(
                  icon: Icons.watch_rounded,
                  name: sourceDevice(Source.watch),
                  // Round 1 (U2b-16): η ώρα είναι το πότε ΔΙΑΒΑΣΕ η εφαρμογή τη Samsung Health (όχι πότε συγχρόνισε το ρολόι).
                  status: d == null ? 'Μέσω Samsung Health' : 'Μέσω Samsung Health ·\u00A0διαβάστηκε ${_when(d.readAt, today)}',
                ),
                const Hairline(vertical: 4),
                _DeviceRow(
                  icon: Icons.monitor_weight_outlined,
                  name: sourceDevice(Source.scale),
                  status: d?.latestBody == null
                      ? 'Μέσω Samsung Health'
                      : 'Μέσω Samsung Health ·\u00A0τελευταία ζύγιση '
                          '${sameDay(d!.latestBody!.time, today) ? 'σήμερα' : shortDayDate(d.latestBody!.time)}',
                ),
              ],
            ),
          );

          final table = AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Ποια συσκευή μετρά τι'),
                const SizedBox(height: 6),
                Text(
                  // Round 1 (U2b-17): «πηγή» (τα βήματα είναι το σύνολο της Samsung Health: ρολόι ΚΑΙ κινητό).
                  'Μία πηγή για κάθε μέτρηση, ποτέ ανάμειξη, ούτε όταν λείπει.'
                  '${watchSleepOff ? ' Ο ύπνος του ρολογιού δεν διαβάζεται.' : ''}',
                  style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
                ),
                const SizedBox(height: 8),
                for (final (i, r) in sourceRows.indexed) ...[
                  if (i > 0) const Hairline(vertical: 2),
                  // Round 1 (U2b-07): χωρίς πηγή ύπνου το οξυγόνο της νύχτας δεν βγαίνει καθόλου («Καμία», όχι «Ρολόι»).
                  _TableRow(
                    row: r,
                    source: r.needsNight && nightSrc == Source.none ? Source.none : plan.sourceFor(r.metrics.first, today),
                    unknown: unknownPlan,
                  ),
                ],
              ],
            ),
          );

          final notUsed = watchSleepOff
              ? AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionLabel('Τι δεν χρησιμοποιούμε'),
                      const SizedBox(height: 8),
                      for (final t in notUsedWithOura)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(Icons.block_rounded, size: 16, color: c.textTertiary),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Text(t, style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.35))),
                            ],
                          ),
                        ),
                    ],
                  ),
                )
              : null;

          // Οι νύχτες έχουν την ημερομηνία του πρωινού: «νύχτα προς 7/11» = από το βράδυ της 6/11.
          String nightTo(DateTime d) => 'τη νύχτα προς ${shortDayDate(d)}';
          final history = plan.eras.isEmpty || store.planState != PlanState.ok
              ? null
              : AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionLabel('Αλλαγές πηγής ύπνου'),
                      const SizedBox(height: 6),
                      // Round 1 (U2b-03): πριν έλεγε «κάθε αλλαγή ισχύει από το βράδυ της μέρας που την έκανες», που δεν
                      // ισχύει όταν απάντησες «Ναι, μετρά από το δαχτυλίδι» (η νύχτα πριν μετρά από το Oura).
                      Text(
                        'Κάθε γραμμή δείχνει από ποια νύχτα μετρά κάθε πηγή. Οι παλιές νύχτες μένουν με την πηγή τους και '
                        'οι Τάσεις δεν συγκρίνουν ποτέ νύχτες από δύο συσκευές.',
                        style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
                      ),
                      const SizedBox(height: 4),
                      InfoRow(
                        'Ως ${nightTo(DateTime(plan.eras.first.from.year, plan.eras.first.from.month, plan.eras.first.from.day - 1))}',
                        sourceName(Source.watch),
                      ),
                      for (final e in plan.eras) InfoRow('Από ${nightTo(e.from)}', sourceName(e.source)),
                    ],
                  ),
                );

          // Το σχέδιο πηγών δεν διαβάστηκε: ρητή επιλογή, τίποτα αυτόματο.
          final unknown = unknownPlan ? PlanRecoveryCard(store: store) : null;

          final compare = OuraOxygenAccessCard.orNull(store);

          // Round 1 (U2b-02 / U2b-09): κουμπί προς τη σελίδα «Oura» (ίδια λέξη με τη «Σήμερα»)· και μετά το «Ο ύπνος
          // ξανά από το ρολόι» η κάρτα λέει ότι η επιλογή έγινε.
          final noSource = nightSrc != Source.none
              ? null
              : store.watchSleepFromTonight
                  ? EmptyCard(
                      icon: Icons.bedtime_rounded,
                      color: c.sleep,
                      title: 'Από απόψε ο ύπνος από το ρολόι',
                      text: 'Το Oura αποσυνδέθηκε και διάλεξες το ρολόι: από απόψε ο ύπνος έρχεται από το Galaxy Watch. Η '
                          'χθεσινή νύχτα μένει κενή.',
                    )
                  : EmptyCard(
                      icon: Icons.bedtime_off_rounded,
                      color: c.sleep,
                      title: 'Ο ύπνος δεν έχει πηγή',
                      text: 'Το Oura αποσυνδέθηκε. Οι νύχτες μένουν κενές ώσπου να το συνδέσεις ξανά ή να διαλέξεις το ρολόι, '
                          'στις «Ρυθμίσεις Oura».',
                      buttonText: 'Ρυθμίσεις Oura',
                      onPressed: () => Navigator.of(context).push(OuraManagePage.route(store, now: now)),
                    );

          return LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 760;
              final left = <Widget>[
                if (unknown != null) unknown,
                if (noSource != null && unknown == null) noSource,
                devices,
                if (compare != null) compare,
                if (history != null) history,
              ];
              final right = <Widget>[table, if (notUsed != null) notUsed];
              Widget col(List<Widget> items) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, w) in items.indexed) ...[if (i > 0) const SizedBox(height: 12), w],
                    ],
                  );
              return ListView(
                padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 8, wide ? 28 : 16, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: wide ? 1080 : 680),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: col(left)),
                                const SizedBox(width: 16),
                                Expanded(child: col(right)),
                              ],
                            )
                          : col([...left, ...right]),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// «10:08» (σήμερα), «χθες 22:10», «Πέμπτη 09:15», «4 Νοε 08:00». Round 1 (U2b-16): «χθες» με μικρό (μέσα σε πρόταση).
  static String _when(DateTime t, DateTime today) {
    if (sameDay(t, today)) return hm(t);
    final day = relativeDay(t, today);
    return '${day == 'Χθες' ? 'χθες' : day} ${hm(t)}';
  }

  static String _ouraStatus(HealthStore s, DateTime today) {
    if (s.planState == PlanState.unknown) {
      // Round 1 (U2b-05): όταν το ιστορικό δεν έχει διαβαστεί ακόμα, πάνω υπάρχει μόνο «Δοκίμασε ξανά» (τίποτα να διαλέξεις).
      final what = s.planRecovery == null ? 'πάτα «Δοκίμασε ξανά» πάνω' : 'διάλεξε πηγή ύπνου πάνω';
      return s.ouraHasTokens ? 'Συνδεδεμένο ·\u00A0$what' : '${what[0].toUpperCase()}${what.substring(1)}';
    }
    if (!s.ouraConfigured && !s.ouraHasTokens) return 'Η σύνδεση ενεργοποιείται τη μέρα που θα έρθει';
    return switch (s.ouraStatus) {
      OuraStatus.off => s.ouraHasTokens ? 'Συνδεδεμένο' : 'Δεν έχει συνδεθεί',
      OuraStatus.starting => 'Συνδεδεμένο ·\u00A0ο ύπνος από το Oura από απόψε',
      OuraStatus.startingNow => 'Συνδεδεμένο ·\u00A0${s.ouraFirstNightText.toLowerCase()}',
      OuraStatus.incomplete => 'Η σύνδεση δεν ολοκληρώθηκε· δοκίμασε ξανά',
      // Round 1 (U2b-09): μετά το «Ο ύπνος ξανά από το ρολόι».
      OuraStatus.disconnected => s.watchSleepFromTonight ? 'Αποσυνδέθηκε ·\u00A0από απόψε ο ύπνος από το ρολόι' : 'Αποσυνδέθηκε',
      OuraStatus.reconnect => 'Χρειάζεται νέα σύνδεση',
      // Round 1 (S5-6): το 403 είναι «συνδρομή Ή άδεια».
      OuraStatus.subscription => 'Η Oura δεν δίνει δεδομένα (συνδρομή ή άδεια)',
      // Round 1 (U2b-16): «ενημερώθηκε», όπως «Τελευταία ενημέρωση» / «Ενημέρωση τώρα» στη σελίδα «Oura».
      _ => s.ouraLastSync == null ? 'Συνδεδεμένο' : 'Συνδεδεμένο ·\u00A0ενημερώθηκε ${_when(s.ouraLastSync!, today)}',
    };
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.icon, required this.name, required this.status, this.action, this.onTap});
  final IconData icon;
  final String name;
  final String status;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          IconBadge(icon, c.primary, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text)),
                const SizedBox(height: 2),
                Text(status, style: TextStyle(fontSize: 13, color: c.textSecondary)),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            Text(action!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.primary)),
            Icon(Icons.chevron_right_rounded, color: c.primary, size: 20),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      key: ValueKey('device-$name'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: row),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.row, required this.source, this.unknown = false});
  final SourceRow row;
  final Source source;

  /// Το σχέδιο πηγών δεν διαβάστηκε (U2b-05): η σημείωση στέλνει στην κάρτα πάνω.
  final bool unknown;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final title = Text(row.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text));
    final tag = SourceTag(source, label: samsungTotalMetrics.contains(row.metrics.first) && source != Source.none ? 'Samsung Health' : null);
    // Round 1 (U2b-15): τίτλος και ετικέτα στην ίδια γραμμή, η σημείωση από κάτω σε ΟΛΟ το πλάτος (πριν η ετικέτα
    // «Samsung Health» έσπαγε τον τίτλο και έκανε τη σημείωση τέσσερις κοντές γραμμές)· με πολύ μεγάλα γράμματα η
    // ετικέτα κάτω από τον τίτλο, όπως στο «Τι μετράει κάθε συσκευή».
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (veryLargeText(context)) ...[
            title,
            const SizedBox(height: 4),
            tag,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(child: title), const SizedBox(width: 10), tag],
            ),
          const SizedBox(height: 2),
          Text(row.noteFor(source, unknown: unknown), style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.3)),
        ],
      ),
    );
  }
}

/// «Δεν διαβάστηκε από πού έρχεται ο ύπνος»: επιλογές ΜΟΝΟ όταν έχει διαβαστεί το ιστορικό (αλλιώς «Δοκίμασε
/// ξανά»). Κάθε επιλογή δείχνει πρώτα όλη τη χρονογραμμή που θα μπει, για επιβεβαίωση.
class PlanRecoveryCard extends StatefulWidget {
  const PlanRecoveryCard({super.key, required this.store});
  final HealthStore store;

  @override
  State<PlanRecoveryCard> createState() => _PlanRecoveryCardState();
}

class _PlanRecoveryCardState extends State<PlanRecoveryCard> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    await widget.store.retryPlan();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _choose(RecoveryOption o) async {
    final c = Aigaio.of(context);
    final ok = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: 'Επιβεβαίωση πηγών'),
      builder: (context) => AlertDialog(
        title: Text(o.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Έτσι θα μετρούν οι νύχτες:', style: TextStyle(color: c.textSecondary, fontSize: 14)),
            const SizedBox(height: 8),
            for (final line in describePlan(o.plan))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text('• $line', style: TextStyle(color: c.text, fontSize: 14.5, height: 1.35)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Άκυρο')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ναι, αυτό')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final done = await widget.store.recoverPlan(o.plan);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!done) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Δεν αποθηκεύτηκε. Τίποτα δεν άλλαξε· δοκίμασε ξανά σε λίγο.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final options = widget.store.planRecovery;
    return AppCard(
      key: const ValueKey('plan-recover'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Δεν διαβάστηκε από πού έρχεται ο ύπνος'),
          const SizedBox(height: 6),
          Text(
            options == null
                ? 'Τα αποθηκευμένα δεδομένα δεν έχουν διαβαστεί ακόμα. Ώσπου να διαβαστούν, οι νύχτες μένουν κενές και '
                    'δεν αποθηκεύεται τίποτα, για να μην μπερδευτούν οι συσκευές.'
                : 'Οι ρυθμίσεις πηγών χάλασαν ή χάθηκαν. Ώσπου να διαλέξεις, οι νύχτες μένουν κενές και δεν '
                    'αποθηκεύεται τίποτα, για να μην μπερδευτούν οι συσκευές.',
            style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (options == null)
            FilledButton(
              key: const ValueKey('plan-retry'),
              onPressed: _busy ? null : _retry,
              child: const Text('Δοκίμασε ξανά'),
            )
          else
            for (final (i, o) in options.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              o.primary
                  ? FilledButton(onPressed: _busy ? null : () => _choose(o), child: Text(o.label))
                  : OutlinedButton(onPressed: _busy ? null : () => _choose(o), child: Text(o.label)),
            ],
        ],
      ),
    );
  }
}
