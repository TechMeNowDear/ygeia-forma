import 'package:flutter/material.dart';

import '../../exercise/ex_data.dart';
import '../../exercise/ex_names.dart';
import '../../format.dart';
import '../../training/walk_stats.dart' show kmValue, liveMeters, kmText;
import '../../theme.dart';
import '../../training/program.dart';
import '../../training/session.dart';
import '../../training/training_store.dart';
import '../../training/wear_link.dart';
import '../../widgets.dart';
import 'hr_widgets.dart';
import 'session_page.dart';
import 'training_common.dart';

/// «Άσκηση σήμερα» στη Σήμερα (σχέδια 9/11, 1β): μία κάρτα, πολλές μορφές.
/// - μέρα βαρών: όνομα, ασκήσεις, «Ξεκίνα την προπόνηση»·
/// - μέρα περπατήματος: «Ξεκινά από το ρολόι: πάτα «Περπάτημα»»·
/// - περπάτημα σε εξέλιξη (ζωντανά από το ρολόι), και χωρίς παλμούς με όριο γιατρού (κεχριμπάρι)·
/// - τελείωσε: σύνοψη σε μία γραμμή και «Δες τη σύνοψη».
/// Ξεκούραση ή χωρίς πρόγραμμα: η κάρτα δεν εμφανίζεται ([shows] = false). Μόνο διαβάζει από την αποθήκη.
class TodayTrainingCard extends StatefulWidget {
  const TodayTrainingCard({super.key, required this.training, required this.now});
  final TrainingStore training;
  final DateTime now;

  /// Αν έχει κάτι να δείξει σήμερα.
  static bool shows(TrainingStore t, DateTime now) {
    if (!t.ready) return false;
    if (liveWalk() != null || t.current != null) return true;
    if (doneToday(t, now) != null) return true;
    return chosenWorkout(t, now) != null || t.program?.forDay(now) != null;
  }

  /// R9-U3-06: η προπόνηση που διάλεξες για σήμερα από τις τρεις τελείες της «Άσκησης» ([TrainingStore.chosenOn]), με
  /// τα λεπτά της εβδομάδας ([Program.at]), ή null. Ίδια με την «Άσκηση»: πριν η Σήμερα έλεγε (και ξεκινούσε) την άλλη.
  static Workout? chosenWorkout(TrainingStore t, DateTime now) {
    final p = t.program;
    final id = t.chosenOn(now);
    final w = p == null || id == null ? null : p.workout(id);
    return w == null ? null : p!.at(w, now);
  }

  /// Περπάτημα που τρέχει τώρα στο ρολόι (ήρθε μήνυμα τα τελευταία 30″), όπως στην Άσκηση.
  static Map<String, dynamic>? liveWalk() {
    final l = WearLink.main.live.value;
    if (l == null) return null;
    final at = (l['at'] as num?)?.toInt() ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - at > 30000) return null;
    return l;
  }

  /// Η τελευταία προπόνηση που τελείωσε σήμερα ΚΑΙ είναι αυτή της μέρας (round1, S6-13): σε μέρα βαρών προπόνηση βαρών,
  /// σε μέρα περπατήματος περπάτημα. Πριν, ένα πρωινό περπάτημα έκρυβε από τη «Σήμερα» την προπόνηση βαρών της μέρας.
  /// Χωρίς πρόγραμμα για σήμερα (ξεκούραση): ό,τι έγινε.
  /// R10-B4-3: «της μέρας» είναι και αυτή που διάλεξες για σήμερα ([chosenWorkout]): ένα περπάτημα που διάλεξες σε μέρα
  /// βαρών και έγινε στο ρολόι (που δεν καθαρίζει την επιλογή) είναι η σημερινή «έγινε», όχι «Έγινε σήμερα και».
  static Session? doneToday(TrainingStore t, DateTime now) {
    final w = chosenWorkout(t, now) ?? t.program?.forDay(now);
    for (final s in t.sessions.reversed) {
      if (s.finished && sameDay(s.start, now) && (w == null || w.isCardio == s.isCardio)) return s;
    }
    return null;
  }

  /// Ό,τι άλλο τελείωσε σήμερα, έξω από την προπόνηση της μέρας (για τη γραμμή «Έγινε σήμερα και: …»).
  static Session? otherToday(TrainingStore t, DateTime now) {
    final w = chosenWorkout(t, now) ?? t.program?.forDay(now);
    if (w == null) return null;
    for (final s in t.sessions.reversed) {
      if (s.finished && sameDay(s.start, now) && w.isCardio != s.isCardio) return s;
    }
    return null;
  }

  @override
  State<TodayTrainingCard> createState() => _TodayTrainingCardState();
}

class _TodayTrainingCardState extends State<TodayTrainingCard> {
  TrainingStore get t => widget.training;

  /// Όνομα άσκησης χωρίς να φορτωθεί η βιβλιοθήκη (~450 KB) με το άνοιγμα της Σήμερα (έλεγχος premium, S5).
  static String _name(String id) => exNamesById[id] ?? ExLibrary.loaded?.byId(id)?.name ?? id;

  void _start(Workout w) {
    _library();
    t.start(w);
    WearLink.main.openWatch();
    Navigator.of(context).push(SessionPage.route(t));
  }

  /// round1, S6-2 / S7-01: η Σήμερα δεν φορτώνει τη βιβλιοθήκη ασκήσεων (S5), αλλά η οθόνη της προπόνησης τη θέλει για το
  /// «Πώς γίνεται» και την «Αλλαγή άσκησης». Φορτώνεται τώρα, χωρίς να περιμένει κανείς· μόλις έρθει, η οθόνη της
  /// προπόνησης ξαναζωγραφίζεται. Τα ονόματα και οι στόχοι δεν την περιμένουν (ex_names.dart, TrainingStore.cautionIds).
  void _library() {
    if (ExLibrary.loaded != null) return;
    ExLibrary.load().then((_) => t.libraryReady(), onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<Map<String, dynamic>?>(valueListenable: WearLink.main.live, builder: (context, live, child) => _build(context));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final now = widget.now;
    final live = TodayTrainingCard.liveWalk();
    final limit = t.hrLimit;
    if (live != null) {
      final bpm = (live['bpm'] as num?)?.toInt() ?? 0;
      final sec = (live['sec'] as num?)?.toInt() ?? 0;
      if (bpm <= 0 && limit != null && sec >= hrWaitSeconds) return _noHr(context, limit);
      return _live(context, live, limit);
    }
    final cur = t.current;
    final done = cur == null ? TodayTrainingCard.doneToday(t, now) : null;
    if (done != null) return _done(context, done, limit);
    final p = t.program;
    final chosen = cur == null ? TodayTrainingCard.chosenWorkout(t, now) : null;
    final w = cur != null ? (p?.workout(cur.workout)) : (chosen ?? p?.forDay(now));
    // R9-U3-06: όπως η «Άσκηση» (R8-U3-05): να φαίνεται ότι η σημερινή είναι επιλογή σου.
    final chosenLine = chosen == null ? null : Text('Τη διάλεξες εσύ για σήμερα.', key: const ValueKey('today-train-chosen'), style: _aux(c));

    final watch = WearLink.main.ready.value
        ? StatusPill(icon: Icons.watch_rounded, text: 'ρολόι έτοιμο', color: c.good)
        : null;
    // round1, U6-20 / R7-U1-9: «όριο παλμών 140» ποτέ σε δύο γραμμές (πριν δενόταν μόνο το «παλμών 140»).
    final limitText = limit == null ? null : 'όριο\u00A0παλμών\u00A0$limit';

    // round1, S6-14: ξεχασμένη προπόνηση (ανοιχτή ώρες χωρίς κίνηση): η ίδια κάρτα με την «Προπόνηση», όχι «Συνέχισε».
    if (cur != null && t.isStale(cur)) {
      return ForgottenWorkout(
        key: const ValueKey('today-training'),
        training: t,
        session: cur,
        now: now,
        watchReady: WearLink.main.ready.value,
        keyPrefix: 'today',
        onResume: () {
          _library();
          // R8-A8-3: ανοίγει και η εφαρμογή στο ρολόι, για να «μπει» ξανά στην προπόνηση.
          WearLink.main.openWatch();
          Navigator.of(context).push(SessionPage.route(t));
        },
      );
    }
    if (cur != null) {
      return _frame(
        context,
        trailing: watch,
        children: [
          _title(context, cur.name),
          const SizedBox(height: 4),
          // Με την ημέρα όταν δεν ξεκίνησε σήμερα (S6-14).
          Text('${cur.setsDone} σετ ως τώρα ·\u00A0ξεκίνησες ${sameDay(cur.start, now) ? '' : '${shortDayDate(cur.start)} '}${hm(cur.start)}',
              style: _aux(c)),
          const SizedBox(height: 16),
          _button(context, 'Συνέχισε την προπόνηση', () {
            _library();
            Navigator.of(context).push(SessionPage.route(t));
          }, key: 'today-train-resume'),
        ],
      );
    }
    if (w == null) return const SizedBox.shrink();

    if (w.isCardio) {
      final cardio = w.cardio!;
      return _frame(
        context,
        trailing: watch,
        children: [
          _title(context, cardio.name),
          if (chosenLine != null) chosenLine,
          const SizedBox(height: 4),
          // Round 10 (R10-B8-B1): ο αριθμός με τη λέξη του. Round 11 (R11-C2-3): το «·» με τον κανόνα [dotJoin] (όπως τα
          // τρόφιμα, foodTileSubtitle): η γραμμή δεν τελειώνει ποτέ σε «·»· αν σπάσει, το «·» πάει στην αρχή της επόμενης.
          Text(
            [
              '${cardio.minutes}\u00A0λεπτά',
              if (p?.planWeekText(cardio, now) case final wk?) wk,
              if (cardio.note != null && cardio.note!.trim().isNotEmpty) cardio.note!.trim(),
              if (limitText != null) limitText,
            ].join(dotJoin),
            style: _aux(c),
          ),
          // round1, U6-24: το ζέσταμα/η αποθεραπεία και στη «Σήμερα», στον δρόμο προς την προπόνηση.
          RoutineButton(w),
          if (_otherLine(c, now) case final o?) o,
          const SizedBox(height: 16),
          Container(
            key: const ValueKey('today-train-walk-hint'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: c.tint(c.exercise), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Icon(Icons.watch_outlined, color: c.exercise, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Ξεκινά από το ρολόι:\n'),
                    TextSpan(text: 'πάτα «${cardio.name}»', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  style: TextStyle(fontSize: 15, height: 1.4, color: c.text),
                ),
              ),
            ]),
          ),
        ],
      );
    }

    final names = [for (final i in w.items) _name(i.ex)];
    final shown = names.take(3).toList();
    final list = [
      for (var k = 0; k < shown.length; k++) k == 0 ? shown[k] : _lowerFirst(shown[k]),
    ].join(', ');
    final more = names.length - shown.length;
    return _frame(
      context,
      trailing: watch,
      children: [
        _title(context, w.name),
        if (chosenLine != null) chosenLine,
        const SizedBox(height: 4),
        Text(
          // Round 10 (R10-B8-B1) / Round 11 (R11-C2-3): όπως η γραμμή του περπατήματος πιο πάνω ([dotJoin]).
          [countText(w.items.length, 'άσκηση', 'ασκήσεις'), 'περίπου ${w.minutes}\u00A0λεπτά', if (limitText != null) limitText]
              .join(dotJoin),
          style: _aux(c),
        ),
        RoutineButton(w),
        if (_otherLine(c, now) case final o?) o,
        if (list.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: list),
              if (more > 0) TextSpan(text: ' +$more', style: TextStyle(color: c.textSecondary)),
            ]),
            style: TextStyle(fontSize: 15, height: 1.45, color: c.text),
          ),
        ],
        const SizedBox(height: 16),
        _button(context, 'Ξεκίνα την προπόνηση', () => _start(w), key: 'today-train-start'),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.directions_walk_rounded, size: 18, color: c.textSecondary),
          const SizedBox(width: 6),
          Expanded(child: Text('Για περπάτημα: στο ρολόι πάτα\u00A0«Περπάτημα».', style: _aux(c))),
        ]),
      ],
    );
  }

  static String _lowerFirst(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

  /// «Έγινε σήμερα και: Περπάτημα · 25 λεπτά» (S6-13), όταν έγινε κάτι άλλο από την προπόνηση της μέρας.
  Widget? _otherLine(Aigaio c, DateTime now) {
    final o = TodayTrainingCard.otherToday(t, now);
    if (o == null) return null;
    final mins = o.isCardio ? (o.cardioMinutes ?? o.duration.inMinutes) : o.duration.inMinutes;
    return Padding(
      key: const ValueKey('today-training-other'),
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Icon(Icons.check_rounded, size: 16, color: c.good),
        const SizedBox(width: 4),
        // Round 12 (R12-D2-4): όπως οι δύο γραμμές πιο πάνω στην ίδια κάρτα: «·» με τον κανόνα [dotJoin] και ο αριθμός με τη
        // λέξη του ([unitsGlued]). Πριν, στα 360 dp: «… Περπάτημα · 1 ώρα 5» / «λεπτά».
        Expanded(child: Text('Έγινε σήμερα και: ${o.name}$dotJoin${unitsGlued(hoursMinutes(mins))}', style: _aux(c))),
      ]),
    );
  }

  TextStyle _aux(Aigaio c) => TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary);

  Widget _title(BuildContext context, String text) {
    final c = Aigaio.of(context);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(text, maxLines: 1, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.15, color: c.text)),
    );
  }

  Widget _button(BuildContext context, String text, VoidCallback onTap, {required String key}) {
    final c = Aigaio.of(context);
    return FilledButton(
      key: ValueKey(key),
      // Round 2 (R2-U2-09): και 10 dp πάνω-κάτω· με γράμματα 2× το κείμενο σε δύο γραμμές ακουμπούσε τις άκρες. Στο 1×
      // το ύψος μένει 52 (16 + 20 < 52).
      style: FilledButton.styleFrom(
          backgroundColor: c.exerciseSolid,
          foregroundColor: c.onSolid,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
      onPressed: onTap,
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }

  Widget _frame(BuildContext context, {String title = 'Άσκηση σήμερα', IconData icon = Icons.fitness_center_rounded, Widget? trailing, required List<Widget> children}) {
    final c = Aigaio.of(context);
    return AppCard(
      key: const ValueKey('today-training'),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader(icon: icon, title: title, color: c.exercise, trailing: trailing),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }

  Widget _live(BuildContext context, Map<String, dynamic> l, int? limit) {
    final c = Aigaio.of(context);
    final sec = (l['sec'] as num?)?.toInt() ?? 0;
    // 14/11: GPS, αλλιώς από τα βήματα με «≈» (ίδιος κανόνας με το ρολόι και τη σύνοψη).
    final d = liveMeters(l);
    final m = d?.meters ?? 0;
    final bpm = (l['bpm'] as num?)?.toInt() ?? 0;
    final paused = l['paused'] == true;
    return _frame(
      context,
      title: paused ? 'Περπάτημα ·\u00A0σε παύση' : 'Περπάτημα ·\u00A0τώρα',
      icon: Icons.directions_walk_rounded,
      trailing: paused ? null : StatusPill(icon: Icons.circle, text: 'ζωντανά', color: c.exercise, iconSize: 8),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(clock(sec),
                  key: const ValueKey('today-walk-time'),
                  style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1.5, height: 1.05, color: c.text, fontFeatures: tabular)),
            ),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(d == null ? '—' : '${d.approx ? '≈ ' : ''}${kmText(m)} km',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular)),
            Text(m < 50 || sec <= 0 ? '' : paceText(sec / (m / 1000)),
                style: TextStyle(fontSize: 13, color: c.textSecondary, fontFeatures: tabular)),
          ]),
        ]),
        if (bpm > 0) ...[const SizedBox(height: 12), HrBar(bpm: bpm, limit: limit, bare: true)],
        const SizedBox(height: 10),
        Text('Τελειώνει από το ρολόι.', style: _aux(c)),
      ],
    );
  }

  /// Κατάσταση Δ: περπάτημα χωρίς παλμούς με όριο γιατρού. Ίδιο με την οθόνη του ρολογιού· μένει ως την πρώτη τιμή.
  Widget _noHr(BuildContext context, int limit) {
    final c = Aigaio.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('today-training-nohr'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.warnBg,
          borderRadius: BorderRadius.circular(AppCard.radius),
          border: Border.all(color: c.warnLine, width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded, color: c.warn, size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text('Δεν έρχονται παλμοί', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.warn))),
          ]),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(children: [
              // Ίδια ελεγμένη φράση παντού (V-A-04/05): «δεν σε προσέχει».
              TextSpan(text: 'Το όριο $limit δεν σε προσέχει τώρα. ', style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: 'Το ρολόι δεν στέλνει παλμούς.'),
            ]),
            style: TextStyle(fontSize: 15, height: 1.45, color: c.text),
          ),
          const SizedBox(height: 6),
          Text('Σφίξε λίγο το λουράκι. Μέχρι να έρθουν παλμοί, πήγαινε με την κούραση.',
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.warn)),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('today-training-open-watch'),
            style: FilledButton.styleFrom(backgroundColor: c.warn, foregroundColor: c.dark ? c.background : Colors.white, minimumSize: const Size.fromHeight(52)),
            onPressed: () => WearLink.main.openWatch(),
            icon: const Icon(Icons.watch_rounded),
            label: const Text('Άνοιξε το ρολόι', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  Widget _done(BuildContext context, Session s, int? limit) {
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
            Text(label, style: _aux(c)),
          ]),
        );
    final max = s.hrMax;
    // round1, U6-28: ίδια διατύπωση με τη σύνοψη (απόφαση 12/11, μ5): «Υψηλότερος παλμός ~132» στα βάρη, και ποτέ «κάτω από
    // το όριο» ως βεβαίωση (ο καρπός στα βάρη συχνά μετρά πιο χαμηλά). Κρίνεται μόνο με το όριο εκείνης της προπόνησης.
    final used = s.limitUsed;
    final hrLine = max == null
        ? null
        : used == null
            ? 'Υψηλότερος παλμός ${hrMaxText(max, cardio: s.isCardio)}'
            : 'Υψηλότερος παλμός ${hrMaxText(max, cardio: s.isCardio)} ·\u00A0'
                '${max >= used ? 'έφτασε το όριο $used' : 'το ρολόι δεν έδειξε πάνω από το όριο $used'}';
    return _frame(
      context,
      icon: s.isCardio ? Icons.directions_walk_rounded : Icons.fitness_center_rounded,
      trailing: StatusPill(icon: Icons.check_rounded, text: 'έγινε', color: c.good),
      children: [
        _title(context, s.name),
        const SizedBox(height: 10),
        Row(children: [
          if (s.isCardio) ...[
            // round1, U6-06: «λεπτά», όχι «λ».
            stat('${s.cardioMinutes ?? s.duration.inMinutes}', (s.cardioMinutes ?? s.duration.inMinutes) == 1 ? 'λεπτό' : 'λεπτά', 'διάρκεια'),
            // 14/11: όχι «0,00 km» όταν δεν μετρήθηκε απόσταση· από τα βήματα με «≈» ([kmValue]).
            stat(kmValue(s) ?? '—', kmValue(s) == null ? '' : 'km', 'απόσταση'),
            stat(s.hrAvg == null ? '—' : '${s.hrAvg}', s.hrAvg == null ? '' : 'bpm', 'μέσοι παλμοί'),
          ] else ...[
            stat('${s.duration.inMinutes}', s.duration.inMinutes == 1 ? 'λεπτό' : 'λεπτά', 'διάρκεια'),
            stat('${s.setsDone}', '', 'σετ'),
            stat(s.volume > 0 ? thousands(s.volume.round()) : '—', s.volume > 0 ? 'kg' : '', 'σύνολο κιλών'),
          ],
        ]),
        if (hrLine != null) ...[
          const SizedBox(height: 10),
          Text(hrLine, style: TextStyle(fontSize: 13, color: used != null && max! >= used ? c.bad : c.textSecondary)),
        ],
        const SizedBox(height: 6),
        InkWell(
          key: const ValueKey('today-training-summary'),
          onTap: () => Navigator.of(context).push(SummaryPage.route(t, s)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Expanded(child: Text('Δες τη σύνοψη', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.exercise))),
              Icon(Icons.chevron_right_rounded, color: c.exercise),
            ]),
          ),
        ),
      ],
    );
  }
}

/// Μικρή ετικέτα κατάστασης με εικονίδιο («ρολόι έτοιμο», «✓ έγινε», «● ζωντανά»).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.icon, required this.text, required this.color, this.iconSize = 14});
  final IconData icon;
  final String text;
  final Color color;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.tint(color), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: iconSize, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}
