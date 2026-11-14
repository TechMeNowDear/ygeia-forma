import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../oura/config.dart';
import '../oura/oura_api.dart';
import '../oura/oura_store.dart';
import '../oura/oura_view.dart';
import '../plan_file.dart';
import '../shown.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import 'oura_pages.dart';
import 'source_widgets.dart';
import 'today.dart' show sleepNightLabel;

/// Κάρτες κατάστασης στην κορυφή της Σήμερα, μόνο όταν ισχύουν (States mockup). Φεύγουν μόνες τους.
class OuraStatusCard extends StatelessWidget {
  const OuraStatusCard({super.key, required this.store, required this.now});
  final HealthStore store;
  final DateTime now;

  /// Αν πρέπει να φανεί κάρτα.
  static bool shows(HealthStore s) => switch (s.ouraStatus) {
        OuraStatus.waiting || OuraStatus.missing || OuraStatus.reconnect || OuraStatus.subscription => true,
        OuraStatus.disconnected || OuraStatus.starting || OuraStatus.startingNow || OuraStatus.incomplete => true,
        OuraStatus.retry => retryShows(s),
        _ => false,
      };

  /// Round 1 (S5-7 / U2a-04): η ανάγνωση αποτυγχάνει (δίκτυο, 429, διακομιστής, μεσάζων). Κάρτα μόνο όταν αυτό
  /// αφορά ό,τι βλέπει ο χρήστης: λείπει η χθεσινή νύχτα (από τις 04:00), ή η τελευταία επιτυχημένη ανάγνωση είναι
  /// παλιότερη από 24 ώρες (ή δεν έγινε ποτέ). Ένα στιγμιαίο σφάλμα με όλα στη θέση τους δεν δείχνει κάρτα.
  static bool retryShows(HealthStore s) {
    final now = s.ouraClock();
    final synced = s.ouraLastSync;
    final stale = synced == null || now.difference(synced) > const Duration(hours: 24);
    return stale || _nightDueAndMissing(s, now);
  }

  static bool _nightDueAndMissing(HealthStore s, DateTime now) =>
      now.hour >= ouraNightDueHour && s.ouraNightFor(dayOf(now))?.main == null;

  /// Round 7 (R7-U1-13): η κάρτα γράφει ήδη τις ώρες του υπνάκου της νύχτας («Χθες βράδυ μόνο υπνάκος …», ίδιοι
  /// όροι με το `switch` του [build]).
  static bool showsNapTimes(HealthStore s, DateTime now) =>
      s.ouraStatus == OuraStatus.missing &&
      s.ouraMissingNights < 2 &&
      napTimes(s.ouraNightFor(dayOf(now)), nightOnly: true).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final s = store.ouraStatus;
    final missing = store.ouraMissingNights;
    final last = store.lastOuraNight;
    // Σφάλμα με παλιά δεδομένα στην οθόνη: λέμε ως πότε είναι (έλεγχος UX U5· ποτέ «χθες βράδυ» για παλιά νύχτα).
    final synced = store.ouraLastSync;
    final syncedText = synced == null ? '' : ' Ό,τι βλέπεις ήρθε ως τον τελευταίο συγχρονισμό, ${shortDayDate(synced)} ${hm(synced)}.';
    final VoidCallback openManage = () {
      Navigator.of(context).push(OuraManagePage.route(store, now: now));
    };
    final VoidCallback openConnect = () {
      Navigator.of(context)
          .push(store.ouraConfigured ? OuraConnectPage.route(store, now: now) : OuraManagePage.route(store, now: now));
    };
    // Round 1 (S5-10): το κουμπί της κάρτας διαβάζει ΤΩΡΑ (ρητή ενέργεια: χωρίς το όριο των 30 λεπτών), μαζί με τη
    // Samsung, ώστε και οι τιμές του ρολογιού να υπολογιστούν με τη νύχτα που ήρθε.
    final VoidCallback readNow = () {
      store.refresh();
    };
    const readNowLabel = 'Ενημέρωση τώρα';
    // Round 1 (U2a-03): χωρίς νύχτα από το δαχτυλίδι το οξυγόνο της νύχτας ΔΕΝ φαίνεται (το ρολόι το μετρά μόνο μέσα
    // στις ώρες ύπνου του δαχτυλιδιού)· πριν, η κάρτα έγραφε «το οξυγόνο από το ρολόι φαίνεται κανονικά».
    const emptyNight = ' νύχτα μένει κενή στον Ύπνο και στις Τάσεις, και το οξυγόνο της νύχτας μένει κενό, γιατί χωρίς '
        'νύχτα από το δαχτυλίδι δεν ξέρουμε πότε κοιμήθηκες.';
    // Round 1 (U2a-04): και η μία νύχτα που λείπει λέει τι να κάνεις (συνήθως απλώς δεν συγχρόνισε η εφαρμογή Oura).
    const ifWorn = ' Αν το φορούσες, άνοιξε την εφαρμογή Oura για να συγχρονίσει και μετά γύρνα εδώ.';
    final nap = napTimes(store.ouraNightFor(dayOf(now)), nightOnly: true);
    final (title, text, color, button, action) = switch (s) {
      OuraStatus.waiting => (
          'Περιμένει το Oura',
          'Η χθεσινή νύχτα δεν έχει φτάσει ακόμα. Άνοιξε την εφαρμογή Oura για να συγχρονίσει, και μετά γύρνα εδώ.',
          c.sleep,
          readNowLabel,
          readNow,
        ),
      OuraStatus.missing when missing >= 2 => (
          last == null
              ? 'Το Oura δεν έχει συγχρονιστεί ακόμα'
              : 'Το Oura δεν έχει συγχρονιστεί από ${sinceDayText(last.day, now)}',
          'Λείπουν ${countText(missing, 'νύχτα', 'νύχτες')}. Άνοιξε την εφαρμογή Oura με το δαχτυλίδι κοντά στο κινητό· '
              'οι νύχτες έρχονται μόνες τους μετά.',
          c.move,
          readNowLabel,
          readNow,
        ),
      OuraStatus.missing when nap.isNotEmpty => (
          'Χθες βράδυ μόνο υπνάκος από το δαχτυλίδι',
          'Υπνάκος $nap. Δεν μετρά ως νύχτα: η$emptyNight$ifWorn',
          c.textSecondary,
          readNowLabel,
          readNow,
        ),
      OuraStatus.missing => (
          'Χθες βράδυ χωρίς ύπνο από το δαχτυλίδι',
          'Η$emptyNight$ifWorn',
          c.textSecondary,
          readNowLabel,
          readNow,
        ),
      OuraStatus.starting => (
          'Από απόψε ο ύπνος από το Oura',
          'Το Oura συνδέθηκε. Η χθεσινή νύχτα μένει όπως τη μέτρησε το ρολόι· από την επόμενη νύχτα ο ύπνος έρχεται '
              'μόνο από το δαχτυλίδι. Φόρεσέ το απόψε.',
          c.sleep,
          null,
          null,
        ),
      // Round 1 (U2a-20): το κείμενο λέει τι κάνει το κουμπί (πριν: «Άνοιξε την εφαρμογή Oura» και κουμπί «Ρυθμίσεις»).
      OuraStatus.startingNow when store.canWatchLastNight && now.hour >= ouraNightDueHour => (
          store.ouraFirstNightText,
          'Το Oura συνδέθηκε. Άνοιξε την εφαρμογή Oura για να συγχρονίσει, και μετά γύρνα εδώ. Ο ύπνος έρχεται μόνο '
              'από το δαχτυλίδι. Δεν το φορούσες; Στις «Ρυθμίσεις Oura» διάλεξε «${store.watchLastNightLabel}».',
          c.sleep,
          'Ρυθμίσεις Oura',
          openManage,
        ),
      OuraStatus.startingNow => (
          store.ouraFirstNightText,
          'Το Oura συνδέθηκε. ${now.hour < ouraNightDueHour ? 'Όταν ξυπνήσεις, άνοιξε' : 'Άνοιξε'} την εφαρμογή Oura για να '
              'συγχρονίσει, και μετά γύρνα εδώ. Ο ύπνος έρχεται μόνο από το δαχτυλίδι.',
          c.sleep,
          null,
          null,
        ),
      OuraStatus.incomplete => (
          'Η σύνδεση δεν ολοκληρώθηκε',
          'Η σύνδεση με το Oura έμεινε μισή και δεν άλλαξε τίποτα. Δοκίμασε ξανά.',
          c.textSecondary,
          'Σύνδεση με Oura',
          openConnect,
        ),
      OuraStatus.reconnect when store.ouraError == OuraErrorKind.scopeMissing => (
          'Λείπει άδεια στην Oura',
          'Η Oura δεν δίνει τον ύπνο με την άδεια που δόθηκε. Σύνδεσε ξανά και άφησε επιλεγμένη την άδεια για τον ύπνο.',
          c.bad,
          'Σύνδεση ξανά',
          openConnect,
        ),
      OuraStatus.reconnect => (
          'Χρειάζεται νέα σύνδεση με το Oura',
          'Γίνεται μετά από αλλαγή κινητού ή αν αφαιρέσεις την άδεια στην Oura. Δεν χάνεται τίποτα· οι νύχτες που '
              'έλειψαν έρχονται μετά.$syncedText',
          c.bad,
          'Σύνδεση ξανά',
          openConnect,
        ),
      // Round 1 (U2a-04 / S5-6): το 403 είναι «συνδρομή Ή άδεια»· η κάρτα λέει τι να κάνεις και έχει κουμπί (πριν: κανένα).
      OuraStatus.subscription => (
          'Η Oura δεν δίνει νέα δεδομένα',
          'Η συνδρομή Oura δεν είναι ενεργή ή λείπει η άδεια για τον ύπνο. Έλεγξε τη συνδρομή στην εφαρμογή Oura. Μετά, στις '
              '«Ρυθμίσεις Oura», πάτα «Ενημέρωση τώρα» ή, αν λείπει η άδεια, «Σύνδεση ξανά».$syncedText',
          c.bad,
          'Ρυθμίσεις Oura',
          openManage,
        ),
      // Round 1 (U2b-09): μετά το «Ο ύπνος ξανά από το ρολόι» η κάρτα το λέει (πριν: ζητούσε ξανά την ίδια επιλογή).
      OuraStatus.disconnected when store.watchSleepFromTonight => (
          'Από απόψε ο ύπνος από το ρολόι',
          'Το Oura αποσυνδέθηκε και διάλεξες το ρολόι: από απόψε ο ύπνος έρχεται από το Galaxy Watch.'
              '${store.sleepUnsourced ? ' Η χθεσινή νύχτα μένει κενή.' : ''}',
          c.textSecondary,
          null,
          null,
        ),
      OuraStatus.disconnected => (
          'Ο ύπνος δεν έχει πηγή',
          'Το Oura αποσυνδέθηκε. ${store.sleepUnsourced ? 'Οι νύχτες μένουν κενές' : 'Από απόψε οι νύχτες μένουν κενές'} '
              'ώσπου να το συνδέσεις ξανά ή να διαλέξεις το ρολόι.',
          c.textSecondary,
          'Ρυθμίσεις Oura',
          openManage,
        ),
      // Round 1 (S5-7 / U2a-04): η ανάγνωση αποτυγχάνει: ο λόγος και ένα κουμπί (πριν: καμία κάρτα).
      OuraStatus.retry => (
          _nightDueAndMissing(store, now) ? 'Δεν διαβάστηκε ακόμα από την Oura' : 'Η ανάγνωση από την Oura δεν γίνεται',
          '${ouraErrorText(store.ouraError ?? OuraErrorKind.network)}$syncedText',
          c.move,
          readNowLabel,
          readNow,
        ),
      _ => ('', '', c.textSecondary, null, null),
    };
    return EmptyCard(
      key: ValueKey('oura-status-${s.name}'),
      icon: s == OuraStatus.reconnect || s == OuraStatus.subscription ? Icons.link_off_rounded : Icons.bedtime_rounded,
      color: color,
      title: title,
      text: text,
      buttonText: button,
      onPressed: action,
      // Round 1 (f9 · U2a-21): χωρίς νέα σύνδεση δεν έρχεται τίποτα· η ενέργεια αυτή είναι γεμάτο κουμπί.
      primary: s == OuraStatus.reconnect,
    );
  }
}

/// Round 1 (S11-9 / U2a-13): «από χθες», «από την Τρίτη», «από το Σάββατο»· για 7 μέρες και πάνω η ημερομηνία
/// («από Τετ 4/11»): η σκέτη μέρα της εβδομάδας θα διαβαζόταν ως «από σήμερα» ή «από την περασμένη εβδομάδα».
String sinceDayText(DateTime d, DateTime now) {
  final diff = daysBetween(d, now);
  if (diff == 0) return 'σήμερα';
  if (diff == 1) return 'χθες';
  if (diff < 0 || diff >= 7) return shortDayDate(d);
  final name = weekdayFull(d);
  return switch (d.weekday) {
    DateTime.monday => 'τη $name',
    DateTime.saturday => 'το $name',
    _ => 'την $name',
  };
}

/// Το σχέδιο πηγών δεν διαβάστηκε με σιγουριά (π.χ. χαλασμένο αρχείο): οι νύχτες μένουν κενές, τίποτα δεν
/// γράφεται, και ο χρήστης διαλέγει στις Πηγές. Ποτέ σιωπηλά πίσω στο ρολόι.
class PlanUnknownCard extends StatelessWidget {
  const PlanUnknownCard({super.key, required this.onOpen});
  final VoidCallback onOpen;

  static bool shows(HealthStore s) => s.planState == PlanState.unknown;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return EmptyCard(
      key: const ValueKey('plan-unknown'),
      icon: Icons.device_unknown_rounded,
      color: c.bad,
      title: 'Δεν διαβάστηκε από πού έρχεται ο ύπνος',
      text: 'Οι ρυθμίσεις πηγών δεν διαβάστηκαν. Για να μην μπερδευτούν οι συσκευές, οι νύχτες μένουν κενές και δεν '
          'αποθηκεύεται τίποτα ώσπου να διαλέξεις.',
      buttonText: 'Διάλεξε πηγή',
      onPressed: onOpen,
      // Round 1 (f9 · U2a-21): η μία ενέργεια της κάρτας, γεμάτο κουμπί.
      primary: true,
    );
  }
}

/// «Τρίτη» κ.λπ. για τις κάρτες κατάστασης.
String weekdayFull(DateTime d) => longDate(d).split(' ').first;

/// Ο ύπνος της νύχτας από το Oura, στη Σήμερα.
class OuraSleepTodayCard extends StatelessWidget {
  const OuraSleepTodayCard({super.key, required this.store, required this.now, required this.onTap});
  final HealthStore store;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    // Round 1 (S5-2 / U2a-05): η νύχτα της κάρτας «χθες βράδυ». Πριν από τις 04:00, όσο η νύχτα με τη σημερινή
    // ημερομηνία δεν έχει τελειώσει, είναι η προηγούμενη (όπως λίγο πριν από τα μεσάνυχτα), όχι «Περιμένει το Oura».
    final today = store.ouraNightDay(now);
    final night = store.ouraNightFor(today);
    final m = night?.main;
    const white = Colors.white;
    final soft = Colors.white.withValues(alpha: 0.8);

    Widget body;
    if (m == null) {
      final reason = store.ouraNightReason(today, now);
      // Η τελευταία νύχτα που ήρθε, ΜΕ την ημερομηνία της (έλεγχος UX U5): ποτέ ως «χθες βράδυ».
      final older = store.lastOuraNight;
      final olderMinutes = older == null || sameDay(older.day, today) ? null : older.nightMinutes;
      // Round 7 (R7-U1-13): η κάρτα κατάστασης από πάνω ([OuraStatusCard]) λέει ήδη γιατί λείπει η νύχτα και τι να
      // κάνεις. Εδώ τότε μόνο η τελευταία νύχτα που ήρθε (ή «—»), όχι ξανά «Περιμένει το Oura» / «Μόνο υπνάκος …».
      final told = reason != null && reason != EmptyNight.notYet && OuraStatusCard.shows(store);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!told)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                reason == null ? 'Δεν υπάρχουν δεδομένα από το δαχτυλίδι' : emptyNightText(reason),
                style: const TextStyle(color: white, fontSize: 20, fontWeight: FontWeight.w700),
              ),
            )
          else if (olderMinutes == null)
            const Padding(
              key: ValueKey('oura-today-no-night'),
              padding: EdgeInsets.only(top: 10),
              child: Text('—', style: TextStyle(color: white, fontSize: 42, fontWeight: FontWeight.w800)),
            ),
          if (olderMinutes != null) ...[
            SizedBox(height: told ? 10 : 6),
            Text(
              // Round 1 (U2a-11): η ημερομηνία και η διάρκεια δεν σπάνε σε δύο γραμμές («6 ώρες / 27 λεπτά»).
              'Τελευταία νύχτα που ήρθε: ${glued(shortDayDate(older!.day))}, ${glued(hoursMinutes(olderMinutes))}',
              key: const ValueKey('oura-today-older-night'),
              style: TextStyle(color: soft, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      );
      // «Μόνο υπνάκος»: οι ώρες του φαίνονται (π.χ. λαγοκοίμισμα που τελείωσε ως τις 22:00).
      if (reason == EmptyNight.onlyNap &&
          napTimes(night, nightOnly: true).isNotEmpty &&
          !(told && OuraStatusCard.showsNapTimes(store, now))) {
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            const SizedBox(height: 6),
            Text(
              'Υπνάκος ${napTimes(night, nightOnly: true)} ${glued('(δεν μετρά ως νύχτα)')}',
              key: const ValueKey('oura-only-nap-times'),
              style: TextStyle(color: soft, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ],
        );
      }
    } else {
      // Συνηθισμένη διάρκεια: ο ίδιος κανόνας «συνήθως» με όλη την εφαρμογή (μεσαία τιμή έως 14 προηγούμενων νυχτών,
      // τουλάχιστον 7), μόνο από νύχτες του Oura του ίδιου κομματιού πηγής (έλεγχος υπολογισμών C7, D9).
      final minutes = night!.nightMinutes;
      final base = ouraBaseline(store.history, store.plan, K.sleepMin, today)?.usual;
      final diff = base == null || minutes == null ? null : minutes - base.round();
      final parts = night.counted;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          () {
            // Πολύ μεγάλα γράμματα: το δαχτυλίδι κάτω από τη διάρκεια, για να μη μικραίνει η διάρκεια (σχέδια 9/11).
            final big = veryLargeText(context);
            final dur = minutes == null
                ? const Text('—', style: TextStyle(color: white, fontSize: 42, fontWeight: FontWeight.w800))
                : DurationValue(minutes, size: 42, color: white, unitColor: soft);
            // Χωρίς βαθμολογία από την Oura: χωρίς άδειο δαχτυλίδι «—» (έλεγχος UX U8, ίδιο με το ρολόι).
            final ring = night.sleepScore == null
                ? null
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScoreRing(
                        value: night.sleepScore!.toDouble(),
                        size: 60,
                        stroke: 6,
                        color: c.ring,
                        track: Colors.white.withValues(alpha: 0.16),
                      ),
                      const SizedBox(height: 4),
                      Text('βαθμολογία', style: TextStyle(color: soft, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  );
            if (big) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [dur, if (ring != null) ...[const SizedBox(height: 8), ring]]);
            }
            return Row(children: [Expanded(child: dur), if (ring != null) ...[const SizedBox(width: 12), ring]]);
          }(),
          if (diff != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              // Ένας κανόνας για το «συνήθως» σε όλες τις οθόνες (τρίτος έλεγχος F1).
              // Round 7 (R7-U1-4): όπως η κάρτα του ρολογιού (today.dart, U1a-14): «… από | ό,τι συνήθως», ποτέ
              // ορφανό «συνήθως».
              child: TrendPill(
                sleepVsUsualText(diff),
                up: diff == 0 ? null : diff > 0,
                onDark: true,
                maxLines: 2,
                keepLastWords: true,
              ),
            ),
          ],
          // Σχέδια 9/11 (1α): η «Καρδιά και θερμοκρασία στον ύπνο» γίνεται μία σειρά μέσα στον Ύπνο.
          ..._nightRow(context, soft),
          const SizedBox(height: 12),
          Text(
            // Round 1 (S5-1): οι ώρες του τόπου όπου κοιμήθηκες (ίδιες με του κινητού όταν δεν ταξιδεύεις).
            'Κοιμήθηκες ${parts.first.wallOnset == null ? '—' : hm(parts.first.wallOnset!)} ·\u00A0ξύπνησες ${hm(parts.last.wallEnd)}',
            key: const ValueKey('oura-today-times'),
            style: TextStyle(color: soft, fontSize: 13, fontWeight: FontWeight.w500, fontFeatures: tabular),
          ),
          if (night.shortNight || night.pieces.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (night.shortNight && (minutes ?? 0) < 180) shortNightLabel,
                if (parts.length > 1) 'σε ${parts.length} κομμάτια: ${[for (final p in parts) '${hm(p.wallStart)}–${hm(p.wallEnd)}'].join(' και ')} (το κενό δεν μετρά)',
              ].join(' ·\u00A0'),
              style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ],
          if (night.naps.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Και υπνάκος ${hoursMinutes(night.napMinutes)} (χωριστά, δεν μετρά στη νύχτα)',
              style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ],
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppCard.radius),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.nightTop, c.nightBottom]),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppCard.radius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.bedtime_rounded, size: 18, color: soft),
                    const SizedBox(width: 8),
                    Expanded(
                      // Round 9 (R9-U1-7): σε σχέση με ΤΩΡΑ, όπως η κάρτα του ρολογιού: 00:00–04:00 η νύχτα της χθεσινής
                      // ημερομηνίας ([OuraStore.ouraNightDay]) είναι «ξύπνημα χθες», όχι «χθες βράδυ».
                      child: Text('Ύπνος ·\u00A0${sleepNightLabel(today, now)}',
                          style: TextStyle(color: soft, fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    const SourceTag(Source.oura, onDark: true),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.6)),
                  ],
                ),
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension on OuraSleepTodayCard {
  /// Ετοιμότητα · HRV · Παλμοί ύπνου της χθεσινής νύχτας (από το Oura), κάτω από τη διάρκεια. Τίποτα αν λείπουν όλα.
  List<Widget> _nightRow(BuildContext context, Color soft) {
    // Η ίδια νύχτα με την κάρτα (S5-2: πριν από τις 04:00 η προηγούμενη).
    final day = store.ouraNightDay(now);
    final plan = store.plan;
    final readiness = plan.value(store.history, K.energy, day);
    final hrv = plan.value(store.history, K.hrv, day);
    final hr = plan.value(store.history, K.sleepHr, day);
    if (readiness == null && hrv == null && hr == null) return const [];
    // Οι τιμές στην ίδια γραμμή ακόμα κι αν μια ετικέτα πάει σε δύο γραμμές (έλεγχος premium, M2).
    Widget cell(String label, double? v, String unit) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, maxLines: 2, style: TextStyle(color: soft, fontSize: 13, fontWeight: FontWeight.w500, height: 1.25)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: v == null ? '—' : '${v.round()}',
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  if (v != null) TextSpan(text: ' $unit', style: TextStyle(color: soft, fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
                maxLines: 1,
                style: const TextStyle(fontFeatures: tabular),
              ),
            ),
          ]),
        );
    const labels = ['Ετοιμότητα', 'HRV', 'Παλμοί ύπνου'];
    final values = [(readiness, '/100'), (hrv, 'ms'), (hr, 'bpm')];
    final labelStyle = TextStyle(color: soft, fontSize: 13, fontWeight: FontWeight.w500, height: 1.25);
    return [
      const SizedBox(height: 14),
      Divider(height: 1, color: Colors.white.withValues(alpha: 0.18)),
      const SizedBox(height: 12),
      LayoutBuilder(
        key: const ValueKey('oura-today-night-row'),
        builder: (context, box) {
          // Τρεις στήλες όσο χωράει κάθε λέξη· αλλιώς (μεγάλα γράμματα) γραμμές «ετικέτα … τιμή», ποτέ σπασμένη λέξη.
          if (wordsFit(context, labels, labelStyle, (box.maxWidth - 20) / 3)) {
            return IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                cell(labels[0], readiness, '/100'),
                const SizedBox(width: 10),
                cell(labels[1], hrv, 'ms'),
                const SizedBox(width: 10),
                cell(labels[2], hr, 'bpm'),
              ]),
            );
          }
          // Ίδια στοίχιση σε κάθε γραμμή (έλεγχος premium, M2): ετικέτα αριστερά, τιμή δεξιά.
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < 3; i++)
              Padding(
                key: ValueKey('oura-today-night-line-$i'),
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Expanded(child: Text(labels[i], style: labelStyle)),
                  const SizedBox(width: 10),
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: values[i].$1 == null ? '—' : '${values[i].$1!.round()}',
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, fontFeatures: tabular)),
                    if (values[i].$1 != null) TextSpan(text: ' ${values[i].$2}', style: TextStyle(color: soft, fontSize: 13, fontWeight: FontWeight.w600)),
                  ])),
                ]),
              ),
          ]);
        },
      ),
    ];
  }
}

/// «Καρδιά και θερμοκρασία στον ύπνο»: HRV, παλμοί, θερμοκρασία (μέσοι όροι όλης της νύχτας), και ετοιμότητα.
/// Όλα από το Oura, σε σύγκριση με τις 14 τελευταίες νύχτες σου από το Oura.
class OuraRestCard extends StatelessWidget {
  const OuraRestCard({super.key, required this.store, required this.now, required this.onTap});
  final HealthStore store;
  final DateTime now;
  final VoidCallback onTap;

  /// Αν η νύχτα έχει έστω μία από τις τιμές της κάρτας.
  static bool hasData(HealthStore s, DateTime now) =>
      [K.hrv, K.sleepHr, K.skinTemp, K.energy].any((k) => s.plan.value(s.history, k, dayOf(now)) != null);

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final day = dayOf(now);
    final plan = store.plan;
    final hrv = ouraBaseline(store.history, plan, K.hrv, day);
    final hr = ouraBaseline(store.history, plan, K.sleepHr, day);
    final temp = plan.value(store.history, K.skinTemp, day);
    final readiness = plan.value(store.history, K.energy, day);

    // Ίδια λέξη «συνήθως» και η διαφορά των νούμερων όπως φαίνονται (έλεγχος υπολογισμών C6/C7, UX U7). Τρίτος
    // έλεγχος F1: ΕΝΑΣ κανόνας με την Καρδιά: «όπως συνήθως» μόνο για διαφορά 0 (πριν: ±2 bpm / ±3 ms εδώ, 0 εκεί,
    // οπότε 60 με συνήθως 59 ήταν «όπως συνήθως» εδώ και «+1 bpm» στην Καρδιά).
    String note(NightBaseline? b) {
      if (b == null) return '—';
      if (b.usual == null) return 'μαθαίνει';
      final d = shownDiff(b.value, b.usual!);
      if (d == 0) return 'όπως συνήθως';
      return '${signedShown(d)} ·\u00A0συνήθως ${b.usual!.round()}';
    }

    Widget cell(String label, String value, String unit, String sub) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: c.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: BigValue(value, unit: unit, size: 22),
              ),
              Text(sub, style: TextStyle(color: c.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            // Κλινικός έλεγχος M8 (4/11): όχι «ξεκούραση»· HRV και θερμοκρασία δεν είναι επικυρωμένοι δείκτες ανάρρωσης.
            Expanded(child: Text('Καρδιά και θερμοκρασία στον ύπνο', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text))),
            const SourceTag(Source.oura),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            cell('HRV (RMSSD)', hrv == null ? '—' : '${hrv.value.round()}', 'ms', note(hrv)),
            cell('Παλμοί στον ύπνο', hr == null ? '—' : '${hr.value.round()}', 'bpm', note(hr)),
            // Πάντα ως απόκλιση από το συνηθισμένο, ποτέ σαν θερμοκρασία σώματος (κλινικός έλεγχος M7, UX U4). Τρίτος
            // έλεγχος F2: η απόκλιση του ίδιου του Oura, ίδιο νούμερο και ίδια ετικέτα με το «Εκτός συνηθισμένου».
            cell(
              'Θερμοκρασία',
              temp == null ? '—' : signedDec(temp),
              '°C',
              temp == null ? '—' : ouraTempDeviationLabel,
            ),
          ]),
          const Hairline(vertical: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ετοιμότητα', style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                    const EstimateNote('εκτίμηση της Oura, όχι μέτρηση'),
                  ],
                ),
              ),
              Text(
                readiness == null ? '—' : '${readiness.round()}',
                style: TextStyle(color: c.text, fontSize: 24, fontWeight: FontWeight.w800, fontFeatures: tabular),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Μέσοι όροι όλης της νύχτας, σε σύγκριση με τις 14 τελευταίες νύχτες σου.',
            style: TextStyle(color: c.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
