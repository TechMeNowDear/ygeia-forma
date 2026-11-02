import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../oura/oura_api.dart';
import '../oura/oura_store.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import 'compare_page.dart';

/// Κοινός σκελετός για τις σελίδες του Oura: μία στήλη στο κινητό, δύο σε ανοιχτό Fold.
class _OuraScaffold extends StatelessWidget {
  const _OuraScaffold({required this.title, required this.left, this.right = const [], this.bottom});
  final String title;
  final List<Widget> left;
  final List<Widget> right;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: c.background, surfaceTintColor: Colors.transparent),
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 760 && right.isNotEmpty;
          Widget col(List<Widget> items) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, w) in items.indexed) ...[if (i > 0) const SizedBox(height: 12), w],
                ],
              );
          return ListView(
            padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 8, wide ? 28 : 16, 24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 1080 : 640),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [Expanded(child: col(left)), const SizedBox(width: 16), Expanded(child: col(right))],
                        )
                      : col([...left, ...right]),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: bottom),
              ),
            ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {this.icon = Icons.check_rounded, this.color});
  final String text;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: color ?? c.good)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 15, color: c.text, height: 1.35))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Σύνδεση Oura (μία φορά)
// ---------------------------------------------------------------------------

class OuraConnectPage extends StatefulWidget {
  const OuraConnectPage({super.key, required this.store, this.now});
  final HealthStore store;
  final DateTime? now;

  static const routeName = 'Σύνδεση Oura';

  static Route<void> route(HealthStore store, {DateTime? now}) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: routeName),
        builder: (_) => OuraConnectPage(store: store, now: now),
      );

  @override
  State<OuraConnectPage> createState() => _OuraConnectPageState();
}

class _OuraConnectPageState extends State<OuraConnectPage> {
  OuraErrorKind? _error;
  bool _opening = false;

  Future<void> _connect() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    final e = await widget.store.beginOuraLogin();
    if (!mounted) return;
    setState(() {
      _opening = false;
      _error = e;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = Aigaio.of(context);
        // Μόλις συνδεθεί, η σελίδα γίνεται η σελίδα διαχείρισης.
        if (store.ouraJustConnected && store.ouraHasTokens) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !store.ouraJustConnected) return;
            store.ouraJustConnected = false;
            Navigator.of(context).pushReplacement(OuraManagePage.route(store, now: widget.now));
          });
        }
        final error = _error ?? store.ouraLoginError;
        final configured = store.ouraConfigured;

        final hero = Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppCard.radius),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.nightTop, c.nightBottom]),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ο ύπνος σου από το Oura Ring 5',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4),
              ),
              const SizedBox(height: 8),
              Text(
                'Συνδέεις μία φορά. Μετά η εφαρμογή παίρνει μόνη της κάθε νύχτα, χωρίς να ξανακάνεις τίποτα.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 15, height: 1.4),
              ),
            ],
          ),
        );

        Widget step(int n, String text) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.tint(c.primary), shape: BoxShape.circle),
                    child: Text('$n', style: TextStyle(color: c.primary, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(text, style: TextStyle(fontSize: 15, color: c.text, height: 1.35)),
                    ),
                  ),
                ],
              ),
            );

        final steps = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Τι θα γίνει'),
              const SizedBox(height: 6),
              step(1, 'Ανοίγει η σελίδα της Oura.'),
              step(2, 'Βάζεις τα στοιχεία του λογαριασμού σου στην Oura. Η εφαρμογή μας δεν τα βλέπει ποτέ.'),
              step(3, 'Πατάς «Αποδοχή» και γυρνάς αυτόματα εδώ.'),
            ],
          ),
        );

        final reads = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Τι θα διαβάζει'),
              const SizedBox(height: 6),
              const _Bullet('Ύπνος, ώρες και φάσεις'),
              const _Bullet('Παλμοί, HRV και αναπνοές στον ύπνο'),
              const _Bullet('Θερμοκρασία δέρματος στον ύπνο'),
              const _Bullet('Βαθμολογία ύπνου και ετοιμότητα της Oura'),
              _Bullet('Όχι email και προσωπικά στοιχεία, όχι βήματα, όχι οξυγόνο', icon: Icons.block_rounded, color: c.textTertiary),
            ],
          ),
        );

        final privacy = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Μένουν στο κινητό σου'),
              const SizedBox(height: 6),
              Text(
                'Τα δεδομένα έρχονται κατευθείαν από την Oura στο κινητό. Δεν δίνονται ποτέ σε AI ή σε άλλους. '
                'Χρειάζεται ενεργή συνδρομή Oura.',
                style: TextStyle(fontSize: 14.5, color: c.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 6),
              Text(
                'Από τη μέρα της σύνδεσης ο ύπνος έρχεται μόνο από το δαχτυλίδι. Οι παλιές νύχτες μένουν όπως είναι, '
                'από το ρολόι.',
                style: TextStyle(fontSize: 14.5, color: c.textSecondary, height: 1.4),
              ),
            ],
          ),
        );

        final status = <Widget>[
          if (!configured)
            EmptyCard(
              icon: Icons.event_rounded,
              color: c.primary,
              title: 'Δεν είναι έτοιμο ακόμα',
              text: ouraErrorText(OuraErrorKind.notConfigured),
            )
          else if (error != null)
            EmptyCard(icon: Icons.error_outline_rounded, color: c.bad, title: 'Δεν συνδέθηκε', text: ouraErrorText(error)),
        ];

        return _OuraScaffold(
          title: 'Σύνδεση Oura',
          left: [hero, ...status, steps],
          right: [reads, privacy],
          bottom: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                key: const ValueKey('oura-connect'),
                onPressed: !configured || _opening || store.ouraConnecting ? null : _connect,
                child: Text(store.ouraConnecting ? 'Συνδέω…' : 'Σύνδεση με Oura'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Αργότερα · Ρυθμίσεις › Πηγές'),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Oura · διαχείριση
// ---------------------------------------------------------------------------

class OuraManagePage extends StatelessWidget {
  const OuraManagePage({super.key, required this.store, this.now});
  final HealthStore store;
  final DateTime? now;

  static const routeName = 'Oura';

  static Route<void> route(HealthStore store, {DateTime? now}) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: routeName),
        builder: (_) => OuraManagePage(store: store, now: now),
      );

  Future<void> _disconnect(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: 'Αποσύνδεση Oura'),
      builder: (context) => AlertDialog(
        title: const Text('Αποσύνδεση από το Oura;'),
        content: const Text(
          'Σταματά η ανάγνωση από το Oura και η άδεια ανακαλείται. Ό,τι έχει ήδη έρθει μένει στο κινητό.\n\n'
          'Από σήμερα οι νύχτες μένουν κενές: ο ύπνος δεν περνά μόνος του στο ρολόι. Αν το θέλεις, το διαλέγεις '
          'μετά ρητά, σε αυτή τη σελίδα.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Άκυρο')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Αποσύνδεση')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final before = store.plan;
    final messenger = ScaffoldMessenger.of(context);
    await store.disconnectOura();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: const Text('Αποσυνδέθηκε. Τα δεδομένα που είχαν έρθει μένουν.'),
      // Αναίρεση: η πηγή του ύπνου ξαναγίνεται Oura· για να ξαναδιαβάζει χρειάζεται «Σύνδεση με Oura».
      action: SnackBarAction(label: 'Αναίρεση', onPressed: () => store.restorePlan(before)),
    ));
  }

  Future<void> _watchAgain(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: 'Ύπνος από το ρολόι'),
      builder: (context) => AlertDialog(
        title: const Text('Ο ύπνος ξανά από το ρολόι;'),
        content: const Text(
          'Από σήμερα ο ύπνος θα έρχεται από το Galaxy Watch. Οι νύχτες του Oura μένουν όπως είναι. '
          'Οι Τάσεις δεν θα συγκρίνουν νύχτες των δύο συσκευών μεταξύ τους.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Άκυρο')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ναι, από το ρολόι')),
        ],
      ),
    );
    if (ok == true) await store.sleepFromWatchAgain();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = Aigaio.of(context);
        final today = dayOf(now ?? DateTime.now());
        final plan = store.plan;
        final status = store.ouraStatus;
        final connected = store.ouraHasTokens;
        final nightsCount = store.ouraNights.where((n) => n.main != null).length;
        final last = store.ouraLastSync;
        final ouraFrom = plan.ouraFrom;

        final (title, subtitle, color) = switch (status) {
          OuraStatus.reconnect => ('Χρειάζεται νέα σύνδεση', ouraErrorText(OuraErrorKind.reconnect), c.bad),
          OuraStatus.subscription => ('Η Oura δεν δίνει δεδομένα', ouraErrorText(OuraErrorKind.subscription), c.bad),
          OuraStatus.disconnected => (
              'Αποσυνδέθηκε',
              'Οι νύχτες μένουν κενές ώσπου να συνδέσεις ξανά ή να διαλέξεις το ρολόι.',
              c.textSecondary
            ),
          OuraStatus.off => connected
              ? ('Συνδεδεμένο', 'Ο ύπνος έρχεται τώρα από το ρολόι, όπως διάλεξες.', c.good)
              : ('Δεν είναι συνδεδεμένο', 'Ο ύπνος έρχεται από το ρολόι.', c.textSecondary),
          OuraStatus.retry => (
              'Συνδεδεμένο',
              ouraErrorText(store.ouraError ?? OuraErrorKind.network),
              c.good,
            ),
          _ => (
              'Συνδεδεμένο',
              '${ouraFrom == null ? '' : 'Από ${shortDayDate(ouraFrom)} · '}δεν χρειάζεται να κάνεις τίποτα',
              c.good,
            ),
        };

        final head = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconBadge(Icons.radio_button_unchecked_rounded, c.sleep, size: 44),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sourceDevice(Source.oura), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.text)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.text)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(subtitle, style: TextStyle(fontSize: 14, color: c.textSecondary, height: 1.4)),
              const Hairline(vertical: 12),
              InfoRow('Τελευταία ενημέρωση', last == null ? '—' : '${relativeDay(last, today)} ${hm(last)}'),
              InfoRow('Νύχτες στο κινητό', '$nightsCount'),
              if (store.ouraSyncing) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            ],
          ),
        );

        final actions = <Widget>[
          if (status == OuraStatus.reconnect || status == OuraStatus.disconnected || (!connected && status != OuraStatus.off))
            FilledButton(
              onPressed: store.ouraConfigured ? () => Navigator.of(context).push(OuraConnectPage.route(store, now: now)) : null,
              child: const Text('Σύνδεση ξανά'),
            )
          else if (connected && store.ouraActive)
            FilledButton.icon(
              key: const ValueKey('oura-sync-now'),
              onPressed: store.ouraSyncing ? null : store.syncOuraNow,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Ενημέρωση τώρα'),
            ),
          if (store.ouraActive)
            Text(
              'Η ενημέρωση γίνεται μόνη της όταν ανοίγεις την εφαρμογή. Αν λείπει η χθεσινή νύχτα, άνοιξε πρώτα '
              'την εφαρμογή Oura.',
              style: TextStyle(fontSize: 13.5, color: c.textSecondary, height: 1.4),
            ),
        ];

        final compare = plan.compareActive(today)
            ? AppCard(
                onTap: () => Navigator.of(context).push(ComparePage.route(store, now: now)),
                child: Row(
                  children: [
                    IconBadge(Icons.compare_arrows_rounded, c.sleep, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Σύγκριση με το ρολόι', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text)),
                          Text(
                            'Ανοιχτή ως ${shortDayDate(plan.compareUntil!)}, μόνο για έλεγχο',
                            style: TextStyle(fontSize: 13, color: c.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.textTertiary),
                  ],
                ),
              )
            : null;

        final what = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Τι παίρνουμε από το Oura'),
              const SizedBox(height: 4),
              for (final r in sourceRows.where((r) => r.group == SourceGroup.night))
                InfoRow(r.title, plan.nightSource(today) == Source.oura ? 'Ναι' : 'Όχι τώρα'),
              const InfoRow('Βήματα δαχτυλιδιού', 'Όχι · από το ρολόι'),
              const InfoRow('Οξυγόνο δαχτυλιδιού', 'Όχι · από το ρολόι'),
            ],
          ),
        );

        final danger = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (connected || store.ouraActive) ...[
                OutlinedButton(
                  key: const ValueKey('oura-disconnect'),
                  style: OutlinedButton.styleFrom(foregroundColor: c.bad),
                  onPressed: () => _disconnect(context),
                  child: const Text('Αποσύνδεση'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Σταματά η ανάγνωση από το Oura. Ό,τι έχει ήδη έρθει μένει στο κινητό. Γίνεται αναίρεση με νέα σύνδεση.',
                  style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4),
                ),
              ],
              if (plan.nightSource(today) == Source.none) ...[
                if (connected || store.ouraActive) const Hairline(vertical: 12),
                OutlinedButton(
                  key: const ValueKey('oura-watch-again'),
                  onPressed: () => _watchAgain(context),
                  child: const Text('Ο ύπνος ξανά από το ρολόι'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Μόνο αν το διαλέξεις: από σήμερα ο ύπνος έρχεται από το Galaxy Watch.',
                  style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4),
                ),
              ],
            ],
          ),
        );

        return _OuraScaffold(
          title: 'Oura',
          left: [head, ...actions, if (compare != null) compare],
          right: [what, danger],
        );
      },
    );
  }
}
