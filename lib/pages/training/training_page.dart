import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../exercise/ex_data.dart';
import '../../format.dart';
import '../../theme.dart';
import '../privacy_page.dart' show copySensitive;
import '../../data.dart' show HealthStore;
import '../../training/equipment.dart';
import '../../training/walk_stats.dart' show kmValue;
import '../../training/progress.dart';
import '../../trends.dart' show TrendPeriod;
import '../../training/program.dart';
import '../../training/progression.dart' show Change;
import '../../training/session.dart';
import '../../training/training_store.dart';
import '../../training/wear_link.dart';
import '../../widgets.dart';
import 'program_editor.dart';
import 'hr_widgets.dart';
import 'program_paste.dart';
import 'progress_page.dart';
import 'session_page.dart';
import 'training_common.dart';
import 'zone_widgets.dart';

/// Άσκηση › Προπόνηση: η σημερινή προπόνηση, η εβδομάδα, το πρόγραμμα, οι τελευταίες προπονήσεις.
class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key, required this.training, this.now, this.health, this.onOpenTrends});
  final TrainingStore training;
  final DateTime? now;

  /// Για την «Πρόοδο»: σώμα και ξεκούραση από τις «Τάσεις», και μετάβαση σε αυτές.
  final HealthStore? health;
  final VoidCallback? onOpenTrends;

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  late Future<void> _ready = Future.wait([widget.training.load(), ExLibrary.load()]);

  /// Η προπόνηση που διάλεξες από το ⋮ για σήμερα. R8-U3-05: ισχύει μόνο εκείνη τη μέρα και ως να ξεκινήσει η προπόνηση.
  /// R9-U3-06: κρατιέται στην αποθήκη ([TrainingStore.chosenOn]), ώστε η «Σήμερα» να λέει την ίδια.
  String? get _chosenToday => t.chosenOn(_now);

  TrainingStore get t => widget.training;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (!t.ready || ExLibrary.loaded == null) {
          // round1, S7-20: αν η φόρτωση απέτυχε, μήνυμα και «Δοκίμασε ξανά», όχι κύκλος που γυρίζει για πάντα.
          if (snap.hasError && snap.connectionState == ConnectionState.done) {
            final c = Aigaio.of(context);
            return PageFrame(title: 'Προπόνηση', onRefresh: () async {}, left: [
              EmptyCard(
                key: const ValueKey('train-load-error'),
                icon: Icons.error_outline_rounded,
                color: c.bad,
                title: 'Δεν φόρτωσαν οι ασκήσεις',
                text: 'Δοκίμασε ξανά. Αν δεν φορτώσουν, κλείσε και άνοιξε ξανά την εφαρμογή.',
                buttonText: 'Δοκίμασε ξανά',
                onPressed: () => setState(() => _ready = Future.wait([t.load(), ExLibrary.load()])),
              ),
            ]);
          }
          return PageFrame(title: 'Προπόνηση', onRefresh: () async {}, left: const [
            Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          ]);
        }
        return ListenableBuilder(
          listenable: Listenable.merge(
              [t, WearLink.main.ready, WearLink.main.live, WearLink.main.sentLimit, WearLink.main.watchLimit, WearLink.main.watchNewer, WearLink.main.watchSlow]),
          builder: (context, _) => _page(context),
        );
      },
    );
  }

  DateTime get _now => widget.now ?? t.now;

  Widget _page(BuildContext context) {
    final c = Aigaio.of(context);
    final p = t.program;
    final today = _now;
    final cards = <Widget>[];
    final side = <Widget>[];

    if (t.readError) {
      // round1, S6-5 / S9-9: με αρχείο που δεν διαβάστηκε δεν γράφεται τίποτα, άρα δεν προσφέρεται τίποτα που θα χανόταν
      // (επικόλληση προγράμματος, «Ελεύθερη άσκηση», έναρξη): μόνο τι έγινε και τι μπορείς να κάνεις.
      cards.add(EmptyCard(
        key: const ValueKey('train-read-error'),
        icon: Icons.error_outline_rounded,
        color: c.bad,
        title: t.newerFile
            ? 'Ενημέρωσε την εφαρμογή'
            : t.damaged
                ? 'Το αρχείο προπονήσεων χάλασε'
                : 'Δεν διαβάστηκαν οι προπονήσεις',
        text: t.newerFile
            ? 'Οι προπονήσεις γράφτηκαν από νεότερη έκδοση της εφαρμογής. Ως την ενημέρωση δεν γράφεται τίποτα, για να μη χαθεί.'
            : t.damaged
                ? 'Δεν διαβάζεται, όσες φορές κι αν ανοίξει η εφαρμογή, και ως τότε δεν γράφεται καμία προπόνηση. Με το κουμπί, '
                    'το αρχείο μένει στην άκρη μέσα στο κινητό (δεν σβήνεται) και οι προπονήσεις ξεκινούν από την αρχή. Μετά '
                    'μπορείς να φέρεις πίσω τις παλιές από αντίγραφο (Ρυθμίσεις › Επαναφορά από αντίγραφο).'
                : 'Για να μη χαθεί τίποτα, δεν γράφεται καμία αλλαγή, και ό,τι έγινε στο ρολόι περιμένει εκεί.',
        buttonText: t.newerFile ? null : (t.damaged ? 'Κράτα το στην άκρη και συνέχισε' : 'Δοκίμασε ξανά'),
        onPressed: t.newerFile ? null : (t.damaged ? () => _setAside(context) : () => t.retryLoad()),
      ));
      if (t.saveError != null) cards.add(Text(t.saveError!, style: TextStyle(color: c.bad, fontWeight: FontWeight.w600)));
      return PageFrame(title: 'Προπόνηση', onRefresh: () async {}, left: cards);
    }
    if (t.saveError != null) {
      cards.add(Text(t.saveError!, style: TextStyle(color: c.bad, fontWeight: FontWeight.w600)));
    }
    // Αποτέλεσμα από ρολόι νεότερης έκδοσης (V-A-08): περιμένει στο ρολόι.
    if (WearLink.main.watchNewer.value) {
      cards.add(EmptyCard(
        key: const ValueKey('train-watch-newer'),
        icon: Icons.system_update_rounded,
        color: c.exercise,
        title: 'Ενημέρωσε την εφαρμογή στο κινητό',
        text: 'Το ρολόι έχει νεότερη έκδοση. Ό,τι έγινε εκεί περιμένει στο ρολόι και περνά μόλις ενημερωθεί το κινητό.',
      ));
    }

    final cur = t.current;
    if (cur != null) cards.add(t.isStale(cur) ? _forgottenCard(context, cur) : _resumeCard(context, cur));
    final walk = _liveWalk();
    if (walk != null) cards.add(_walkCard(context, walk));

    if (p == null) {
      cards.add(_noProgram(context));
      if (cur == null) cards.add(_freeCard(context));
    } else {
      // 13/11: και η προπόνηση που διάλεξες με το χέρι παίρνει τα λεπτά της εβδομάδας (πλάνο περπατήματος).
      final chosen = _chosenToday;
      final picked = chosen == null ? null : p.workout(chosen);
      final w = chosen == null ? p.forDay(today) : (picked == null ? null : p.at(picked, today));
      cards.add(_todayCard(context, p, w, today, chosen: chosen != null));
      final strengthDone = [for (final x in t.sessions.reversed) if (x.finished && !x.isCardio) x];
      final lastStrength = strengthDone.isEmpty ? null : strengthDone.first;
      if (lastStrength != null) cards.add(_lastCard(context, lastStrength));
      if (cur == null) cards.add(_freeCard(context));
      cards.add(_weekCard(context, p, today));
      side.add(_programCard(context, p));
    }
    if (widget.health != null) side.add(ZoneCard(health: widget.health!, training: t, now: _now));
    side.add(WeekMovementCard(training: t, now: _now));
    side.add(_progressCard(context));
    final recent = [for (final s in t.sessions.reversed) if (s.finished) s].take(6).toList();
    if (recent.isNotEmpty) side.add(_recentCard(context, recent));
    // Σχέδια 12/11 (4α): η ζώνη περπατήματος αντί για το όριο γιατρού. Το όριο φαίνεται μόνο αν υπάρχει (νικά πάντα).
    if (t.hrLimit != null) side.add(_hrLimitCard(context));
    // Προπονήσεις που δεν διαβάστηκαν (V-A-10): κρατιούνται στο αρχείο, όχι χαμένες· μόνο μια μικρή σημείωση.
    final badHr = t.sessions.where((s) => s.hrBad != null).length;
    if (t.quarantine.isNotEmpty || badHr > 0) {
      final n = t.quarantine.length;
      side.add(Padding(
        key: const ValueKey('train-quarantine'),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          [
            if (n > 0)
              n == 1
                  ? '1 καταγραφή προπόνησης δεν διαβάστηκε· κρατιέται στο αρχείο και μπαίνει στο αντίγραφο.'
                  : '$n καταγραφές προπόνησης δεν διαβάστηκαν· κρατιούνται στο αρχείο και μπαίνουν στο αντίγραφο.',
            if (badHr > 0)
              badHr == 1
                  ? 'Οι παλμοί 1 προπόνησης δεν διαβάστηκαν· το αρχείο τους κρατήθηκε στην άκρη.'
                  : 'Οι παλμοί $badHr προπονήσεων δεν διαβάστηκαν· τα αρχεία τους κρατήθηκαν στην άκρη.',
          ].join(' '),
          style: TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary),
        ),
      ));
    }

    return PageFrame(
      title: 'Προπόνηση',
      onRefresh: () async {},
      left: cards,
      right: side,
    );
  }

  // ---------------------------------------------------------------- κάρτες
  Widget _resumeCard(BuildContext context, Session s) {
    final c = Aigaio.of(context);
    return AppCard(
      onTap: () => _openSession(context),
      child: Row(children: [
        IconBadge(Icons.play_arrow_rounded, c.exercise),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s.name} σε εξέλιξη', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
            Text('Από ${sameDay(s.start, _now) ? '' : '${shortDayDate(s.start)} '}${hm(s.start)} ·\u00A0${s.setsDone} σετ',
                style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
          ]),
        ),
        FilledButton(
          key: const ValueKey('train-resume'),
          style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid),
          onPressed: () => _openSession(context),
          child: const Text('Συνέχεια'),
        ),
      ]),
    );
  }

  /// «Ξεχασμένη προπόνηση;» (έλεγχος 9/11, V-A-09): ανοιχτή χωρίς κίνηση εδώ και 3 ώρες. Ένα πάτημα «Τέλος (στις 19:22)» με
  /// το τελευταίο ✓ ως τέλος· ποτέ διάρκεια 20 ωρών. Χωρίς κανένα σετ: «Σβήσιμο».
  Widget _forgottenCard(BuildContext context, Session s) => ForgottenWorkout(
        key: const ValueKey('train-forgotten'),
        training: t,
        session: s,
        now: _now,
        watchReady: WearLink.main.ready.value,
        // R8-A8-3: όπως το «Ξεκίνα»: ανοίγει και η εφαρμογή στο ρολόι, για να «μπει» ξανά στην προπόνηση.
        onResume: () {
          WearLink.main.openWatch();
          _openSession(context);
        },
      );

  /// «Πρόοδος» (9/11): οι δύο πιο ξεκάθαρες αλλαγές (μόνο από την προπόνηση· το σώμα φαίνεται μέσα στη σελίδα).
  Widget _progressCard(BuildContext context) {
    final c = Aigaio.of(context);
    // Ίδια περίοδος με τη σελίδα «Πρόοδος» (3 μήνες, έλεγχος 9/11, V-B-10).
    final walk = walkProgress(t.sessions, _now, TrendPeriod.quarter);
    final strength = strengthProgress(t.sessions, _now, TrendPeriod.quarter);
    final top = progressHighlights(walk, strength, const []).take(2).map((e) => e.$1).toList();
    // round1, U6-12: μία αλλαγή ανά γραμμή (πριν «… · Ρυθμός: 13:09 →» / «12:43 /km»).
    final sub = top.isNotEmpty
        ? top.join('\n')
        : (walk.insufficient && strength.isEmpty
            ? 'Η πρώτη σύγκριση μετά από λίγες εβδομάδες προπόνησης και περπατήματος.'
            : 'Καμία ξεκάθαρη αλλαγή τους τελευταίους 3 μήνες.');
    return AppCard(
      key: const ValueKey('train-progress'),
      onTap: () => Navigator.of(context).push(ProgressPage.route(t, health: widget.health, onOpenTrends: widget.onOpenTrends, now: widget.now)),
      child: Row(children: [
        IconBadge(Icons.trending_up_rounded, c.exercise),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Πρόοδος', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
            Text(sub, style: TextStyle(fontSize: 13.5, height: 1.35, color: c.textSecondary)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: c.textSecondary),
      ]),
    );
  }

  /// «Ελεύθερη άσκηση» (9/11): χωρίς πρόγραμμα, διαλέγεις τις ασκήσεις τη στιγμή. Το ρολόι ακολουθεί όπως πάντα.
  Widget _freeCard(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      key: const ValueKey('train-free'),
      onTap: () => _startFree(context),
      child: Row(children: [
        IconBadge(Icons.add_rounded, c.exercise),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ελεύθερη άσκηση', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
            // round1, U6-11: σε μία γραμμή και στα 360 dp (πριν «…μία-» / «μία.»). Round 2 (R2-U2-04): το «…εκείνη την ώρα.»
            // (234 dp με Inter 13,5) δεν χωρούσε στα ≈ 224 dp του 360 και άφηνε «ώρα.» μόνη της· τώρα 196 dp, και οι δύο
            // τελευταίες λέξεις μαζί αν ποτέ σπάσει (στενή στήλη, μεγάλα γράμματα).
            Text('Διαλέγεις ασκήσεις επί\u00A0τόπου.',
                key: const ValueKey('train-free-sub'), style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: c.textSecondary),
      ]),
    );
  }

  void _startFree(BuildContext context) {
    if (t.current != null) return;
    t.startFree();
    WearLink.main.openWatch();
    _openSession(context);
  }

  Widget _noProgram(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Δεν υπάρχει πρόγραμμα ακόμα', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text)),
        const SizedBox(height: 6),
        Text('Ζήτα από τον Claude να σου φτιάξει ένα και επικόλλησέ το, ή φτιάξ’ το μόνος σου από τη βιβλιοθήκη.',
            style: TextStyle(fontSize: 15, height: 1.45, color: c.textSecondary)),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('train-paste'),
          style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(48)),
          onPressed: () => Navigator.of(context).push(ProgramPastePage.route(t)),
          icon: const Icon(Icons.content_paste_rounded),
          label: const Text('Επικόλληση προγράμματος'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('train-new'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => Navigator.of(context).push(ProgramEditorPage.route(t, null)),
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('Φτιάξε το μόνος σου'),
        ),
        // Και χωρίς πρόγραμμα να φαίνεται ότι το ρολόι βρέθηκε (9/11).
        if (WearLink.main.ready.value) ...[
          const SizedBox(height: 10),
          Row(key: const ValueKey('train-watch-ready'), children: [
            Icon(Icons.watch_rounded, size: 16, color: c.good),
            const SizedBox(width: 4),
            Text('ρολόι έτοιμο', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.good)),
          ]),
        ],
      ]),
    );
  }

  /// ⋮ του προγράμματος (σχέδια 9/11, 6α): αλλαγές, επικόλληση νέου, αντιγραφή, και άλλη προπόνηση για σήμερα.
  Widget _programMenu(BuildContext context, Program p, {Workout? w, required String key, bool picks = true}) {
    final others = [if (picks) for (final x in p.workouts) if (x.id != w?.id) x];
    return PopupMenuButton<String>(
      key: ValueKey(key),
      tooltip: 'Πρόγραμμα',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) {
        switch (v) {
          case 'edit':
            Navigator.of(context).push(ProgramEditorPage.route(t, p));
          case 'paste':
            Navigator.of(context).push(ProgramPastePage.route(t));
          case 'export':
            _export(context);
          default:
            if (v.startsWith('pick:')) setState(() => t.choose(v.substring(5), _now));
        }
      },
      itemBuilder: (_) => [
        for (final x in others)
          PopupMenuItem(value: 'pick:${x.id}', key: ValueKey('train-pick-${x.id}'), child: Text('Σήμερα: ${x.name}')),
        if (others.isNotEmpty) const PopupMenuDivider(),
        const PopupMenuItem(value: 'edit', key: ValueKey('train-edit'), child: Text('Αλλαγές στο πρόγραμμα')),
        const PopupMenuItem(value: 'paste', key: ValueKey('train-paste-new'), child: Text('Επικόλληση νέου')),
        const PopupMenuItem(value: 'export', key: ValueKey('train-export'), child: Text('Αντιγραφή για τον Claude')),
      ],
    );
  }

  bool _allItems = false;

  Widget _todayCard(BuildContext context, Program p, Workout? w, DateTime today, {bool chosen = false}) {
    final c = Aigaio.of(context);
    final dayName = weekdayLong[today.weekday]!;
    final children = <Widget>[];
    final title = TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.15, color: c.text);
    final aux = TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary);
    // R8-U3-05: να φαίνεται ότι η σημερινή είναι επιλογή σου, με επιστροφή στο πρόγραμμα με ένα πάτημα.
    if (chosen) {
      // Wrap: με μεγάλα γράμματα το κουμπί πάει από κάτω, ποτέ ξεχείλισμα.
      children.add(Wrap(key: const ValueKey('train-chosen'), spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Τη διάλεξες εσύ για σήμερα.', style: aux),
        TextButton(
          key: const ValueKey('train-chosen-reset'),
          style: TextButton.styleFrom(foregroundColor: c.exercise, minimumSize: const Size(0, 44)),
          onPressed: () => setState(() => t.choose(null, _now)),
          child: const Text('Πίσω στο πρόγραμμα'),
        ),
      ]));
    }
    if (w == null && p.notStarted(today)) {
      // R7-A6-6: πριν από την έναρξη του προγράμματος καμία προπόνηση του (πριν: το Σάββατο έδειχνε ήδη «Κάτω μέρος 2»).
      final f = p.from!;
      children.add(Text('Το πρόγραμμα ξεκινά ${onDay(f)}',
          key: const ValueKey('train-not-started'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.text)));
      children.add(Text('Ως τότε, αν θες, διάλεξε προπόνηση από τις τρεις τελείες, πάνω δεξιά.', style: TextStyle(fontSize: 14, color: c.textSecondary)));
    } else if (w == null) {
      children.add(Text('$dayName: ξεκούραση', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.text)));
      children.add(Text('Αν θες, διάλεξε προπόνηση από τις τρεις τελείες, πάνω δεξιά.', style: TextStyle(fontSize: 14, color: c.textSecondary)));
    } else if (w.isCardio) {
      final cardio = w.cardio!;
      children.addAll([
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(cardio.name, maxLines: 1, style: title)),
        Text(
            // Round 10 (R10-B8-B1): ίδιος κανόνας με την κάρτα της Σήμερα (αδιάσπαστο κενό στο «30 λεπτά»). Round 11 (R11-C2-3):
            // το «·» με τον κανόνα [dotJoin]: η γραμμή δεν τελειώνει ποτέ σε «·».
            ['${cardio.minutes}\u00A0λεπτά', if (p.planWeekText(cardio, today) case final wk?) wk, if (cardio.note != null && cardio.note!.trim().isNotEmpty) cardio.note!.trim()]
                .join(dotJoin),
            key: const ValueKey('train-cardio-line'),
            style: aux),
        RoutineButton(w),
        ProgramNotesButton(p, workout: w),
        const SizedBox(height: 12),
        Text(
            WearLink.main.ready.value
                ? 'Ξεκινά από το ρολόι: πάτα «${cardio.name}», με παλμούς και απόσταση. Αν έχεις μαζί το κινητό, το βλέπεις ζωντανά εδώ.'
                : 'Ξεκινά από το ρολόι, με παλμούς και απόσταση, όταν μπει η εφαρμογή του ρολογιού. Ως τότε τα βήματα μετριούνται στην «Κίνηση».',
            style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary)),
      ]);
    } else {
      children.add(FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(w.name, maxLines: 1, style: title)));
      // Round 11 (R11-C2-2): όπως η γραμμή του περπατήματος και η κάρτα της Σήμερα: «·» με τον κανόνα [dotJoin] και ο
      // αριθμός με τη λέξη του (πριν, με μεγάλα γράμματα: «6 ασκήσεις · περίπου 55» / «λεπτά»).
      children.add(Text('${countText(w.items.length, 'άσκηση', 'ασκήσεις')}${dotJoin}περίπου ${w.minutes}\u00A0λεπτά', style: aux));
      if (w.note != null) children.add(Text(w.note!, style: TextStyle(fontSize: 14, color: c.textSecondary)));
      children.add(RoutineButton(w));
      // round1, S7-11: η σημείωση του προγράμματος (κανόνες ασφάλειας) ένα πάτημα μακριά.
      children.add(ProgramNotesButton(p, workout: w));
      final shown = _allItems || w.items.length <= 6 ? w.items : w.items.take(5).toList();
      for (var n = 0; n < shown.length; n++) {
        final plan = shown[n];
        // round1, S7-03 (f6a): η άσκηση που μπαίνει σήμερα στη θέση (ίσως η πιο δύσκολη παραλλαγή που διάλεξες).
        final item = t.itemToday(plan);
        final tg = t.targetFor(item);
        final k = item.kind;
        // Σχέδια 9/11 (6α): «ανεβαίνει» αντί για «↑», σε λέξη· +1 επανάληψη γράφεται στη γραμμή του στόχου. Η πιο δύσκολη
        // παραλλαγή είναι πια πρόταση (S7-03), όχι αυτόματη αλλαγή.
        final (String, Color)? pill = switch (tg.change) {
          Change.up => ('ανεβαίνει', c.good),
          Change.variant => ('νέα παραλλαγή', c.exercise),
          Change.down || Change.back => ('πιο ελαφρύ', c.textSecondary),
          Change.pain => ('πόνεσε', c.warn),
          _ => null,
        };
        // round1, U6-20: αδιάσπαστα κενά μέσα στους αριθμούς («11,\u00A011,\u00A010», «+1\u00A0επανάληψη»).
        final reps = repsList(tg.reps).replaceAll(', ', ',\u00A0');
        final more = tg.change == Change.more ? ' ·\u00A0+1\u00A0επανάληψη' : '';
        children.add(Container(
          key: ValueKey('train-item-${plan.ex}'),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: n < shown.length - 1 ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: exName(item.ex), style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                  ]),
                  style: const TextStyle(fontSize: 15, height: 1.35),
                ),
              ),
              if (pill != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: c.tint(pill.$2), borderRadius: BorderRadius.circular(999)),
                  child: Text(pill.$1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pill.$2)),
                ),
              ],
            ]),
            Text('${item.sets} σετ × ${item.lo == item.hi ? '${item.lo}' : '${item.lo}–${item.hi}'} ·\u00A0άφησε ${item.rir}', style: aux),
            if (isBand(k) && (tg.load ?? 0) > 0)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 3), child: BandDots(tg.load, size: 14)),
                Flexible(child: Text('${bandName(tg.load!)} ·\u00A0$reps$more', style: TextStyle(fontSize: 14, color: c.text, fontFeatures: tabular))),
              ])
            else
              Text('${hasLoad(k) ? '${loadLabel(k, tg.load)} ·\u00A0' : ''}$reps$more', style: TextStyle(fontSize: 14, color: c.text, fontFeatures: tabular)),
          ]),
        ));
      }
      if (shown.length < w.items.length) {
        final rest = w.items.length - shown.length;
        children.add(Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('train-more-items'),
            style: TextButton.styleFrom(foregroundColor: c.textSecondary, padding: EdgeInsets.zero),
            onPressed: () => setState(() => _allItems = true),
            child: Text(rest == 1 ? 'και 1 ακόμα άσκηση' : 'και $rest ακόμα ασκήσεις'),
          ),
        ));
      }
      children.add(const SizedBox(height: 12));
      final can = t.current == null;
      children.add(FilledButton(
        key: const ValueKey('train-start'),
        style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(52)),
        onPressed: can ? () => _start(context, w) : null,
        child: Text(t.current != null ? 'Υπάρχει προπόνηση σε εξέλιξη' : 'Ξεκίνα την προπόνηση',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ));
      children.add(const SizedBox(height: 12));
      children.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.directions_walk_rounded, size: 18, color: c.textSecondary),
        const SizedBox(width: 6),
        Expanded(child: Text('Για περπάτημα: στο ρολόι πάτα\u00A0«Περπάτημα».', style: aux)),
      ]));
    }
    return AppCard(
      key: const ValueKey('train-today'),
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: CardHeader(icon: Icons.fitness_center_rounded, title: 'Σήμερα', color: c.exercise)),
          _programMenu(context, p, w: w, key: 'train-today-more'),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ]),
    );
  }

  Widget _weekCard(BuildContext context, Program p, DateTime today) {
    final c = Aigaio.of(context);
    final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final week = t.weekOf(today);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Η εβδομάδα', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 10),
        Row(children: [
          for (var d = 1; d <= 7; d++)
            Expanded(child: () {
              final day = DateTime(monday.year, monday.month, monday.day + d - 1);
              // R9-A6-6: πριν από την έναρξη του προγράμματος καμία προπόνηση του, όπως η κάρτα «Σήμερα» ([Program.forDay]).
              final w = p.notStarted(day) ? null : p.workout(p.days[d]);
              final ds = [for (final s in week) if (s.finished && sameDay(s.start, day)) s];
              // round1, S6-13: «✓» μόνο όταν έγινε αυτό που έλεγε η μέρα (βάρη σε μέρα βαρών, περπάτημα σε μέρα
              // περπατήματος)· ένα πρωινό περπάτημα δεν «κλείνει» τη μέρα των βαρών. Ό,τι άλλο έγινε: μικρή τελεία.
              // Ό,τι έγινε πράγματι (μπορεί να είναι άλλη προπόνηση βαρών από το πρόγραμμα) δείχνεται με το όνομά της.
              final match = [for (final s in ds) if (w == null || w.isCardio == s.isCardio) s];
              final done = match.isNotEmpty;
              final other = !done && ds.isNotEmpty;
              final doneW = done ? p.workout(match.last.workout) : null;
              final shownW = doneW ?? w;
              final isToday = sameDay(day, today);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isToday ? c.tint(c.exercise) : c.background,
                  borderRadius: BorderRadius.circular(10),
                  border: isToday ? Border.all(color: c.exercise, width: 1.5) : null,
                ),
                child: Column(children: [
                  Text(dayShort[d]!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
                  const SizedBox(height: 2),
                  // round1, U5-27 / U5-18: σύντομο ελληνικό όνομα αντί για τον εσωτερικό κωδικό («UA»), εικονίδιο για το
                  // περπάτημα, και ✓ ως εικονίδιο (το γράμμα δεν υπάρχει στη γραμματοσειρά).
                  SizedBox(
                    height: 18,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(key: ValueKey('train-week-$d'), mainAxisSize: MainAxisSize.min, children: [
                        if (shownW == null && !done)
                          Text('—', style: TextStyle(fontSize: 12, color: c.textSecondary))
                        else if (shownW != null && shownW.isCardio)
                          Icon(Icons.directions_walk_rounded, size: 15, color: done ? c.good : c.textSecondary, semanticLabel: 'Περπάτημα')
                        else if (shownW != null)
                          Text(shortWorkoutName(shownW),
                              maxLines: 1,
                              style: TextStyle(fontSize: 12, color: done ? c.good : c.textSecondary, fontWeight: done ? FontWeight.w700 : FontWeight.w500)),
                        if (done) Icon(Icons.check_rounded, size: 14, color: c.good, semanticLabel: 'έγινε'),
                        if (other) ...[const SizedBox(width: 2), Icon(Icons.circle, size: 6, color: c.textSecondary, semanticLabel: 'έγινε άλλη άσκηση')],
                      ]),
                    ),
                  ),
                ]),
              );
            }()),
        ]),
      ]),
    );
  }

  Widget _programCard(BuildContext context, Program p) {
    final c = Aigaio.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Το πρόγραμμα', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text))),
          // Σχέδια 9/11 (6α): τα τρία κουμπιά του προγράμματος στο ⋮.
          _programMenu(context, p, key: 'train-program-more', picks: false),
        ]),
        const SizedBox(height: 4),
        // Round 2 (R2-U2-03): η κάρτα έχει 4 dp δεξιά μόνο για το ⋮· τα κείμενα από κάτω παίρνουν άλλα 12, ώστε να έχουν
        // 16 dp και από τις δύο πλευρές (πριν η σημείωση έφτανε 8 dp από την άκρη).
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(p.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text)),
            // round1, U6-20: «ισχύει από Παρ\u00A013/11» (όχι διπλό «από», όχι ημερομηνία σε δύο γραμμές).
            Text(
              'Έκδοση ${p.version} ·\u00A0${p.author == 'claude' ? 'από τον Claude' : 'δικό σου'}${p.from == null ? '' : ' ·\u00A0ισχύει από ${shortDayDate(p.from!).replaceAll(' ', '\u00A0')}'}',
              style: TextStyle(fontSize: 13.5, color: c.textSecondary),
            ),
            // round1, S7-11 / U6-25: η σημείωση του προγράμματος (κανόνες ασφάλειας) μένει ορατή μετά την επικόλληση.
            if (p.note != null && p.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(p.note!.trim(),
                  key: const ValueKey('train-program-note'), style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary)),
            ],
          ]),
        ),
      ]),
    );
  }

  /// «Τελευταία φορά · Πέμ 5/11» (σχέδια 9/11, 6α): διάρκεια, σετ, σύνολο κιλών· πάτημα → σύνοψη.
  Widget _lastCard(BuildContext context, Session s) {
    final c = Aigaio.of(context);
    Widget stat(String v, String unit, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
                  if (unit.isNotEmpty) TextSpan(text: ' $unit', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textSecondary)),
                ]),
                maxLines: 1,
                style: const TextStyle(fontFeatures: tabular),
              ),
            ),
            Text(label, style: TextStyle(fontSize: 13, color: c.textSecondary)),
          ]),
        );
    return AppCard(
      key: const ValueKey('train-last'),
      onTap: () => Navigator.of(context).push(SummaryPage.route(t, s)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // round1, U6-20: η ημερομηνία ως δεύτερη γραμμή (πριν «Τετ» / «11/11» σε δύο γραμμές).
        CardHeader(
          icon: Icons.check_rounded,
          title: 'Τελευταία φορά',
          subtitle: shortDayDate(s.start),
          color: c.good,
          trailing: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
        ),
        const SizedBox(height: 10),
        Row(children: [
          // round1, U5-06 / U6-06: διάρκεια σε λέξη («60 λεπτά», όχι «60 λ»).
          stat('${s.duration.inMinutes}', s.duration.inMinutes == 1 ? 'λεπτό' : 'λεπτά', 'διάρκεια'),
          stat('${s.setsDone}', '', 'σετ'),
          stat(s.volume > 0 ? thousands(s.volume.round()) : '—', s.volume > 0 ? 'kg' : '', 'σύνολο κιλών'),
        ]),
      ]),
    );
  }

  Widget _recentCard(BuildContext context, List<Session> recent) {
    final c = Aigaio.of(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Τελευταίες προπονήσεις', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 4),
        for (final s in recent)
          InkWell(
            onTap: () => Navigator.of(context).push(SummaryPage.route(t, s)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${shortDayDate(s.start)} ·\u00A0${s.name}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                    // round1, U5-06 / U5-18: διάρκεια σε λέξεις και «μέσοι παλμοί» αντί για «♥» (λείπει από τη γραμματοσειρά).
                    Text(recentWorkoutLine(s), style: TextStyle(fontSize: 13, color: c.textSecondary)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              ]),
            ),
          ),
      ]),
    );
  }

  /// Όριο παλμών από τον γιατρό: αν υπάρχει, το ρολόι δονείται όσο μετρά άσκηση και οι παλμοί μείνουν πάνω του.
  /// Έλεγχος 9/11 (V-B-05, V-A-05): όχι απόλυτη υπόσχεση, και φαίνεται αν το όριο έφτασε στο ρολόι.
  Widget _hrLimitCard(BuildContext context) {
    final c = Aigaio.of(context);
    final hr = t.hrLimit;
    final link = WearLink.main;
    final sent = hr != null && link.sentLimit.value == '$hr';
    // Έλεγχος 9/11 (V-A-06): «✓» μόνο όταν το ίδιο το ρολόι πει ότι έχει αυτό το όριο.
    final acked = link.watchLimit.value;
    final (String, Color, IconData)? watch = hr == null
        ? (acked != null && acked != 'null'
            ? ('Το ρολόι έχει ακόμα όριο $acked: άνοιξε την εφαρμογή στο ρολόι για να το σβήσει.', c.warn, Icons.watch_rounded)
            : null)
        : acked == '$hr'
            // round1, U5-18 / U6-05: το «✓» ως γράμμα έλειπε από τη γραμματοσειρά· εικονίδιο και λέξεις.
            ? ('Το ρολόι έχει το όριο $hr', c.good, Icons.check_circle_rounded)
            : sent
                ? ('Στάλθηκε· θα επιβεβαιωθεί μόλις ανοίξεις την εφαρμογή στο ρολόι (ή την ενημερώσεις εκεί).', c.textSecondary, Icons.watch_rounded)
                : link.ready.value
                    ? ('Στέλνεται στο ρολόι…', c.textSecondary, Icons.watch_rounded)
                    : ('Το ρολόι δεν βρέθηκε τώρα: δεν ξέρω αν έχει αυτό το όριο.', c.warn, Icons.watch_rounded);
    return AppCard(
      key: const ValueKey('train-hrlimit'),
      onTap: () => _editHrLimit(context),
      child: Row(children: [
        IconBadge(Icons.favorite_rounded, c.heart),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Όριο παλμών από τον γιατρό', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
            Text(hr != null ? '$hr bpm ·\u00A0δόνηση στο ρολόι όσο μετρά άσκηση' : 'Κανένα. Πάτα αν σου δώσει ο γιατρός.',
                style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
            // Έλεγχος του γ2 (S1): το ρολόι στέλνει παλμούς αργά με σβηστή οθόνη· να το ξέρεις πριν από την άσκηση.
            if (hr != null && link.watchSlow.value)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(slowAlarmText, key: const ValueKey('train-hr-slow'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.warn)),
              ),
            if (watch != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(key: const ValueKey('train-hr-watch'), crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 1), child: Icon(watch.$3, size: 15, color: watch.$2)),
                  const SizedBox(width: 4),
                  Expanded(child: Text(watch.$1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: watch.$2))),
                ]),
              ),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: c.textTertiary),
      ]),
    );
  }

  // ---------------------------------------------------------------- ενέργειες
  Future<void> _editHrLimit(BuildContext context) => editDoctorLimit(context, t);

  Future<void> _start(BuildContext context, Workout w) async {
    // R8-U3-05 / R9-U3-06: η επιλογή από το ⋮ τελειώνει με την προπόνηση που ξεκινά ([TrainingStore.start]).
    t.start(w);
    // Ανοίγει και η εφαρμογή στο ρολόι (παλμοί, ✓ στον καρπό), αν υπάρχει.
    WearLink.main.openWatch();
    _openSession(context);
  }

  /// Περπάτημα που τρέχει τώρα στο ρολόι (ήρθε μήνυμα τα τελευταία 30″).
  Map<String, dynamic>? _liveWalk() {
    final l = WearLink.main.live.value;
    if (l == null) return null;
    final at = (l['at'] as num?)?.toInt() ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - at > 30000) return null;
    return l;
  }

  Widget _walkCard(BuildContext context, Map<String, dynamic> l) {
    final c = Aigaio.of(context);
    final sec = (l['sec'] as num?)?.toInt() ?? 0;
    final m = (l['m'] as num?)?.toDouble() ?? 0;
    final steps = (l['steps'] as num?)?.toInt() ?? 0;
    final bpm = (l['bpm'] as num?)?.toInt() ?? 0;
    final time = clock(sec);
    String pace() => m < 50 || sec <= 0 ? '—' : paceText(sec / (m / 1000));

    Widget stat(String v, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.text)),
            Text(label, style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
          ]),
        );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            l['rec'] == true
                ? 'ΠΕΡΠΑΤΗΜΑ ·\u00A0ΛΕΠΤΟ ΑΠΟΚΑΤΑΣΤΑΣΗΣ'
                : l['paused'] == true
                    ? 'ΠΕΡΠΑΤΗΜΑ ΣΤΟ ΡΟΛΟΪ ·\u00A0ΣΕ ΠΑΥΣΗ'
                    : 'ΠΕΡΠΑΤΗΜΑ ΣΤΟ ΡΟΛΟΪ ·\u00A0ΖΩΝΤΑΝΑ',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: l['paused'] == true ? c.exercise : c.textSecondary)),
        const SizedBox(height: 8),
        if (bpm > 0)
          ...[HrBar(bpm: bpm, limit: t.hrLimit), const SizedBox(height: 10)]
        // Με όριο και χωρίς παλμούς (μετά την αναμονή): κεχριμπάρι «δεν σε προσέχει», όχι απλώς να χάνεται η γραμμή
        // (έλεγχος γ2, W2-15· όπως η κάρτα της Σήμερα).
        else if (t.hrLimit != null && sec >= hrWaitSeconds)
          ...[HrStale(limit: t.hrLimit), const SizedBox(height: 10)],
        Row(children: [stat(time, 'χρόνος'), stat(m > 0 ? (m / 1000).toStringAsFixed(2).replaceAll('.', ',') : '—', 'km')]),
        const SizedBox(height: 8),
        Row(children: [stat(pace(), 'ρυθμός'), stat(steps > 0 ? thousands(steps) : '—', 'βήματα')]),
        const SizedBox(height: 6),
        Text('Τελειώνει από το ρολόι. Μόλις τελειώσει, γράφεται εδώ.', style: TextStyle(fontSize: 13, color: c.textSecondary)),
      ]),
    );
  }

  void _openSession(BuildContext context) => Navigator.of(context).push(SessionPage.route(t));

  /// round1, S9-9: «Κράτα το στην άκρη και συνέχισε», με επιβεβαίωση. Το αρχείο μετονομάζεται, δεν σβήνεται.
  Future<void> _setAside(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Στην άκρη το αρχείο;'),
        content: const Text('Οι προπονήσεις και το πρόγραμμα ξεκινούν από την αρχή. Το χαλασμένο αρχείο μένει στο κινητό. '
            'Τις παλιές προπονήσεις τις φέρνεις πίσω από αντίγραφο, αν έχεις.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Άκυρο')),
          FilledButton(key: const ValueKey('train-set-aside-ok'), onPressed: () => Navigator.pop(context, true), child: const Text('Ναι, συνέχισε')),
        ],
      ),
    );
    if (ok != true) return;
    final done = await t.setAsideUnreadable();
    if (done || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Δεν έγινε. Κλείσε και άνοιξε ξανά την εφαρμογή.')));
  }

  Future<void> _export(BuildContext context) async {
    await copySensitive(t.exportForClaude(names: exNames()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Αντιγράφηκε. Επικόλλησέ το στη συζήτηση με τον Claude.')));
  }
}

/// Η σταθερή πρόταση για τα φάρμακα στη φόρμα ορίου (έλεγχος 9/11, V-B-06· ESC 2020, Pelliccia κ.ά., Eur Heart J 2021:
/// οι παλμοί προπόνησης ισχύουν με β-αναστολέα μόνο αν η ικανότητα μετρήθηκε με το φάρμακο).
/// Έλεγχος του #90 (Σ-7): να μη διαβάζεται σαν «σβήσε το όριο του γιατρού»· ρωτάς τον γιατρό, και πάντα και με την κούραση.
const hrLimitBetaBlockerText = 'Αν παίρνεις β-αναστολέα, το όριο ισχύει μόνο αν βγήκε από τεστ κοπώσεως που έγινε με το '
    'φάρμακο· αλλιώς ρώτα τον γιατρό. Και πάντα πήγαινε και με την κούραση: να μπορείς να μιλάς.';

/// «Πότε δεν έρχεται δόνηση» (ⓘ της φόρμας ορίου): τι κάνει το ρολόι και τι το κινητό, χωριστά.
const hrLimitMoreText = 'Το ρολόι δονείται μόνο όσο μετρά άσκηση: περπάτημα ή προπόνηση που ξεκίνησε στο ρολόι, ή «Παλμοί εδώ» '
    'στην προπόνηση του κινητού.\n'
    '• Στο ρολόι: αν δεν μετρά παλμούς (χαλαρό λουράκι, λείπει η άδεια παλμών του ρολογιού), δονείται μία φορά για να το '
    'ξέρεις (μία μακριά και δύο σύντομες· τρεις σύντομες αν χάθηκαν στη μέση). Πάνω από το όριο: τρεις μακριές.\n'
    '• Στο κινητό: αν δεν φτάνουν παλμοί (ρολόι μακριά ή χωρίς «Παλμοί εδώ»), το γράφει στην οθόνη της προπόνησης. Αν το '
    'ρολόι δεν μετρά άσκηση, δεν έρχεται καμία δόνηση.\n'
    'Στα βάρη ο καρπός συχνά μετρά λιγότερους παλμούς από τους πραγματικούς.';

/// Όριο παλμών από γιατρό: το φύλλο αλλαγής (από την Προπόνηση, όταν υπάρχει όριο, και από τις Ρυθμίσεις ›
/// Για προχωρημένους).
Future<void> editDoctorLimit(BuildContext context, TrainingStore t) async {
  final r = await showModalBottomSheet<_HrChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _HrLimitSheet(current: t.hrLimit),
  );
  if (r != null) t.setHrLimit(r.hr);
}

/// Τι επέλεξε στο φύλλο ορίου: αριθμός ή κανένα όριο (null).
class _HrChoice {
  const _HrChoice(this.hr);
  final int? hr;
}

/// Όριο παλμών: αριθμός 80–220 (κάτω από 100 ζητά επιβεβαίωση), ή «Χωρίς όριο».
class _HrLimitSheet extends StatefulWidget {
  const _HrLimitSheet({this.current});
  final int? current;

  @override
  State<_HrLimitSheet> createState() => _HrLimitSheetState();
}

class _HrLimitSheetState extends State<_HrLimitSheet> {
  late final _hr = TextEditingController(text: widget.current?.toString() ?? '');
  bool _lowOk = false;
  bool _more = false;

  @override
  void dispose() {
    _hr.dispose();
    super.dispose();
  }

  int? get _value => int.tryParse(_hr.text.trim());

  String? get _error {
    final v = _value;
    if (_hr.text.trim().isEmpty) return null;
    if (v == null || v < 80 || v > 220) return 'Γράψε αριθμό από 80 έως 220';
    return null;
  }

  bool get _valid {
    final v = _value;
    return v != null && v >= 80 && v <= 220 && (v >= 100 || _lowOk);
  }

  // Round 1 (U5-30, αίτημα f9 → f6b): η σελίδα/το φύλλο ανοίγει με push, έξω από το ExerciseTheme της κατηγορίας·
  // χωρίς αυτό διακόπτες και δευτερεύοντα κουμπιά έβγαιναν μπλε δίπλα στα πορτοκαλί.
  @override
  Widget build(BuildContext context) => ExerciseTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final v = _value;
    final askLow = v != null && v >= 80 && v < 100;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Όριο παλμών από τον γιατρό', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
            const SizedBox(height: 6),
            // Έλεγχος 9/11 (V-B-05, V-B-06): όχι απόλυτη υπόσχεση· πρώτα πώς νιώθεις· μία σταθερή πρόταση για β-αναστολέα
            // (ESC 2020, Pelliccia κ.ά.). Οι λεπτομέρειες πίσω από το ⓘ, για να μη γεμίζει το φύλλο.
            Text('Αν σου δώσει αριθμό, γράψ’ τον εδώ. Όσο το ρολόι μετρά άσκηση (βάρη ή περπάτημα), δονείται όταν οι παλμοί '
                'φτάσουν ή ξεπεράσουν τον αριθμό για περίπου 5 δευτερόλεπτα.',
                style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary)),
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('train-hr-caution'),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(color: c.tint(c.exercise), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Η δόνηση βοηθά, δεν εγγυάται: πρώτα μετράει πώς νιώθεις. Με πόνο στο στήθος, δύσπνοια ή ζάλη σταματάς, '
                    'ό,τι κι αν δείχνει το ρολόι.',
                    style: TextStyle(fontSize: 14, height: 1.4, color: c.text)),
                const SizedBox(height: 6),
                Text(hrLimitBetaBlockerText, key: const ValueKey('train-hr-beta'), style: TextStyle(fontSize: 14, height: 1.4, color: c.text)),
              ]),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('train-hr-more'),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                onPressed: () => setState(() => _more = !_more),
                icon: Icon(_more ? Icons.expand_less_rounded : Icons.info_outline_rounded, size: 18),
                label: const Text('Πότε δεν έρχεται δόνηση'),
              ),
            ),
            if (_more)
              // Έλεγχος του #90 (M-2): χωριστά τι κάνει το ρολόι και τι το κινητό· ποτέ δόνηση όταν το ρολόι δεν μετρά.
              Text(
                hrLimitMoreText,
                key: const ValueKey('train-hr-more-text'),
                style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary),
              ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('train-hr'),
              controller: _hr,
              autofocus: widget.current == null,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
              onChanged: (_) => setState(() => _lowOk = false),
              decoration: InputDecoration(labelText: 'Όριο παλμών', suffixText: 'bpm', errorText: _error, border: const OutlineInputBorder()),
            ),
            if (askLow)
              CheckboxListTile(
                key: const ValueKey('train-hr-low'),
                contentPadding: EdgeInsets.zero,
                value: _lowOk,
                onChanged: (x) => setState(() => _lowOk = x == true),
                title: Text('Έγραψες $v. Σωστά;', style: TextStyle(fontSize: 14.5, color: c.text)),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('train-hr-save'),
              style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(50)),
              onPressed: !_valid ? null : () => Navigator.of(context).pop(_HrChoice(_value)),
              child: const Text('Αποθήκευση'),
            ),
            if (widget.current != null) ...[
              const SizedBox(height: 6),
              TextButton(
                key: const ValueKey('train-hr-clear'),
                onPressed: () => Navigator.of(context).pop(const _HrChoice(null)),
                child: const Text('Χωρίς όριο'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Η δεύτερη γραμμή μιας προπόνησης στις «Τελευταίες προπονήσεις». Round 2 (R2-U2-11): η διάρκεια σε λεπτά, όπως η
/// κάρτα «Τελευταία φορά» και η σύνοψη δίπλα της (πριν «1 ώρα» εδώ και «60 λεπτά» εκεί για την ίδια προπόνηση)· κάθε
/// αριθμός μένει με τη μονάδα του όταν η γραμμή σπάει.
String recentWorkoutLine(Session s) {
  final hr = s.hrAvg != null ? ' ·\u00A0μέσοι παλμοί\u00A0${s.hrAvg}' : '';
  if (s.isCardio) {
    final km = kmValue(s);
    return '${countText(s.cardioMinutes ?? s.duration.inMinutes, 'λεπτό', 'λεπτά').replaceAll(' ', '\u00A0')}'
        '${km != null ? ' ·\u00A0$km\u00A0km' : ''}$hr';
  }
  return '${countText(s.duration.inMinutes, 'λεπτό', 'λεπτά').replaceAll(' ', '\u00A0')} ·\u00A0${s.setsDone}\u00A0σετ'
      '${s.volume > 0 ? ' ·\u00A0${thousands(s.volume.round())}\u00A0kg' : ''}$hr';
}
