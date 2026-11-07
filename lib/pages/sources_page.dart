import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../oura/oura_store.dart';
import '../plan_file.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import 'oura_pages.dart';
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
                  action: store.ouraActive || store.ouraHasTokens ? 'Διαχείριση' : 'Σύνδεση',
                  onTap: () => Navigator.of(context).push(
                    store.ouraActive || store.ouraHasTokens
                        ? OuraManagePage.route(store, now: now)
                        : OuraConnectPage.route(store, now: now),
                  ),
                ),
                const Hairline(vertical: 4),
                _DeviceRow(
                  icon: Icons.watch_rounded,
                  name: sourceDevice(Source.watch),
                  status: d == null ? 'Μέσω Samsung Health' : 'Μέσω Samsung Health · ${_when(d.readAt, today)}',
                ),
                const Hairline(vertical: 4),
                _DeviceRow(
                  icon: Icons.monitor_weight_outlined,
                  name: sourceDevice(Source.scale),
                  status: d?.latestBody == null
                      ? 'Μέσω Samsung Health'
                      : 'Μέσω Samsung Health · ${shortDayDate(d!.latestBody!.time)}',
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
                  'Μία συσκευή για κάθε μέτρηση, ποτέ ανάμειξη, ούτε όταν λείπει.'
                  '${plan.hasOura ? ' Ο ύπνος του ρολογιού φαίνεται μόνο στη Σύγκριση πηγών.' : ''}',
                  style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
                ),
                const SizedBox(height: 8),
                for (final (i, r) in sourceRows.indexed) ...[
                  if (i > 0) const Hairline(vertical: 2),
                  _TableRow(row: r, source: plan.sourceFor(r.metrics.first, today)),
                ],
              ],
            ),
          );

          final notUsed = plan.hasOura
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
                      Text(
                        'Κάθε αλλαγή ισχύει από το βράδυ της μέρας που την έκανες· η νύχτα πριν μένει όπως τη μέτρησε η '
                        'προηγούμενη πηγή. Οι παλιές νύχτες μένουν με την πηγή τους και οι Τάσεις δεν συγκρίνουν ποτέ '
                        'νύχτες από δύο συσκευές.',
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
          final unknown = store.planState == PlanState.unknown ? PlanRecoveryCard(store: store) : null;

          final compare = OuraOxygenAccessCard.orNull(store);

          final noSource = nightSrc == Source.none
              ? EmptyCard(
                  icon: Icons.bedtime_off_rounded,
                  color: c.sleep,
                  title: 'Ο ύπνος δεν έχει πηγή',
                  text: 'Το Oura αποσυνδέθηκε. Οι νύχτες μένουν κενές ώσπου να το συνδέσεις ξανά ή να διαλέξεις το ρολόι '
                      'στη σελίδα «Oura».',
                )
              : null;

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

  static String _when(DateTime t, DateTime today) => sameDay(t, today) ? hm(t) : '${relativeDay(t, today)} ${hm(t)}';

  static String _ouraStatus(HealthStore s, DateTime today) {
    if (s.planState == PlanState.unknown) return s.ouraHasTokens ? 'Συνδεδεμένο · διάλεξε πηγή ύπνου πάνω' : 'Διάλεξε πηγή ύπνου πάνω';
    if (!s.ouraConfigured && !s.ouraHasTokens) return 'Η σύνδεση ενεργοποιείται τη μέρα που θα έρθει';
    return switch (s.ouraStatus) {
      OuraStatus.off => s.ouraHasTokens ? 'Συνδεδεμένο' : 'Δεν έχει συνδεθεί',
      OuraStatus.starting => 'Συνδεδεμένο · ο ύπνος από το Oura από απόψε',
      OuraStatus.startingNow => 'Συνδεδεμένο · ${s.ouraFirstNightText.toLowerCase()}',
      OuraStatus.incomplete => 'Η σύνδεση δεν ολοκληρώθηκε· δοκίμασε ξανά',
      OuraStatus.disconnected => 'Αποσυνδέθηκε',
      OuraStatus.reconnect => 'Χρειάζεται νέα σύνδεση',
      OuraStatus.subscription => 'Η συνδρομή δεν είναι ενεργή',
      _ => s.ouraLastSync == null
          ? 'Συνδεδεμένο'
          : 'Συνδεδεμένο · τελευταίος συγχρονισμός ${_when(s.ouraLastSync!, today)}',
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
  const _TableRow({required this.row, required this.source});
  final SourceRow row;
  final Source source;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 2),
                Text(row.noteFor(source), style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SourceTag(source, label: samsungTotalMetrics.contains(row.metrics.first) ? 'Samsung Health' : null),
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
                    'δεν αποθηκεύεται τίποτα, για να μη μπερδευτούν συσκευές.'
                : 'Οι ρυθμίσεις πηγών χάλασαν ή χάθηκαν. Ώσπου να διαλέξεις, οι νύχτες μένουν κενές και δεν '
                    'αποθηκεύεται τίποτα, για να μη μπερδευτούν συσκευές.',
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
