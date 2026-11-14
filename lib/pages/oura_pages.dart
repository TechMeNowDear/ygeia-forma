import 'dart:async';

import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart' show K;
import '../oura/oura_api.dart';
import '../oura/oura_store.dart';
import '../oxygen_note.dart' show oxygenAvgLabel, oxygenMinLabel;
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import 'oxygen_widgets.dart';
import 'sources_page.dart';

/// Round 9 (R9-A11-2 = R9-U4-9, f4): η κάρτα «Μένουν στο κινητό σου» της σύνδεσης. Πριν η κάρτα υποσχόταν ότι δεν πάνε
/// ποτέ σε AI ή σε άλλους, ενώ η ίδια η εφαρμογή φτιάχνει αρχεία με δεδομένα του Oura που στέλνει ο χρήστης (PDF για τον γιατρό,
/// «Αναφορά για έλεγχο», π.χ. σε συζήτηση με AI). Ίδιο νόημα με τον ιστότοπο και την πολιτική απορρήτου (R7-A11-2).
/// Round 10 (R10-B8-2): «συνδρομή Oura.» με αδιάσπαστο κενό: στα 400 dp το «Oura.» έμενε μόνο του στην τελευταία γραμμή.
const ouraConnectPrivacyText = 'Τα δεδομένα έρχονται κατευθείαν από την Oura στο κινητό. Η εφαρμογή δεν τα δίνει ποτέ '
    'σε άλλους και δεν τα στέλνει σε AI· μπαίνουν μόνο σε αρχεία που φτιάχνεις και στέλνεις εσύ. Χρειάζεται ενεργή '
    'συνδρομή\u00A0Oura.';

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
  const _Bullet(this.text, {this.icon = Icons.check_rounded, this.color, this.sub});
  final String text;
  final String? sub;
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
          Expanded(
            child: sub == null
                ? Text(text, style: TextStyle(fontSize: 15, color: c.text, height: 1.35))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(text, style: TextStyle(fontSize: 15, color: c.text, height: 1.35)),
                    Text(sub!, style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.35)),
                  ]),
          ),
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

  /// 04:00–23:59: «Φορούσες το δαχτυλίδι την τελευταία νύχτα;». null = έκλεισε χωρίς απάντηση (τίποτα δεν ανοίγει).
  /// [unsourced] (round 1, U2b-13): η τελευταία νύχτα δεν έχει πηγή (μετά από αποσύνδεση): με «Όχι» μένει ΚΕΝΗ, όχι
  /// «όπως τη μέτρησε το ρολόι».
  Future<bool?> _askLastNight({bool unsourced = false}) => showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        routeSettings: const RouteSettings(name: 'Η τελευταία νύχτα'),
        builder: (context) {
          final c = Aigaio.of(context);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Φορούσες το δαχτυλίδι την τελευταία νύχτα;',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c.text)),
                  const SizedBox(height: 8),
                  Text(
                    unsourced
                        ? 'Αν ναι, η τελευταία νύχτα μετρά από το δαχτυλίδι. Αν όχι, η τελευταία νύχτα μένει κενή και το '
                            'δαχτυλίδι μετρά από απόψε.'
                        : 'Αν ναι, η τελευταία νύχτα μετρά από το δαχτυλίδι. Αν όχι, μένει όπως τη μέτρησε το ρολόι και '
                            'το δαχτυλίδι μετρά από απόψε.',
                    style: TextStyle(fontSize: 14.5, color: c.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('oura-first-night-no'),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Όχι, από απόψε'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const ValueKey('oura-first-night-yes'),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Ναι, μετρά από το δαχτυλίδι'),
                  ),
                ],
              ),
            ),
          );
        },
      );

  Future<void> _connect() async {
    // Η πρώτη νύχτα αποφασίζεται εδώ, πριν ανοίξει ο browser, από την ώρα που πατήθηκε το κουμπί.
    final now = widget.store.ouraClock();
    // Round 1 (S5-3 / U2b-13): σύνδεση ξανά μέσα σε εποχή Oura που τρέχει (π.χ. «Χρειάζεται νέα σύνδεση»): η τελευταία
    // νύχτα είναι ήδη του Oura, άρα καμία ερώτηση (ό,τι κι αν απαντούσες δεν άλλαζε τίποτα) και «από σήμερα».
    final src = widget.store.plan.nightSource(dayOf(now));
    var wore = false;
    if (src != Source.oura && firstNightChoice(now) == FirstNightChoice.ask) {
      final a = await _askLastNight(unsourced: src == Source.none);
      if (a == null || !mounted) return;
      wore = a;
    }
    setState(() {
      _opening = true;
      _error = null;
    });
    final e = await widget.store.beginOuraLogin(from: src == Source.oura ? dayOf(now) : firstOuraNight(now, woreRing: wore));
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
                'Ο ύπνος σου από το Oura',
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
              const _Bullet('Βαθμολογία ύπνου και ετοιμότητα'),
              // Έλεγχος 9/11 (UX3-05 / V-D-05): η εφαρμογή ΔΙΑΒΑΖΕΙ τον μέσο όρο οξυγόνου από το Oura (πριν: «όχι οξυγόνο»).
              const _Bullet(oxygenAvgLabel, sub: 'Η χαμηλότερη τιμή έρχεται από το ρολόι.'),
              _Bullet('Όχι email και προσωπικά στοιχεία, όχι βήματα', icon: Icons.block_rounded, color: c.textTertiary),
            ],
          ),
        );

        final clockNow = store.ouraClock();
        final firstNightLine = store.plan.nightSource(dayOf(clockNow)) == Source.oura
            ? 'Οι νύχτες του δαχτυλιδιού που έλειψαν έρχονται μόλις συνδεθείς.'
            : firstNightChoice(clockNow) == FirstNightChoice.today
                ? 'Η νύχτα που κοιμάσαι τώρα θα μετρά από το δαχτυλίδι.'
                : 'Πριν ανοίξει η σελίδα της Oura θα σε ρωτήσουμε αν φορούσες το δαχτυλίδι την τελευταία νύχτα.';
        final privacy = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Μένουν στο κινητό σου'),
              const SizedBox(height: 6),
              Text(
                ouraConnectPrivacyText,
                style: TextStyle(fontSize: 14.5, color: c.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 6),
              // Round 1 (U2b-13 / U2b-19): «όπως είναι» (όχι «από το ρολόι»: μετά από αποσύνδεση οι νύχτες είναι κενές)·
              // και η τελευταία πρόταση λέει αυτό που θα γίνει ΤΩΡΑ (πριν: «Μετά τις 04:00 θα σε ρωτήσουμε», όλη τη μέρα).
              Text(
                'Από την πρώτη νύχτα του δαχτυλιδιού ο ύπνος έρχεται μόνο από αυτό. Οι νύχτες πριν μένουν όπως είναι. '
                '$firstNightLine',
                style: TextStyle(fontSize: 14.5, color: c.textSecondary, height: 1.4),
              ),
            ],
          ),
        );

        // Round 1 (U2b-10): με άγνωστο σχέδιο πηγών η σύνδεση δεν μπορεί να ολοκληρωθεί (δεν αλλάζει η πηγή): το λέμε
        // και στέλνουμε στις Πηγές, αντί για «δοκίμασε ξανά σε λίγο» που δεν θα πετύχαινε ποτέ.
        final unknown = store.planUnknown;
        final status = <Widget>[
          if (unknown)
            EmptyCard(
              key: const ValueKey('oura-plan-first'),
              icon: Icons.device_unknown_rounded,
              color: c.bad,
              title: 'Πρώτα διάλεξε από πού έρχεται ο ύπνος',
              text: 'Οι ρυθμίσεις πηγών δεν διαβάστηκαν. Διάλεξε πηγή ύπνου στις Πηγές και μετά σύνδεσε το Oura.',
              buttonText: 'Άνοιξε τις Πηγές',
              onPressed: () => Navigator.of(context).push(SourcesPage.route(store, now: widget.now)),
            )
          else if (!configured)
            EmptyCard(
              icon: Icons.event_rounded,
              color: c.primary,
              title: 'Δεν είναι έτοιμο ακόμα',
              text: ouraErrorText(OuraErrorKind.notConfigured),
            )
          else if (error != null)
            EmptyCard(
              icon: Icons.error_outline_rounded,
              color: c.bad,
              title: 'Δεν συνδέθηκε',
              text: ouraLoginErrorText(error, code: _error == null ? store.ouraLoginCode : null),
            ),
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
                onPressed: !configured || unknown || _opening || store.ouraConnecting ? null : _connect,
                child: Text(store.ouraConnecting ? 'Συνδέω…' : 'Σύνδεση με Oura'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Όχι τώρα'),
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
    // Round 1 (U2b-11 / U2b-07): η συνέπεια που γράφει ο διάλογος είναι αυτή που θα γίνει. Αν το Oura δεν είχε αρχίσει
    // ακόμα (σύνδεση με αρχή απόψε) ή ο ύπνος είναι ήδη του ρολογιού, οι νύχτες ΔΕΝ μένουν κενές.
    final consequence = switch (store.sleepSourceAfterDisconnect) {
      Source.none => 'Από απόψε οι νύχτες μένουν κενές, και μαζί το οξυγόνο της νύχτας: ο ύπνος δεν περνά μόνος του στο '
          'ρολόι. Αν το θέλεις, το διαλέγεις μετά ρητά, σε αυτή τη σελίδα.',
      Source.watch => 'Ο ύπνος συνεχίζει να έρχεται από το ρολόι.',
      _ => 'Η πηγή του ύπνου δεν αλλάζει.',
    };
    final ok = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: 'Αποσύνδεση Oura'),
      builder: (context) => AlertDialog(
        title: const Text('Αποσύνδεση από το Oura;'),
        content: Text(
          'Σταματά η ανάγνωση από το Oura και η άδεια ανακαλείται. Ό,τι έχει ήδη έρθει μένει στο κινητό.\n\n'
          '$consequence',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Άκυρο')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Αποσύνδεση')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final before = store.plan;
    // Αναίρεση έχει νόημα μόνο αν είχε ήδη αρχίσει εποχή Oura (αλλιώς δεν άλλαξε τίποτα που να επιστρέφει).
    final undo = store.ouraEraStarted;
    final messenger = ScaffoldMessenger.of(context);
    final revoked = await store.disconnectOura();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      // Round8 (R8-U2-1, f1): με «Αναίρεση» το μήνυμα δεν θα έκλεινε ποτέ μόνο του (Flutter ≥ 3.38).
      persist: false,
      // Round 1 (S5-8): αν η Oura δεν απάντησε στην ανάκληση (π.χ. χωρίς δίκτυο), το λέμε: η άδεια μένει στον λογαριασμό.
      content: Text(revoked
          ? 'Αποσυνδέθηκε. Τα δεδομένα που είχαν έρθει μένουν.'
          : 'Αποσυνδέθηκε από το κινητό. Η Oura δεν απάντησε: αν θέλεις, αφαίρεσε την άδεια της εφαρμογής και από τον '
              'λογαριασμό σου στην Oura.'),
      // Αναίρεση: η πηγή του ύπνου ξαναγίνεται Oura· για να ξαναδιαβάζει χρειάζεται «Σύνδεση με Oura».
      action: undo ? SnackBarAction(label: 'Αναίρεση', onPressed: () => store.restorePlan(before)) : null,
    ));
  }

  /// Μόνο τη μέρα της σύνδεσης: η τελευταία νύχτα από το ρολόι, το δαχτυλίδι από απόψε.
  Future<void> _watchLastNight(BuildContext context) async {
    final asleep = store.ouraClock().hour < 4;
    final ok = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: 'Η τελευταία νύχτα από το ρολόι'),
      builder: (context) => AlertDialog(
        title: Text('${store.watchLastNightLabel};'),
        content: Text(
          asleep
              ? 'Η νύχτα που κοιμάσαι τώρα θα μετρά από το Galaxy Watch. Το δαχτυλίδι μετρά από το επόμενο βράδυ.'
              : 'Η τελευταία νύχτα θα φαίνεται όπως τη μέτρησε το Galaxy Watch. Το δαχτυλίδι μετρά από απόψε.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Άκυρο')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ναι, από το ρολόι')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final done = await store.watchLastNight();
    messenger.showSnackBar(SnackBar(
      content: Text(done
          ? (asleep ? 'Η νύχτα από το ρολόι. Το δαχτυλίδι από το επόμενο βράδυ.' : 'Η τελευταία νύχτα από το ρολόι. Το δαχτυλίδι από απόψε.')
          : 'Δεν αποθηκεύτηκε. Δοκίμασε ξανά.'),
    ));
  }

  Future<void> _watchAgain(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: 'Ύπνος από το ρολόι'),
      builder: (context) => AlertDialog(
        title: const Text('Ο ύπνος ξανά από το ρολόι;'),
        content: const Text(
          'Από απόψε ο ύπνος θα έρχεται από το Galaxy Watch. Οι νύχτες του Oura μένουν όπως είναι. '
          'Οι Τάσεις δεν θα συγκρίνουν νύχτες των δύο συσκευών μεταξύ τους.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Άκυρο')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ναι, από το ρολόι')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    // Round 1 (U2b-09): λέμε ότι έγινε (ή ότι δεν αποθηκεύτηκε)· πριν, καμία ένδειξη ως την επόμενη μέρα.
    final messenger = ScaffoldMessenger.of(context);
    final done = await store.sleepFromWatchAgain();
    messenger.showSnackBar(SnackBar(
      content: Text(done ? 'Από απόψε ο ύπνος έρχεται από το ρολόι.' : 'Δεν αποθηκεύτηκε. Δοκίμασε ξανά.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = Aigaio.of(context);
        final today = dayOf(now ?? DateTime.now());
        final tomorrow = DateTime(today.year, today.month, today.day + 1);
        final plan = store.plan;
        final status = store.ouraStatus;
        final connected = store.ouraHasTokens;
        final nightsCount = store.ouraNights.where((n) => n.main != null).length;
        final last = store.ouraLastSync;
        final ouraFrom = plan.ouraFrom;
        // Round 1 (U2b-10): άγνωστο σχέδιο πηγών: καμία ενέργεια εδώ δεν μπορεί να πετύχει πριν διαλέξεις στις Πηγές.
        final unknown = store.planUnknown;
        // Round 1 (U2b-09): διάλεξε ήδη «από απόψε το ρολόι».
        final watchTonight = store.watchSleepFromTonight;
        final noSourceToday = plan.nightSource(today) == Source.none;
        // Round 1 (U2b-01): η ανάγνωση γίνεται πράγματι μόνη της μόνο με ζωντανή σύνδεση.
        final live = connected && store.ouraActive && status != OuraStatus.reconnect;
        // Ο ύπνος δεν έχει πηγή σήμερα ή (τη μέρα της αποσύνδεσης) από απόψε: εδώ διαλέγεται ρητά το ρολόι.
        final unsourced =
            !unknown && !watchTonight && (noSourceToday || (!connected && plan.nightSource(tomorrow) == Source.none));
        final missingNights = store.ouraMissingNights;

        final (title, subtitle, color) = switch (status) {
          _ when unknown => (
              'Δεν διαβάστηκε από πού έρχεται ο ύπνος',
              'Πρώτα διάλεξε πηγή ύπνου στις Πηγές. Ώσπου να διαλέξεις, οι νύχτες μένουν κενές και τίποτα δεν αλλάζει από εδώ.',
              c.bad,
            ),
          OuraStatus.reconnect => (
              store.ouraError == OuraErrorKind.scopeMissing ? 'Λείπει άδεια στην Oura' : 'Χρειάζεται νέα σύνδεση',
              ouraErrorText(store.ouraError == OuraErrorKind.scopeMissing ? OuraErrorKind.scopeMissing : OuraErrorKind.reconnect),
              c.bad,
            ),
          // Round 1 (S5-6 / U2a-04): και τι να κάνεις (403 = συνδρομή Ή άδεια).
          OuraStatus.subscription => (
              'Η Oura δεν δίνει δεδομένα',
              '${ouraErrorText(OuraErrorKind.subscription)} Έλεγξε τη συνδρομή στην εφαρμογή Oura και πάτα «Ενημέρωση τώρα»· '
                  'αν λείπει η άδεια, πάτα «Σύνδεση ξανά».',
              c.bad,
            ),
          OuraStatus.disconnected when watchTonight => (
              'Αποσυνδέθηκε',
              'Από απόψε ο ύπνος έρχεται από το ρολόι, όπως διάλεξες.${noSourceToday ? ' Η χθεσινή νύχτα μένει κενή.' : ''}',
              c.textSecondary
            ),
          OuraStatus.disconnected => (
              'Αποσυνδέθηκε',
              '${noSourceToday ? 'Οι νύχτες μένουν κενές' : 'Από απόψε οι νύχτες μένουν κενές'} ώσπου να συνδέσεις ξανά ή να '
                  'διαλέξεις το ρολόι.',
              c.textSecondary
            ),
          OuraStatus.off => connected
              ? ('Συνδεδεμένο', 'Ο ύπνος έρχεται τώρα από το ρολόι, όπως διάλεξες.', c.good)
              : ('Δεν είναι συνδεδεμένο', 'Ο ύπνος έρχεται από το ρολόι.', c.textSecondary),
          OuraStatus.starting => (
              'Συνδεδεμένο',
              'Από απόψε ο ύπνος έρχεται μόνο από το Oura. Η χθεσινή νύχτα μένει όπως τη μέτρησε το ρολόι.',
              c.good,
            ),
          OuraStatus.startingNow => (
              'Συνδεδεμένο',
              '${store.ouraFirstNightText}. Θα φανεί όταν συγχρονίσει η εφαρμογή Oura.',
              c.good,
            ),
          OuraStatus.incomplete => ('Δεν συνδέθηκε', ouraErrorText(OuraErrorKind.incomplete), c.bad),
          OuraStatus.retry => (
              'Συνδεδεμένο',
              ouraErrorText(store.ouraError ?? OuraErrorKind.network),
              c.good,
            ),
          // Round 1 (U2b-12): όταν λείπει η χθεσινή νύχτα η σελίδα λέει το ίδιο με τη «Σήμερα» (πριν: «δεν χρειάζεται να
          // κάνεις τίποτα»).
          OuraStatus.waiting => (
              'Συνδεδεμένο',
              'Η χθεσινή νύχτα δεν έχει φτάσει ακόμα. Άνοιξε την εφαρμογή Oura για να συγχρονίσει και μετά πάτα «Ενημέρωση τώρα».',
              c.sleep,
            ),
          OuraStatus.missing => (
              'Συνδεδεμένο',
              missingNights >= 2
                  ? 'Λείπουν ${countText(missingNights, 'νύχτα', 'νύχτες')}. Άνοιξε την εφαρμογή Oura με το δαχτυλίδι κοντά στο '
                      'κινητό και μετά πάτα «Ενημέρωση τώρα».'
                  : 'Χθες βράδυ χωρίς ύπνο από το δαχτυλίδι. Αν το φορούσες, άνοιξε την εφαρμογή Oura για να συγχρονίσει και '
                      'μετά πάτα «Ενημέρωση τώρα».',
              c.move,
            ),
          _ => (
              'Συνδεδεμένο',
              '${ouraFrom == null ? '' : 'Από τη νύχτα προς ${shortDayDate(ouraFrom)} · '}δεν χρειάζεται να κάνεις τίποτα',
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

        final openConnect = store.ouraConfigured ? () => Navigator.of(context).push(OuraConnectPage.route(store, now: now)) : null;
        final actions = <Widget>[
          if (unknown)
            FilledButton(
              key: const ValueKey('oura-open-sources'),
              onPressed: () => Navigator.of(context).push(SourcesPage.route(store, now: now)),
              child: const Text('Άνοιξε τις Πηγές'),
            )
          else ...[
            if (store.canWatchLastNight)
              OutlinedButton(
                key: const ValueKey('oura-watch-last-night'),
                onPressed: () => _watchLastNight(context),
                child: Text(store.watchLastNightLabel),
              ),
            if (status == OuraStatus.reconnect || status == OuraStatus.disconnected || (!connected && status != OuraStatus.off))
              FilledButton(
                onPressed: openConnect,
                child: const Text('Σύνδεση ξανά'),
              )
            // Round 1 (U2b-11): μετά από αποσύνδεση πριν αρχίσει το Oura η σελίδα έμενε χωρίς κανένα κουμπί.
            else if (!connected)
              FilledButton(
                key: const ValueKey('oura-connect-open'),
                onPressed: openConnect,
                child: const Text('Σύνδεση με Oura'),
              )
            else if (store.ouraActive)
              _SyncNowButton(store: store),
            // Round 1 (S5-6): το 403 μπορεί να είναι άδεια που λείπει: δρόμος για νέα έγκριση αδειών χωρίς «Αποσύνδεση».
            if (status == OuraStatus.subscription)
              OutlinedButton(
                key: const ValueKey('oura-reconnect'),
                onPressed: openConnect,
                child: const Text('Σύνδεση ξανά'),
              ),
            // Round 1 (U2b-01): μόνο με ζωντανή σύνδεση (πριν φαινόταν και μετά την αποσύνδεση ή με «νέα σύνδεση»).
            if (live)
              Text(
                'Η ενημέρωση γίνεται μόνη της όταν ανοίγεις την εφαρμογή. Αν λείπει η χθεσινή νύχτα, άνοιξε πρώτα '
                'την εφαρμογή Oura.',
                style: TextStyle(fontSize: 13.5, color: c.textSecondary, height: 1.4),
              ),
          ],
        ];

        final compare = OuraOxygenAccessCard.orNull(store);

        final what = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Από πού έρχεται τι'),
              const SizedBox(height: 4),
              // Έλεγχος 9/11 (UX3-05): πηγή, όχι «Ναι» δίπλα σε «Όχι · από το ρολόι»· ίδιες ετικέτες με τις Πηγές.
              // Round 1 (U2b-08): η πραγματική πηγή σήμερα, με τις λέξεις των Πηγών («Oura», «Ρολόι», «Καμία»)· πριν
              // «Oura · όχι τώρα» και όταν ο ύπνος ήταν του ρολογιού ή χωρίς πηγή.
              for (final r in sourceRows.where((r) => r.group == SourceGroup.night))
                InfoRow(r.title, store.ouraStartsTonight ? 'Oura από απόψε' : sourceName(plan.sourceFor(r.metrics.first, today))),
              // Round 1 (U2b-07): χωρίς πηγή ύπνου το ρολόι δεν δίνει οξυγόνο νύχτας (το μετρά μόνο μέσα στις ώρες ύπνου).
              InfoRow(oxygenMinLabel, sourceName(noSourceToday ? Source.none : Source.watch)),
              // Round 1 (U2b-06): τα βήματα είναι το σύνολο της Samsung Health (ρολόι και κινητό), όπως στις Πηγές.
              InfoRow('Βήματα', metricSourceName(K.steps, Source.watch)),
            ],
          ),
        );

        // Round 1 (U2b-01): τη μέρα της αποσύνδεσης όχι ξανά «Αποσύνδεση»· χωρίς tokens μένει μόνο όσο τρέχει εποχή Oura
        // (ο δρόμος για να σταματήσει το Oura όταν δεν γίνεται νέα σύνδεση).
        final canDisconnect = connected || (store.ouraActive && status != OuraStatus.disconnected);
        final danger = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (canDisconnect) ...[
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
              if (unsourced) ...[
                if (canDisconnect) const Hairline(vertical: 12),
                OutlinedButton(
                  key: const ValueKey('oura-watch-again'),
                  onPressed: () => _watchAgain(context),
                  child: const Text('Ο ύπνος ξανά από το ρολόι'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Μόνο αν το διαλέξεις: από απόψε ο ύπνος έρχεται από το Galaxy Watch.',
                  style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4),
                ),
              ],
            ],
          ),
        );

        return _OuraScaffold(
          title: 'Oura',
          left: [head, ...actions, if (compare != null) compare],
          // Round 1 (U2b-11): χωρίς περιεχόμενο δεν μένει άδεια κάρτα.
          right: [what, if (canDisconnect || unsourced) danger],
        );
      },
    );
  }
}

/// «Ενημέρωση τώρα»: διαβάζει πάντα, με φρένο λίγων δευτερολέπτων για διπλά πατήματα ([ouraUserGap], round 1, S5-10·
/// πριν: ένα λεπτό). Ξαναενεργοποιείται μόνο του με ΕΝΑ χρονόμετρο μίας χρήσης όσο φαίνεται η σελίδα (κανένα
/// επαναλαμβανόμενο).
class _SyncNowButton extends StatefulWidget {
  const _SyncNowButton({required this.store});
  final HealthStore store;

  @override
  State<_SyncNowButton> createState() => _SyncNowButtonState();
}

class _SyncNowButtonState extends State<_SyncNowButton> {
  Timer? _timer;

  void _arm() {
    _timer?.cancel();
    _timer = null;
    final left = widget.store.ouraSyncNowIn;
    if (left == Duration.zero) return;
    _timer = Timer(left + const Duration(milliseconds: 200), () {
      _timer = null;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final can = !store.ouraSyncing && store.ouraCanSyncNow;
    if (!can && !store.ouraSyncing) {
      if (_timer == null) _arm();
    } else {
      _timer?.cancel();
      _timer = null;
    }
    return FilledButton.icon(
      key: const ValueKey('oura-sync-now'),
      // Round 1 (S5-10): ρητή ανάγνωση μέσα από το refresh(): διαβάζει το Oura τώρα και ξαναϋπολογίζει τις τιμές του
      // ρολογιού (οξυγόνο νύχτας, παλμοί μέρας) με τη νύχτα που ήρθε.
      onPressed: can ? () async {
        await store.refresh();
        if (mounted) setState(_arm);
      } : null,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Ενημέρωση τώρα'),
    );
  }
}
