import 'dart:async';

import 'package:flutter/material.dart';

import '../body_trend.dart' show bodyNoPermissionShort, bodyNotPermitted, guardBody, mixedDayPending, shownBody;
import '../data.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../history.dart';
import '../labels.dart';
import '../nav.dart';
import '../oxygen_note.dart';
import '../reference.dart';
import '../shown.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import '../unusual.dart';
import '../training/training_store.dart';
import '../training/wear_link.dart';
import '../training/zone.dart' show weekMovement;
import 'backup_reminder_card.dart';
import 'checkin_card.dart';
import 'nutrition.dart';
import 'oura_today.dart';
import 'prefs_notice.dart';
import 'sources_page.dart';
import 'unusual_card.dart';
import 'waist_sheet.dart';
import 'training/today_training_card.dart';
import 'week_card.dart';
import 'info_sheet.dart';
import 'oxygen_widgets.dart';

/// Round 3 (k1 · R3-A-1): κάτω από το «Βάρος» όταν η τελευταία ζύγιση είναι «σε αναμονή» (διαφέρει πολύ από τις
/// προηγούμενες και δεν τη βεβαίωσαν ακόμα επόμενες: weight_guard.dart). Φαίνεται, αλλά δεν μπαίνει σε υπολογισμούς.
const pendingWeightNote = 'Διαφέρει πολύ από τις προηγούμενες ζυγίσεις· δεν μετρά ακόμα στους υπολογισμούς.';

/// Round 4 (m1 · R4-A-2): δύο πολύ διαφορετικές ζυγίσεις την ίδια μέρα και καμία άλλη ζύγιση κοντά (π.χ. η πρώτη μέρα,
/// το παιδί πριν από σένα): δεν ξέρουμε ποια είναι δική σου, ως την επόμενη ζύγιση (weight_guard.dart `guardDays`).
const mixedWeightNote = 'Δύο πολύ διαφορετικές ζυγίσεις την ίδια μέρα· καμία δεν μετρά ακόμα, ως την επόμενη ζύγισή σου.';

/// Round 7 (U1-3): η οδηγία της κάρτας «Σήμερα μέση» όταν μένει μόνο η μέση (από το φύλλο «Μέση», waist_sheet.dart).
const waistTodayHint = 'Όρθιος, κοιλιά χαλαρή, στο τέλος της εκπνοής· η μεζούρα στο δέρμα.';

/// Η αρχική οθόνη: τα σημαντικά από κάθε κατηγορία, μία ερώτηση ανά κάρτα.
/// Πώς κοιμήθηκα; Τι έφαγα; Κουνήθηκα; Πού πάει το βάρος μου; Οι ειδοποιήσεις μόνο όταν υπάρχουν.
class TodayPage extends StatelessWidget {
  const TodayPage({
    super.key,
    required this.store,
    required this.food,
    required this.open,
    required this.openSettings,
    this.now,
    this.training,
    this.clock,
  });

  /// Για την κάρτα «Άσκηση σήμερα» (χωρίς αυτό: [TrainingStore.main]).
  final TrainingStore? training;

  final HealthStore store;
  final FoodStore food;

  /// Άνοιγμα κατηγορίας ([Cat]) και καρτέλας μέσα της.
  final void Function(int category, [int? tab]) open;
  final VoidCallback openSettings;

  /// Για τα στιγμιότυπα δοκιμών· στην εφαρμογή είναι πάντα «τώρα».
  final DateTime? now;

  /// Round 8 (R8-U1-5): το ρολόι όταν δεν δίνεται [now] (για τις δοκιμές της αλλαγής μέρας)· στην εφαρμογή [DateTime.now].
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final training = this.training ?? TrainingStore.main;
    final clock = this.clock ?? DateTime.now;
    // Round 8 (R8-U1-5): η σελίδα ξαναχτίζεται και στα μεσάνυχτα και στην επιστροφή στην εφαρμογή σε άλλη μέρα, όχι μόνο
    // όταν αλλάζουν τα δεδομένα. Πριν, από 23:57 ως 00:02 (επιστροφή < 5′ από την ανάγνωση: καμία νέα ανάγνωση) έμενε
    // «Σάββατο · Καλησπέρα», η «Διατροφή · σήμερα» με τα σύνολα του Σαββάτου και το «+ Φαγητό» έγραφε στο Σάββατο.
    return _DayClock(
      clock: clock,
      enabled: now == null,
      builder: (context) => ListenableBuilder(
        // Το ζωντανό περπάτημα το ακούει μόνο η κάρτα «Άσκηση σήμερα» (όχι όλη η σελίδα σε κάθε μήνυμα του ρολογιού).
        // Η αποθήκη προπονήσεων αλλάζει σε κάθε σετ: την ακούει μόνο η θέση της κάρτας (όχι όλη η σελίδα).
        listenable: Listenable.merge([store, WearLink.main.ready]),
        builder: (context, _) {
          final c = Aigaio.of(context);
          final d = store.data;
          final now = this.now ?? clock();
          final prefs = store.prefs;

          final settingsButton = IconButton(
            tooltip: 'Ρυθμίσεις',
            onPressed: openSettings,
            style: IconButton.styleFrom(
              backgroundColor: c.card,
              foregroundColor: c.text,
              fixedSize: const Size(46, 46),
              side: BorderSide(color: c.hairline),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            icon: const Icon(Icons.tune_rounded, size: 20),
          );
          // Στη μεγάλη οθόνη οι Ρυθμίσεις είναι κάτω στην πλευρική μπάρα. Round 9 (R9-U1-3): ο ίδιος κανόνας με το main.dart
          // ([useSideBar]: και ύψος), ώστε στο κλειστό Fold σε οριζόντια θέση (κάτω μπάρα) το κουμπί να μένει εδώ.
          final action = useSideBar(MediaQuery.sizeOf(context)) ? null : settingsButton;

          // Σχέδια 9/11 (1β): «Άσκηση σήμερα» αμέσως μετά τον Ύπνο· ξεκούραση ή χωρίς πρόγραμμα: καμία κάρτα.
          final Widget? trainingCard = prefs.show('training') ? _TrainingSlot(training: training, now: now) : null;
          // Round 7 (U1-12): η κάρτα λέει «σήμερα»: ανοίγει το ημερολόγιο στη ΣΗΜΕΡΙΝΗ μέρα, όπως το πάτημα στο widget
          // (main.dart, S2-8/S11-1). Πριν άνοιγε τη μέρα που είχε μείνει ανοιχτή (π.χ. τη χθεσινή), και το «+ Φαγητό» της
          // Διατροφής έγραφε εκεί.
          final foodCard = prefs.show('food')
              ? FoodTodayCard(
                  food: food,
                  now: now,
                  goals: store.goals,
                  onOpen: () {
                    food.setDay(this.now ?? clock());
                    open(Cat.food, FoodTab.diary);
                  })
              : null;

          if (d == null || !d.hasAnyPermission) {
            // Round 7 (U1-14): χωρίς άδεια της Samsung Health (πρώτο άνοιγμα, ή άδειες που αφαίρεσε μια ενημέρωση) μένουν η
            // προπόνηση της μέρας και το «+ Φαγητό»: δεν εξαρτώνται από τη Samsung (training.json, βάση τροφίμων).
            return PageFrame(
              eyebrow: longDate(now),
              title: greeting(now),
              action: action,
              onRefresh: () => store.refresh(),
              left: [
                if (PrefsNoticeCard.shows(store)) PrefsNoticeCard(store: store),
                _ConnectCard(store: store),
                if (trainingCard != null) trainingCard,
                if (foodCard != null) foodCard,
              ],
            );
          }

          final error = store.error != null ? _ErrorCard(store: store) : null;
          // Από τη σύνδεση του Oura η «νύχτα» (ύπνος, παλμοί και θερμοκρασία ύπνου, ετοιμότητα) έρχεται μόνο από αυτό.
          final ouraNight = store.plan.nightSource(now) != Source.watch;
          final openSleep = () => open(Cat.health, HealthTab.sleep);
          // Round 1 (U1a-11): με άγνωστο σχέδιο πηγών η κάρτα «Δεν διαβάστηκε από πού έρχεται ο ύπνος» (πάνω, με το κουμπί)
          // τα λέει όλα· η κάρτα ύπνου από κάτω επαναλάμβανε την ίδια φράση και έγραφε «Oura» για άγνωστη πηγή.
          final sleep = !prefs.show('sleep') || PlanUnknownCard.shows(store)
              ? null
              : ouraNight
                  ? OuraSleepTodayCard(store: store, now: now, onTap: openSleep)
                  : _SleepCard(data: d, now: now, onTap: openSleep);
          // Σχέδια 9/11 (1α): Ετοιμότητα, HRV και παλμοί ύπνου είναι πια μία σειρά μέσα στην κάρτα του Ύπνου (όχι
          // χωριστή κάρτα)· η πλήρης κάρτα, με θερμοκρασία και «συνήθως», είναι στην Υγεία › Ύπνος.
          final ouraState = PlanUnknownCard.shows(store)
              ? PlanUnknownCard(onOpen: () => Navigator.of(context).push(SourcesPage.route(store, now: this.now)))
              : OuraStatusCard.shows(store)
                  ? OuraStatusCard(store: store, now: now)
                  : null;
          final review = prefs.show('week') ? currentWeekReview(store.history, now, plan: store.analysisPlan) : null;
          final week = review == null ? null : WeekCard(review: review);
          final unusualResult = prefs.show('unusual') ? checkUnusual(store.history, dayOf(now), plan: store.analysisPlan) : null;
          final unusual = unusualResult != null && unusualResult.show ? UnusualCard(result: unusualResult) : null;
          // 12/11: ζύγισμα τις μέρες του χρήστη (προεπιλογή Δε · Τε · Πα) και μέση με μεζούρα τη μέρα της. Η κάρτα μένει
          // ώσπου να γίνουν και τα δύο της ημέρας· η ζύγιση έρχεται μόνη της από την InBody.
          // Round 3 (k1 · R3-B-4): η σημερινή ζύγιση της μέρας ([shownBody]: η πρώτη που μετρά, ή «σε αναμονή»), ίδια με την
          // κάρτα «Βάρος» και το ιστορικό. Πριν: η τελευταία ζύγιση της μέρας (η βραδινή μετά την προπόνηση, ή του παιδιού μετά
          // από σένα).
          final todayWeighIns = [
            for (final b in shownBody(d.body))
              if (sameDay(b.time, now)) b,
          ];
          final weighed = todayWeighIns.isEmpty ? null : todayWeighIns.last;
          final weighDay = store.profile.weighDays.contains(now.weekday);
          final waistDay = store.profile.waistDay == now.weekday;
          final waistToday = waistDay && store.waist.any((e) => e.day == waistDayKey(now));
          final weigh = (weighDay && weighed == null) || (waistDay && !waistToday)
              ? _WeighCard(
                  store: store,
                  now: now,
                  weighDay: weighDay,
                  waistDay: waistDay,
                  waistDone: waistToday,
                  weighedKg: weighed?.weight,
                  weighedAt: weighed?.time,
                  noPermission: bodyNotPermitted(d))
              : null;
          // Σχέδια 12/11 (A1/A3): ο έλεγχος θερμίδων κάτω από τη ζύγιση (απάντηση χρήστη 12/11). Ακούει μόνο το φαγητό.
          final checkIn = store.goals == null ? null : CheckInSlot(store: store, food: food, now: now);

          // 14/11 (αίτημα χρήστη: «από κάθε κατηγορία λίγο πιο πολλά, με μια ματιά»): τρεις ενότητες με δύο κάρτες η καθεμία,
          // πριν από τη Διατροφή. Κίνηση: βήματα και λεπτά άσκησης της εβδομάδας. Καρδιά: παλμοί ξύπνιος (χθες, ολόκληρη μέρα)
          // και οξυγόνο της νύχτας. Σώμα: βάρος και λίπος (InBody).
          final move = <Widget>[
            if (prefs.show('steps')) _stepsCard(context, d, now, () => open(Cat.exercise, ExerciseTab.move)),
            if (prefs.show('exweek'))
              ListenableBuilder(
                listenable: training,
                builder: (context, _) => _exerciseWeekCard(context, training, now, () => open(Cat.exercise, ExerciseTab.train)),
              ),
          ];
          final body = <Widget>[
            if (prefs.show('weight')) _weightCard(context, d, now, () => open(Cat.health, HealthTab.body)),
            if (prefs.show('fat')) _fatCard(context, d, now, () => open(Cat.health, HealthTab.body)),
          ];

          // Με το Oura: το Energy Score της Samsung δεν φαίνεται (τη θέση του παίρνει η ετοιμότητα του Oura στην
          // «Καρδιά και θερμοκρασία στον ύπνο»), και οι παλμοί/θερμοκρασία ύπνου είναι μόνο στην ίδια κάρτα. Το οξυγόνο μένει του ρολογιού.
          // Οξυγόνο: η σημείωση υπολογίζεται εδώ, γιατί η κάρτα εμφανίζεται ΜΟΝΗ της (και κλειστή στις Ρυθμίσεις) όταν το
          // χαμηλό επαναλαμβάνεται (τρίτος κλινικός έλεγχος C3/F5): αλλιώς η σύσταση «πες το στον γιατρό σου» ήταν δύο
          // πατήματα μακριά. Όχι για μία μόνο νύχτα.
          // Έλεγχος 3, E5: όλες οι 30 νύχτες από το ιστορικό (ίδιος αισθητήρας), πέρα από τη σύνδεση του Oura και το
          // όριο της επανάγνωσης· χωρίς «since».
          // Round 1 (S4-10, f4): «τελευταία νύχτα» = η πιο πρόσφατη με χαμηλότερη τιμή του ρολογιού (σήμερα ή χθες), όπως Καρδιά/Ύπνος.
          final oxNight = ouraNight ? oxygenLastNight(store, d, now) : null;
          final oxGuidance = oxNight != null
              ? oxygenGuidance(
                  d.spo2MinByNight(oxNight, ouraNights: true, windows: store.ouraWindows, history: store.history), oxNight,
                  today: now)
              : (d.lastNight == null
                  ? null
                  : oxygenGuidance(
                      d.spo2MinByNight(d.lastNight!.date, history: store.history), d.lastNight!.date, today: now));
          final oxAuto = !prefs.show('spo2') && oxGuidance != null && (oxGuidance.veryLowRepeated || oxGuidance.repeated);
          Widget oxCard() => ouraNight
              ? _watchSpo2Card(context, d, now, store.ouraWindows, oxGuidance!, () => open(Cat.health, HealthTab.heart),
                  auto: oxAuto)
              : _spo2Card(context, d, now, oxGuidance, () => open(Cat.health, HealthTab.heart), auto: oxAuto);
          final heart = <Widget>[
            if (prefs.show('awake')) _awakeCard(context, now, () => open(Cat.health, HealthTab.heart)),
            if (prefs.show('spo2')) oxCard(),
          ];
          final extras = <Widget>[
            if (!ouraNight && prefs.show('energy')) _energyCard(context, d, now, () => open(Cat.health, HealthTab.heart)),
            if (!ouraNight && prefs.show('rhr')) _restingCard(context, d, now, () => open(Cat.health, HealthTab.heart)),
            if (prefs.show('calories')) _caloriesCard(context, d, now, () => open(Cat.exercise, ExerciseTab.move)),
            if (!ouraNight && prefs.show('skin')) _skinCard(context, d, now, () => open(Cat.health, HealthTab.body)),
          ];
          List<Widget> section(String title, List<Widget> cards) => cards.isEmpty ? const [] : [SectionHeader(title), ...pairUp(cards)];

          // Μόνο κινητό (απόφαση 10/11): το τράβηγμα ανανεώνει και στο ανοιχτό Fold· φαίνεται μόνο «Ενημέρωση 18:40»
          // (σχέδια 9/11, 1α/1γ· έλεγχος premium, S8).
          // Round 1 (U1a-7): «Ενημέρωση χθες 18:40» (πεζό στη μέση της φράσης, όπως «Τελευταία μέτρηση, χθες 22:10»).
          final updated =
              'Ενημέρωση ${sameDay(d.readAt, now) ? '' : '${relativeDay(d.readAt, now).replaceFirst('Χθες', 'χθες')} '}${hm(d.readAt)}';
          final footer = Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              updated,
              key: const ValueKey('today-updated'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textTertiary, fontSize: 12.5),
            ),
          );

          final dbNotice = store.dbCorruptAt == null ? null : _DatabaseCard(store: store);
          // Έλεγχος 13/11 (S9-3): υπενθύμιση αντιγράφου, χαμηλά (ποτέ πάνω από τα δεδομένα υγείας)· αν δεν χρειάζεται, τίποτα.
          final backupReminder = BackupReminderSlot(store: store, food: food, training: training, now: now);
          final alerts = [
            // Round 1 (f3 · S3-2/S9-1, S9-5): οι ρυθμίσεις δεν διαβάζονται ή η τελευταία αλλαγή τους δεν γράφτηκε.
            if (PrefsNoticeCard.shows(store)) PrefsNoticeCard(store: store),
            if (dbNotice != null) dbNotice,
            if (ouraState != null) ouraState,
            if (error != null) error,
            if (unusual != null) unusual,
            if (oxAuto) KeyedSubtree(key: const ValueKey('today-oxygen-auto'), child: oxCard()),
          ];

          return PageFrame(
            eyebrow: longDate(now),
            title: greeting(now),
            action: action,
            onRefresh: () => store.refresh(),
            // Round 1 (U1a-13): η «Η εβδομάδα σου» (≈ 980 dp, Κυριακή βράδυ και Δευτέρα) κάτω από τη Διατροφή και τα
            // Βήματα/Βάρος· πριν, τη Δευτέρα το «+ Φαγητό» ήταν τρεις οθόνες πιο κάτω. Στο ανοιχτό Fold ήταν ήδη τελευταία.
            // 14/11: η Διατροφή μετά από Κίνηση, Καρδιά και Σώμα (αίτημα χρήστη).
            single: [
              ...alerts,
              if (weigh != null) weigh,
              if (checkIn != null) checkIn,
              if (sleep != null) sleep,
              if (trainingCard != null) trainingCard,
              ...section('Κίνηση', move),
              ...section('Καρδιά', heart),
              ...section('Σώμα', body),
              // Χωρίς επικεφαλίδα: η κάρτα γράφει ήδη «Διατροφή · σήμερα».
              if (foodCard != null) foodCard,
              if (week != null) week,
              ...section('Επίσης', extras),
              backupReminder,
              footer,
            ],
            top: alerts,
            // Fold ανοιχτό (σχέδια 9/11, 1γ): ρητά αριστερά Ύπνος + Άσκηση, δεξιά Διατροφή + Βήματα/Βάρος.
            // Round 7 (U1-1): η «Η εβδομάδα σου» (≈ 1.000 dp) όχι αριστερά: έκανε τη στήλη ~1.900 dp με ~560 δεξιά.
            // Round 9 (R9-U1-2): ούτε δεξιά: εκεί άφηνε τρύπα ~750 dp αριστερά (στιγμιότυπο 68e, Δευτέρα του ελέγχου θερμίδων).
            // Κάτω από τις δύο στήλες, σε όλο το πλάτος, με τις γραμμές της σε δύο στήλες ([WeekCard]), και μετά η «Ενημέρωση».
            // 14/11: αριστερά ύπνος, άσκηση, Κίνηση, Καρδιά· δεξιά Σώμα, Διατροφή, «Επίσης».
            left: [
              if (weigh != null) weigh,
              if (checkIn != null) checkIn,
              if (sleep != null) sleep,
              if (trainingCard != null) trainingCard,
              ...section('Κίνηση', move),
              ...section('Καρδιά', heart),
            ],
            right: [
              ...section('Σώμα', body),
              if (foodCard != null) foodCard,
              ...section('Επίσης', extras),
              backupReminder,
            ],
            bottom: [if (week != null) week, footer],
          );
        },
      ),
    );
  }

  Widget _stepsCard(BuildContext context, Dashboard d, DateTime now, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final steps = d.todaySteps;
    final base = d.stepsBaseline;
    final last7 = d.steps.length <= 7 ? d.steps : d.steps.sublist(d.steps.length - 7);
    return StatCard(
      icon: Icons.directions_walk_rounded,
      color: c.exercise,
      // Από αποθηκευμένη ανάγνωση άλλης μέρας: το λέει, να μη μοιάζει με τα σημερινά.
      // UX U8: ίδια μορφή ημερομηνίας με τις άλλες κάρτες («Σάβ 24/10»).
      title: datedTitle('Βήματα', d.readAt, now),
      value: steps == null ? null : thousands(steps),
      note: base == null ? null : 'Συνήθως ${thousands(base)}',
      chart: last7.length >= 2 ? MiniBars(values: [for (final s in last7) s.value], color: c.exercise) : null,
      onTap: onTap,
    );
  }

  Widget _weightCard(BuildContext context, Dashboard d, DateTime now, VoidCallback onTap) {
    final c = Aigaio.of(context);
    // Round 2 (g4 · R2-D-6, R2-D-8): ίδιοι κανόνες με το Σώμα, τις Τάσεις και τη διόρθωση θερμίδων: μία ζύγιση ανά μέρα
    // (η πρώτη της μέρας που μετρά) και καμία «ξένη» ([countedBody]). Πριν: η τελευταία ζύγιση, όποια κι αν ήταν (π.χ. του
    // παιδιού μετά από σένα, με «−47,0 kg»), και η διαφορά από την αμέσως προηγούμενη, ακόμα και της ίδιας μέρας. Ζύγιση
    // «σε αναμονή» (διαφέρει πολύ, χωρίς ακόμα επόμενη· weight_guard.dart) φαίνεται κανονικά.
    // Round 3 (k1 · R3-A-1): η «σε αναμονή» φαίνεται με τη σημείωση [pendingWeightNote] ([shownBody], [guardBody]).
    final guard = guardBody(d.body);
    final daily = [for (final b in guard.shown) if (b.weight != null) b];
    final last = daily.isEmpty ? null : daily.last;
    final waiting = last != null && guard.pending.contains(last);
    // Round 4 (m1 · R4-A-4): διαφορά και γράφημα μόνο από ζυγίσεις που μετρούν. Ζύγιση «σε αναμονή» φαίνεται με τη
    // σημείωση, χωρίς «−42,6 kg από 4/12» (πριν: η διαφορά της ζύγισης του παιδιού από τη δική σου).
    final counted = [for (final b in guard.counted) if (b.weight != null) b];
    final at = last == null ? -1 : counted.indexWhere((b) => identical(b, last));
    final prev = waiting || at < 1 ? null : counted[at - 1];
    Widget? trend;
    if (last?.weight != null && prev?.weight != null) {
      // Η διαφορά των νούμερων όπως φαίνονται (τρίτος έλεγχος F3): 82,2 και 83,4 → «−1,2», όχι «−1,1».
      final diff = shownDiff(last!.weight!, prev!.weight!, 1);
      trend = TrendPill(
        // Σύντομη ημερομηνία και έως 2 γραμμές: στα 360 dp το «από 13 Αυγ» κοβόταν (έλεγχος UX U2).
        '${signedDec(diff)} kg από ${prev.time.day}/${prev.time.month}',
        // Ουδέτερο χρώμα: χωρίς στόχο (μετά τον γιατρό) ούτε η πτώση ούτε η άνοδος είναι «καλή» ή «κακή».
        kind: TrendKind.neutral,
        maxLines: 2,
        keepLastWords: true,
      );
    }
    final weights = [for (final b in counted) b.weight!];
    final recent = weights.length <= 10 ? weights : weights.sublist(weights.length - 10);
    return StatCard(
      icon: Icons.monitor_weight_rounded,
      color: c.body,
      // Αν η τελευταία ζύγιση δεν είναι σημερινή, λέει πότε έγινε. Round 7 (U1-2): σε σχέση με ΤΩΡΑ, όχι με την ώρα της
      // ανάγνωσης (με παλιά ανάγνωση η προχθεσινή ζύγιση έγραφε «Χθες»), και με την ίδια μορφή με τις άλλες κάρτες
      // («Βάρος · Δευ 16/11», όπως «Βήματα · Τρί 17/11»· πριν «Βάρος · Χθες» / «· Παρασκευή» / «· 13 Νοε»).
      title: datedTitle('Βάρος', last?.time, now),
      value: last?.weight == null ? null : dec(last!.weight!),
      unit: 'kg',
      trend: trend,
      note: waiting ? (mixedDayPending(guard.pending, last) ? mixedWeightNote : pendingWeightNote) : null,
      // Round 1 (U1a-20): ελάχιστο εύρος 3 kg, όπως στο Σώμα· η αλλαγή 0,5–1 kg από μέρα σε μέρα είναι νερό, όχι τάση.
      chart: recent.length >= 2 ? Sparkline(values: recent, color: c.body, minRange: 3) : null,
      // Round 1 (S11-8, σημείωση του f1): όταν η Samsung δεν έδωσε τις ζυγίσεις αυτή τη φορά, το λέει (όπως το Σώμα)·
      // πριν έγραφε «Ζυγίσου στην InBody» και για ζύγιση που υπάρχει αλλά δεν διαβάστηκε.
      // Round 8 (R8-A4-3): και όταν η άδεια «Σύσταση σώματος» είναι κλειστή (πριν: «Ζυγίσου στην InBody» όλη μέρα).
      empty: d.failed.contains('body')
          ? 'Οι ζυγίσεις δεν διαβάστηκαν τώρα. Τράβηξε την οθόνη προς τα κάτω για να ξαναδοκιμάσεις.'
          : bodyNotPermitted(d)
              ? bodyNoPermissionShort
              : 'Ζυγίσου στην InBody. Η μέτρηση φτάνει εδώ σε λίγα λεπτά.',
      onTap: onTap,
    );
  }

  /// Άσκηση της εβδομάδας (14/11): λεπτά μέτριας άσκησης από τα περπατήματα (στη ζώνη ή πιο πάνω) από τα 150 του Π.Ο.Υ.,
  /// και μέρες με βάρη. Ίδιος υπολογισμός με την κάρτα «Αυτή η εβδομάδα» της Άσκησης ([weekMovement]).
  Widget _exerciseWeekCard(BuildContext context, TrainingStore training, DateTime now, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final w = weekMovement(training.sessions, now);
    return StatCard(
      key: const ValueKey('today-exweek'),
      icon: Icons.timer_outlined,
      color: c.exercise,
      // Σύντομος τίτλος και η εβδομάδα από κάτω (στη μισή κάρτα των 360 dp ο «Άσκηση εβδομάδας» έπιανε δύο γραμμές).
      title: 'Άσκηση',
      subtitle: 'αυτή η εβδομάδα',
      value: '${w.moderateMin}',
      unit: 'από 150 λεπτά',
      note: 'Βάρη: ${w.strengthDays == 1 ? '1 μέρα' : '${w.strengthDays} μέρες'}',
      chart: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: (w.moderateMin / 150).clamp(0.0, 1.0), minHeight: 8, color: c.exercise, backgroundColor: c.hairline),
        ),
      ),
      onTap: onTap,
    );
  }

  /// Παλμοί ξύπνιος (14/11): της τελευταίας ΟΛΟΚΛΗΡΩΜΕΝΗΣ μέρας (συνήθως χθες· η σημερινή δεν μετρά), με το «συνήθως», όπως
  /// στην Καρδιά ([_AwakeHeartCard] του heart.dart).
  Widget _awakeCard(BuildContext context, DateTime now, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final plan = store.plan;
    final day = DateTime(now.year, now.month, now.day);
    DateTime? last;
    for (var i = 1; i <= 3 && last == null; i++) {
      final x = DateTime(day.year, day.month, day.day - i);
      if (plan.value(store.history, K.dayHr, x) != null) last = x;
    }
    final b = last == null ? null : personalBaseline(store.history, plan, K.dayHr, last);
    final pts = planSeries(store.history, plan, K.dayHr, DateTime(day.year, day.month, day.day - 7), DateTime(day.year, day.month, day.day - 1)).points;
    Widget? trend;
    if (b?.usual != null) {
      final dd = shownDiff(b!.value, b.usual!);
      trend = TrendPill(dd == 0 ? asUsualText : '${signedShown(dd)} ·\u00A0συνήθως ${b.usual!.round()}', up: dd == 0 ? null : dd > 0);
    }
    return StatCard(
      key: const ValueKey('today-awake'),
      icon: Icons.favorite_border_rounded,
      color: c.heart,
      // Η μέρα σε δική της γραμμή (UX U1): «Παλμοί ξύπνιος · Παρ 13/11» έπιανε τρεις γραμμές στη μισή κάρτα.
      title: 'Παλμοί ξύπνιος',
      subtitle: last == null ? null : shortDayDate(last),
      value: b?.value.round().toString(),
      unit: 'bpm',
      trend: trend,
      chart: pts.length >= 2 ? Sparkline(values: [for (final p in pts) p.$2], color: c.heart, minRange: 8) : null,
      empty: 'Έρχεται μετά από μια ολόκληρη μέρα με το ρολόι.',
      onTap: onTap,
    );
  }

  /// Λίπος σώματος (14/11): η τελευταία ζύγιση που μετρά (ίδιοι κανόνες με το Βάρος: [guardBody]), με τους μύες από κάτω.
  /// Χωρίς «καλό/κακό»: η αλλαγή κάτω από 2 μονάδες είναι θόρυβος της ζυγαριάς (McLester 2020, όπως στο Σώμα).
  Widget _fatCard(BuildContext context, Dashboard d, DateTime now, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final counted = [for (final b in guardBody(d.body).counted) if (b.fatPct != null) b];
    final last = counted.isEmpty ? null : counted.last;
    final recent = counted.length <= 10 ? counted : counted.sublist(counted.length - 10);
    return StatCard(
      key: const ValueKey('today-fat'),
      icon: Icons.pie_chart_outline_rounded,
      color: c.body,
      title: 'Λίπος',
      subtitle: last == null || sameDay(last.time, now) ? null : shortDayDate(last.time),
      value: last == null ? null : dec(last.fatPct!),
      unit: '%',
      note: last?.smm == null ? null : 'Μύες ${dec(last!.smm!)} kg',
      chart: recent.length >= 2 ? Sparkline(values: [for (final b in recent) b.fatPct!], color: c.body, minRange: 4) : null,
      empty: bodyNotPermitted(d) ? bodyNoPermissionShort : 'Έρχεται με την επόμενη ζύγιση στην InBody.',
      onTap: onTap,
    );
  }

  Widget _energyCard(BuildContext context, Dashboard d, DateTime now, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final e = d.latestEnergy;
    final recent = d.energy.length <= 7 ? d.energy : d.energy.sublist(d.energy.length - 7);
    return StatCard(
      icon: Icons.bolt_rounded,
      color: c.energy,
      title: 'Energy Score',
      value: e?.value.round().toString(),
      unit: 'από 100',
      // Round 7 (U1-2): η μέρα σε σχέση με τώρα, όχι με την ώρα της ανάγνωσης.
      note: e == null ? null : '${relativeDay(e.day, now)} ·\u00A0εκτίμηση της Samsung',
      chart: recent.length >= 2 ? Sparkline(values: [for (final v in recent) v.value], color: c.energy, minRange: 20) : null,
      empty: 'Έρχεται μετά από έναν ύπνο με το ρολόι.',
      onTap: onTap,
    );
  }

  Widget _restingCard(BuildContext context, Dashboard d, DateTime now, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final hr = d.lastNight?.sleepingHr;
    final base = d.restingHrBaseline;
    Widget? trend;
    if (hr != null && base != null) {
      // Η διαφορά των νούμερων όπως φαίνονται (έλεγχος υπολογισμών C6) και η ίδια λέξη «συνήθως» παντού (C7/U7).
      // Ένας κανόνας σε όλες τις οθόνες (τρίτος έλεγχος F1).
      final diff = shownDiff(hr, base);
      trend = diff == 0
          ? const TrendPill(asUsualText)
          : TrendPill(
              '${signedShown(diff)} ·\u00A0συνήθως ${base.round()}',
              up: diff > 0,
              // Η πτώση είναι ουδέτερη, όχι «καλή» (κλινικός έλεγχος M4). Κόκκινο μόνο με τον κανόνα του «Εκτός
              // συνηθισμένου» (κλινικός έλεγχος 4, C1)· αλλιώς γκρι.
              kind: diff > 0 && sleepHrOff(store.history, d.lastNight!.date, plan: store.analysisPlan)
                  ? TrendKind.bad
                  : TrendKind.neutral,
            );
    }
    final recent = d.nights.where((n) => n.sleepingHr != null).toList();
    final last7 = recent.length <= 7 ? recent : recent.sublist(recent.length - 7);
    return StatCard(
      icon: Icons.favorite_rounded,
      color: c.heart,
      title: datedTitle('Παλμοί στον ύπνο', hr == null ? null : d.lastNight!.date, now),
      value: hr?.round().toString(),
      unit: 'bpm',
      trend: trend,
      // Ελάχιστο εύρος 8 bpm, όπως στα γραφήματα της Καρδιάς (U1a-20).
      chart: last7.length >= 2 ? Sparkline(values: [for (final n in last7) n.sleepingHr!], color: c.heart, minRange: 8) : null,
      empty: 'Έρχεται μετά από έναν ύπνο με το ρολόι.',
      onTap: onTap,
    );
  }

  /// Οξυγόνο της νύχτας από το ρολόι όταν ο ύπνος είναι του Oura: μετρήσεις του ρολογιού μέσα στις ώρες της
  /// νύχτας του Oura. Χωρίς νύχτα του Oura δεν ξέρουμε πότε κοιμήθηκες: κενό, με τον λόγο.
  /// [g]: η σημείωση χαμηλού οξυγόνου (B7) με τις τιμές του ορισμού A4. [auto]: η κάρτα φαίνεται μόνη της, επειδή το
  /// χαμηλό επαναλαμβάνεται· τότε η σημείωση φαίνεται και χωρίς τιμή για την τελευταία νύχτα.
  Widget _watchSpo2Card(BuildContext context, Dashboard d, DateTime now, SleepWindows windows, OxygenGuidance g,
      VoidCallback onTap, {bool auto = false}) {
    final c = Aigaio.of(context);
    // 7/11: μέσος όρος από το Oura, χαμηλότερη από το ρολόι (μόνο με κάλυψη ≥ 50%).
    final rox = ringOxygen(store, d, now, windows);
    final noWindow = !windows.mains.containsKey(dateKey(dayOf(now)));
    return StatCard(
      icon: Icons.air_rounded,
      color: c.sleep,
      title: 'Οξυγόνο στον ύπνο',
      value: rox.avg == null ? null : spo2AvgText(rox.avg!),
      unit: '%',
      // Round 1 (U1a-6): ένα όνομα παντού για τη χαμηλότερη μεμονωμένη τιμή.
      trend: rox.min == null ? null : TrendPill('Χαμηλότερη τιμή ${lowestText(rox.min!)}% ·\u00A0ρολόι'),
      note: rox.isEmpty ? null : (g.short ?? (rox.avg == null ? ringAvgMissing(store) : 'Μέσος όρος ·\u00A0Oura')),
      empty: auto && g.short != null
          ? g.short
          : noWindow
              ? 'Χωρίς νύχτα από το δαχτυλίδι δεν ξέρουμε πότε κοιμήθηκες· το οξυγόνο της νύχτας μένει κενό.'
              : ringAvgMissing(store),
      onTap: onTap,
    );
  }

  Widget _caloriesCard(BuildContext context, Dashboard d, DateTime now, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final total = (d.activity['calories'] as num?)?.toDouble();
    final active = (d.activity['activeCalories'] as num?)?.toDouble();
    final minutes = (d.activity['activeMinutes'] as num?)?.toInt();
    return StatCard(
      icon: Icons.local_fire_department_rounded,
      color: c.heart,
      // Κλινικός έλεγχος M9: τα ρολόγια κάνουν μεγάλα λάθη στις θερμίδες (συχνά 20–30%).
      // Οι θερμίδες είναι της μέρας της ανάγνωσης: από αποθηκευμένη ανάγνωση άλλης μέρας, με την ημερομηνία (A11).
      title: datedTitle('Θερμίδες', total == null ? null : d.readAt, now),
      value: total == null ? null : thousands(total),
      unit: 'kcal',
      note: active == null ? 'Εκτίμηση ρολογιού' : 'Εκτίμηση ρολογιού ·\u00A0από κίνηση ${thousands(active)} kcal',
      trend: (minutes != null && minutes > 0) ? TrendPill('Ενεργός ${hoursMinutes(minutes)}') : null,
      onTap: onTap,
    );
  }

  Widget _spo2Card(BuildContext context, Dashboard d, DateTime now, OxygenGuidance? g, VoidCallback onTap,
      {bool auto = false}) {
    final c = Aigaio.of(context);
    final n = d.lastNight;
    final min = n?.spo2Min;
    return StatCard(
      icon: Icons.air_rounded,
      color: c.sleep,
      title: datedTitle('Οξυγόνο', n?.spo2Avg == null && min == null ? null : n!.date, now),
      value: n?.spo2Avg == null ? null : spo2AvgText(n!.spo2Avg!),
      unit: '%',
      trend: min == null
          ? null
          : TrendPill('Χαμηλότερη τιμή ${lowestText(min)}% ·\u00A0ενδεικτικό'),
      note: g?.short,
      empty: auto && g?.short != null ? g!.short : 'Έρχεται μετά από έναν ύπνο με το ρολόι.',
      onTap: onTap,
    );
  }

  Widget _skinCard(BuildContext context, Dashboard d, DateTime now, VoidCallback onTap) {
    final c = Aigaio.of(context);
    final t = d.lastNight?.skinTemp;
    final base = d.skinTempBaseline;
    return StatCard(
      icon: Icons.thermostat_rounded,
      color: c.move,
      title: datedTitle('Θερμοκρασία καρπού', t == null ? null : d.lastNight!.date, now),
      // Χωρίς μέσο όρο δεν δείχνουμε απόλυτη τιμή καρπού (π.χ. 33,6 °C διαβάζεται ως υποθερμία· κλινικός έλεγχος L5).
      // Διαφορά των νούμερων όπως φαίνονται, ίδια με το «Εκτός συνηθισμένου» (τρίτος έλεγχος F3).
      value: t == null || base == null ? null : signedDec(shownDiff(t, base, 1)),
      unit: '°C',
      note: (t != null && base != null) ? 'Απόκλιση από τα συνηθισμένα σου' : null,
      empty: t == null ? 'Έρχεται μετά από έναν ύπνο με το ρολόι.' : 'Μαθαίνει το συνηθισμένο σου (7 νύχτες).',
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Ο ύπνος της νύχτας, σε σύντομη μορφή (η πλήρης είναι στην Υγεία › Ύπνος)
// ---------------------------------------------------------------------------

class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.data, required this.now, required this.onTap});

  final Dashboard data;

  /// Round 8 (R8-U1-1): «χθες βράδυ» / «ξύπνημα χθες» σε σχέση με ΤΩΡΑ, όπως το Βάρος και το Energy Score (R7-U1-2).
  /// Πριν σε σχέση με την ώρα της ανάγνωσης: με χθεσινή ανάγνωση (δεν έγινε ακόμα νέα) η νύχτα Πέμ→Παρ έγραφε το
  /// Σάββατο «χθες βράδυ».
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final n = data.lastNight;

    if (n == null) {
      return EmptyCard(
        icon: Icons.bedtime_rounded,
        color: c.sleep,
        title: 'Ύπνος',
        text: 'Δεν υπάρχει ύπνος τις τελευταίες μέρες. Φόρεσε το ρολόι στον ύπνο και θα εμφανιστεί εδώ το πρωί.',
      );
    }

    const white = Colors.white;
    final soft = Colors.white.withValues(alpha: 0.75);
    final base = data.sleepBaseline;
    // Σύγκριση μόνο για νύχτα με φάσεις (πραγματικός ύπνος): χωρίς φάσεις η διάρκεια έχει τα ξυπνήματα.
    final diff = base == null || !n.fullDuration ? null : n.minutes - base.round();
    // Ένας κανόνας για το «συνήθως» (τρίτος έλεγχος F1): «Όσο κοιμάσαι συνήθως» μόνο για 0 λεπτά διαφορά.
    final total = stageOrder.fold<int>(0, (s, k) => s + (n.stageMinutes[k] ?? 0));
    final stages = [for (final k in stageOrder) if ((n.stageMinutes[k] ?? 0) > 0) k];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppCard.radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.nightTop, c.nightBottom],
        ),
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
                      child: Text(
                        'Ύπνος ·\u00A0${sleepNightLabel(n.date, now)}',
                        style: TextStyle(color: soft, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.6)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: DurationValue(n.minutes, size: 42, color: white, unitColor: soft)),
                    // Χωρίς βαθμολογία της νύχτας (π.χ. σε κομμάτια, η Samsung βαθμολογεί το καθένα): χωρίς άδειο
                    // δαχτυλίδι «—», που ήθελε εξήγηση (έλεγχος UX U8).
                    if (n.score != null) ...[
                      const SizedBox(width: 12),
                      ScoreRing(
                        value: n.score!.toDouble(),
                        size: 64,
                        stroke: 6,
                        color: c.ring,
                        track: Colors.white.withValues(alpha: 0.16),
                      ),
                    ],
                  ],
                ),
                if (diff != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TrendPill(
                      sleepVsUsualText(diff),
                      up: diff == 0 ? null : diff > 0,
                      onDark: true,
                      maxLines: 2,
                      keepLastWords: true,
                    ),
                  ),
                ],
                if (!n.staged) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Χωρίς φάσεις από τη Samsung· διάρκεια με τα ξυπνήματα',
                    style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                ],
                if (n.partial) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Ένα κομμάτι της νύχτας ήρθε χωρίς φάσεις: η διάρκεια είναι μικρότερη από τον πραγματικό ύπνο',
                    style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                ],
                if (n.estimatedMinutes > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    // Μία φράση παντού για το κενό που ίσως ήταν ύπνος (UX U3).
                    '+${hoursMinutes(n.estimatedMinutes)} $possibleSleepPhrase',
                    style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                ],
                if (total > 0) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 10,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, k) in stages.indexed) ...[
                            if (i > 0) const SizedBox(width: 2),
                            // Round 8 (R8-U1-2): χρώματα για τη σκούρα κάρτα (≥ 3:1), όχι της λευκής κάρτας.
                            Expanded(flex: n.stageMinutes[k]!, child: ColoredBox(color: c.stageOnNight(k))),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(hm(n.start), style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w600, fontFeatures: tabular)),
                      Expanded(
                        // Χωρίς ποσοστά μίας νύχτας (κλινικός έλεγχος H1): μόνο η μπάρα, ως εκτίμηση.
                        // Round 2 (R2-U1-1): 8 dp από τις ώρες και ίδιο μέγεθος γραμμάτων παντού· όταν δεν χωρά σπάει σε
                        // «Φάσεις · εκτίμηση | της Samsung» (οι δύο τελευταίες λέξεις μαζί, U1a-14), δεν μικραίνει.
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'Φάσεις ·\u00A0εκτίμηση της\u00A0Samsung',
                            key: const ValueKey('today-stages-label'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      Text(hm(n.end), style: TextStyle(color: soft, fontSize: 12.5, fontWeight: FontWeight.w600, fontFeatures: tabular)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Η νύχτα στον τίτλο της κάρτας ύπνου της Σήμερα («Ύπνος · …»), σε σχέση με ΤΩΡΑ ([now]· R8-U1-1). [wakeDay]: η μέρα
/// της νύχτας (το πρωί που ξύπνησες). Η ίδια συνάρτηση για το ρολόι και το Oura (oura_today.dart).
/// Round 9 (R9-U1-1): για παλιότερη νύχτα η μέρα όπως στις άλλες κάρτες («ξύπνημα Τετ 11/11», [shortDayDate]), όχι με πεζά
/// («ξύπνημα τετάρτη», «ξύπνημα 3 νοε»). Round 9 (R9-U1-7): και το Oura μετά τα μεσάνυχτα («ξύπνημα χθες» για τη νύχτα
/// της χθεσινής ημερομηνίας, όχι «χθες βράδυ»).
String sleepNightLabel(DateTime wakeDay, DateTime now) {
  if (sameDay(wakeDay, now)) return 'χθες βράδυ';
  if (daysBetween(wakeDay, now) == 1) return 'ξύπνημα χθες';
  return 'ξύπνημα ${shortDayDate(wakeDay)}';
}

// ---------------------------------------------------------------------------

class _ConnectCard extends StatelessWidget {
  const _ConnectCard({required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final err = store.error;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        // Round 7 (U1-14): ίδιες γωνίες με τις άλλες κάρτες (πριν 28).
        borderRadius: BorderRadius.circular(AppCard.radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.nightTop, c.nightBottom],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            store.loading ? 'Διαβάζω…' : 'Σύνδεση με Samsung Health',
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            err != null
                ? errorText(err['kind'] as String? ?? 'other')
                : 'Θα ανοίξει το παράθυρο του Samsung Health. Πάτα «Επιλογή όλων» και «Τέλος». '
                    'Η εφαρμογή μόνο διαβάζει.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15.5, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (store.loading)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: c.nightTop),
              onPressed: () => store.refresh(askPermissions: true),
              child: const Text('Σύνδεση με Samsung Health'),
            ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final kind = store.error?['kind'] as String? ?? 'other';
    return EmptyCard(
      icon: Icons.sync_problem_rounded,
      color: c.bad,
      title: 'Δεν έγινε νέα ανάγνωση',
      text: '${errorText(kind)} Βλέπεις τα τελευταία δεδομένα που διάβασα.',
      buttonText: 'Δοκίμασε ξανά',
      onPressed: () => store.refresh(),
      primary: true,
    );
  }
}

/// Η βάση του κινητού βρέθηκε χαλασμένη (A7): τίποτα δεν σβήστηκε, το παλιό αρχείο κρατήθηκε.
class _DatabaseCard extends StatelessWidget {
  const _DatabaseCard({required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return EmptyCard(
      icon: Icons.storage_rounded,
      color: c.bad,
      title: 'Η βάση χάλασε· κράτησα αντίγραφο',
      // Round 7 (R7-A9-1/2, f4): η σωστή διαδρομή, τα προϊόντα, και πόσα ξαναμπήκαν από το αρχείο που κρατήθηκε.
      text: databaseNoticeText(store.dbRecovered, partial: store.dbPartial),
      buttonText: 'Εντάξει',
      onPressed: () => store.dismissDatabaseNotice(),
    );
  }
}

/// «Σήμερα ζύγιση» (σχέδια 12/11, 5α): στις μέρες ζυγίσματος και στη μέρα της μέσης. Λίστα με ό,τι μένει: η ζύγιση
/// σημειώνεται μόνη της όταν έρθει από την InBody· η μέση γράφεται από το κουμπί. Χωρίς ειδοποίηση· μόνο κάρτα.
class _WeighCard extends StatelessWidget {
  const _WeighCard(
      {required this.store,
      required this.now,
      required this.weighDay,
      required this.waistDay,
      this.waistDone = false,
      this.weighedKg,
      this.weighedAt,
      this.noPermission = false});
  final HealthStore store;
  final DateTime now;
  final bool weighDay, waistDay;

  /// Round 8 (R8-A4-3): η άδεια «Σύσταση σώματος» της Samsung Health είναι κλειστή: η ζύγιση δεν μπορεί να φτάσει, άρα
  /// δεν θα σημειωθεί μόνη της· η κάρτα το λέει κάτω από τη «Ζύγιση InBody».
  final bool noPermission;

  /// Η μέση της ημέρας γράφτηκε (η κάρτα μένει ως να έρθει η ζύγιση· ανασκόπηση 11/11, S3).
  final bool waistDone;
  final double? weighedKg;
  final DateTime? weighedAt;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final weighed = weighedAt != null;
    Widget item(bool done, String text, {String? trailing}) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            done
                ? Icon(Icons.check_circle_rounded, size: 24, color: c.good)
                : Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.textTertiary, width: 2)),
                  ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text))),
            if (trailing != null) Text(trailing, style: TextStyle(fontSize: 13.5, color: c.textSecondary, fontFeatures: tabular)),
          ]),
        );
    return Container(
      key: const ValueKey('today-weigh'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.tint(c.body),
        borderRadius: BorderRadius.circular(AppCard.radius),
        border: Border.all(color: c.body.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            IconBadge(Icons.monitor_weight_rounded, c.body, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                weighDay && waistDay ? 'Σήμερα ζύγιση και μέση' : (weighDay ? 'Σήμερα ζύγιση' : 'Σήμερα μέση'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          // Round 7 (U1-3): η οδηγία της ζύγισης μόνο όσο μένει η ζύγιση· όταν μένει μόνο η μέση, η οδηγία της μέσης
          // (φύλλο «Μέση»: η μεζούρα στο δέρμα, όχι «με τα ίδια ρούχα»).
          Text(
            weighDay && !weighed
                ? 'Το πρωί, μετά την τουαλέτα, πριν φας ή πιεις, με τα ίδια ρούχα.'
                : waistTodayHint,
            key: const ValueKey('today-weigh-hint'),
            style: TextStyle(fontSize: 14, height: 1.4, color: c.text),
          ),
          // Round 12 (R12-D2-5): «·» με τον κανόνα [dotJoin] και ο αριθμός με τη μονάδα του· πριν, στα 360 dp με γράμματα 2×:
          // «Ζύγιση InBody ·» / «82,2 kg» (η γραμμή τελείωνε σε «·»).
          if (weighDay)
            item(weighed, weighed && weighedKg != null ? 'Ζύγιση InBody$dotJoin${dec(weighedKg!)}\u00A0kg' : 'Ζύγιση InBody',
                trailing: weighed ? hm(weighedAt!) : null),
          if (weighDay && !weighed && noPermission)
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 4),
              child: Text(
                bodyNoPermissionShort,
                key: const ValueKey('today-weigh-no-permission'),
                // Το φόντο της κάρτας είναι το απαλό του Σώματος (R2-D-3): χρώμα κειμένου, όχι χρωματιστό.
                style: TextStyle(fontSize: 13.5, height: 1.35, color: c.text),
              ),
            ),
          if (waistDay) item(waistDone, 'Μέση με μεζούρα'),
          if (waistDay && !waistDone)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              // Round 1 (U1a-22): περίγραμμα, όπως το «+ Γράψε τη μέση» του Σώματος· ένα γεμάτο κουμπί ανά οθόνη
              // (μέρα ζύγισης + προπόνησης: το «Ξεκίνα την προπόνηση»).
              // Round 2 (R2-D-3): η κάρτα κάθεται στο φόντο της σελίδας, όχι σε κάρτα: γράμματα στο χρώμα του Σώματος πάνω
              // στο απαλό του φόντο έβγαιναν 4,0–4,4:1 στα φωτεινά θέματα. Γράμματα στο χρώμα κειμένου (≥ 11:1)· περίγραμμα
              // και εικονίδιο μένουν στο χρώμα του Σώματος (≥ 3:1, WCAG 1.4.11).
              // Round 7 (U1-8): περίγραμμα στο ΠΛΗΡΕΣ χρώμα του Σώματος: με 50% διαφάνεια έβγαινε 1,86–1,99:1 στα φωτεινά
              // θέματα και 2,69–3,05:1 στα σκοτεινά· τώρα 4,01–4,40:1 και 6,33–7,55:1 (WCAG 2.x, όλα τα θέματα:
              // /home/claude/scratch/f5r7/border.py).
              child: OutlinedButton.icon(
                key: const ValueKey('today-waist'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: c.text,
                  side: BorderSide(color: c.body, width: 1.5),
                ),
                onPressed: () => openWaistSheet(context, store, now: now),
                icon: Icon(Icons.straighten_rounded, size: 20, color: c.body),
                label: const Text('Γράψε τη μέση'),
              ),
            ),
          if (weighDay && !weighed)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                // Round 2 (R2-D-3): ίδιο φόντο· το κύριο χρώμα της «Αυγής» έβγαινε 4,45:1. Χρώμα κειμένου σε όλα τα θέματα.
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40), foregroundColor: c.text),
                onPressed: () => showMetricInfo(context, metricInfos[K.weight]!),
                child: const Text('Πώς ζυγίζομαι σωστά'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Η θέση της «Άσκηση σήμερα»: ξαναχτίζεται μόνο αυτή όταν αλλάζει η αποθήκη προπονήσεων (έλεγχος premium, S5).
/// Χωρίς κάρτα (ξεκούραση, χωρίς πρόγραμμα): τίποτα, ούτε κενό.
class _TrainingSlot extends StatelessWidget with SelfSpaced {
  const _TrainingSlot({required this.training, required this.now});
  final TrainingStore training;
  final DateTime now;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: training,
        builder: (context, _) => TodayTrainingCard.shows(training, now)
            ? Padding(padding: const EdgeInsets.only(bottom: PageFrame.gap), child: TodayTrainingCard(training: training, now: now))
            : const SizedBox.shrink(key: ValueKey('today-training-none')),
      );
}

/// Round 8 (R8-U1-5): ξαναχτίζει τη «Σήμερα» όταν αλλάζει η μέρα: ένα χρονόμετρο ως 1″ μετά τα επόμενα μεσάνυχτα (όσο
/// η εφαρμογή είναι μπροστά· ακυρώνεται στο παρασκήνιο) και ένας έλεγχος σε κάθε επιστροφή στην εφαρμογή. Τίποτα
/// συνεχές: μία αφύπνιση τη μέρα το πολύ. [enabled]: όχι στα στιγμιότυπα (σταθερή ώρα).
class _DayClock extends StatefulWidget {
  const _DayClock({required this.clock, required this.enabled, required this.builder});
  final DateTime Function() clock;
  final bool enabled;
  final WidgetBuilder builder;

  @override
  State<_DayClock> createState() => _DayClockState();
}

class _DayClockState extends State<_DayClock> with WidgetsBindingObserver {
  Timer? _timer;
  late DateTime _day;

  @override
  void initState() {
    super.initState();
    _day = dayOf(widget.clock());
    if (widget.enabled) {
      WidgetsBinding.instance.addObserver(this);
      _arm();
    }
  }

  void _arm() {
    _timer?.cancel();
    final now = widget.clock();
    final next = DateTime(now.year, now.month, now.day + 1);
    _timer = Timer(next.difference(now) + const Duration(seconds: 1), _check);
  }

  /// Αν άλλαξε η μέρα, νέο χτίσιμο (με το νέο «τώρα»)· και νέο χρονόμετρο για τα επόμενα μεσάνυχτα.
  void _check() {
    if (!mounted) return;
    final day = dayOf(widget.clock());
    if (day != _day) setState(() => _day = day);
    _arm();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.enabled) return;
    if (state == AppLifecycleState.resumed) {
      _check();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
