import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../exercise/ex_data.dart';
import '../../format.dart';
import '../../theme.dart';
import '../../data.dart' show HealthStore;
import '../../training/equipment.dart';
import '../../training/progression.dart';
import '../../training/program.dart';
import '../../training/session.dart';
import '../../training/set_hr.dart';
import '../../training/walk_stats.dart';
import '../../training/training_device.dart';
import '../../training/training_store.dart';
import '../../training/wear_link.dart';
import '../../widgets.dart';
import '../exercise_detail.dart';
import '../info_sheet.dart' show InfoDot;
import 'ex_picker.dart';
import 'hr_widgets.dart';
import 'training_common.dart';
import 'zone_widgets.dart';
import 'walk_widgets.dart';

/// Μετακίνηση ανάμεσα στα διαθέσιμα βάρη (με τα βελάκια). Στο λάστιχο βοήθειας περιλαμβάνεται και το «χωρίς».
double? shiftLoad(LoadKind k, double? v, int dir) {
  if (v == null || !hasLoad(k)) return null;
  final list = [if (k == LoadKind.bandAssist) 0.0, ...available(k)];
  var idx = 0;
  for (var i = 0; i < list.length; i++) {
    if (list[i] <= v + 1e-6) idx = i;
  }
  final n = idx + dir;
  if (n < 0 || n >= list.length) return null;
  return list[n];
}

/// R7-U4-2: «μένει 1 δευτερόλεπτο» / «μένουν 45 δευτερόλεπτα» (ενικός στο 1· πριν «μένουν 1 δευτερόλεπτα»).
String restLeftText(int secs) => '${secs == 1 ? 'μένει' : 'μένουν'} ${secondsText(secs)}';

/// R7-U4-2: πότε ξαναλέει το TalkBack το διάλειμμα (η λωρίδα είναι «ζωντανή περιοχή»: λέγεται κάθε φορά που αλλάζει η
/// ετικέτα της). Πριν η ετικέτα άλλαζε κάθε δευτερόλεπτο: 90 ανακοινώσεις σε διάλειμμα 90″. Τώρα: στην αρχή (και όταν
/// μεγαλώσει, π.χ. «+30″»), όταν περνά κάθε μισό λεπτό (60, 30…) και μία φορά στα 10 τελευταία δευτερόλεπτα. Το τέλος
/// το λέει η ειδοποίηση «Τέλος διαλείμματος» με τη δόνηση. [last]: τα δευτερόλεπτα της τελευταίας ανακοίνωσης
/// (null = καμία ακόμα σε αυτό το διάλειμμα).
bool restSpeaksNow(int? last, int secs) {
  if (last == null || secs > last) return true;
  if (secs == last) return false;
  if (secs <= 10) return last > 10;
  return (last - 1) ~/ 30 != (secs - 1) ~/ 30;
}

/// Η προπόνηση σε εξέλιξη: μία άσκηση τη φορά, σετ με ✓, διάλειμμα που ξεκινά μόνο του.
class SessionPage extends StatefulWidget {
  const SessionPage({super.key, required this.training});
  final TrainingStore training;

  static Route<void> route(TrainingStore t) =>
      MaterialPageRoute<void>(settings: const RouteSettings(name: 'Προπόνηση'), builder: (_) => SessionPage(training: t));

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  TrainingStore get t => widget.training;
  // Η άσκηση και το διάλειμμα ζουν στην αποθήκη (τα βλέπει και το ρολόι).
  int get _idx => t.focus;
  set _idx(int v) => t.focus = v;
  DateTime? get _restEnd => t.restEnd;
  set _restEnd(DateTime? v) => t.restEnd = v;
  Timer? _timer;
  final _tick = ValueNotifier<int>(0);

  /// R7-U4-2: ποιο διάλειμμα ([_spokenEnd]) και με πόσα δευτερόλεπτα ([_spokenSecs]) ανακοινώθηκε τελευταία στο TalkBack.
  DateTime? _spokenEnd;
  int? _spokenSecs;

  /// round1, U6-16 / U5-03: η λωρίδα των ασκήσεων και η λίστα ακολουθούν την τρέχουσα άσκηση και το τρέχον σετ (πριν
  /// το επόμενο «Έγινε» γλιστρούσε κάτω από τη λωρίδα του διαλείμματος και το ενεργό chip έμενε εκτός οθόνης).
  final _chipKeys = <int, GlobalKey>{};
  final _currentKey = GlobalKey();
  String? _followed;

  void _follow(String sig) {
    if (sig == _followed) return;
    _followed = sig;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final chip = _chipKeys[_idx]?.currentContext;
      if (chip != null) Scrollable.ensureVisible(chip, alignment: .1, duration: const Duration(milliseconds: 200));
      final cur = _currentKey.currentContext;
      if (cur != null) {
        Scrollable.ensureVisible(cur,
            alignment: 1.0, duration: const Duration(milliseconds: 250), alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final s = t.current;
    if (s != null) {
      final i = s.items.indexWhere((e) => !e.skipped && !e.rowsDone);
      t.setFocusQuiet(i < 0 ? (s.items.isEmpty ? 0 : s.items.length - 1) : i);
    }
    TrainingDevice.keepOn(true);
    TrainingDevice.askNotify();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_restEnd != null && !t.now.isBefore(_restEnd!)) {
        _restEnd = null;
        HapticFeedback.heavyImpact();
        if (mounted) setState(() {});
      }
      _tick.value++;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tick.dispose();
    TrainingDevice.keepOn(false);
    super.dispose();
  }

  void _rest(ExLog e, String next) {
    // Η προπόνηση σταμάτησε στο μεταξύ (σύμπτωμα, «Σταμάτησα» στο ρολόι): κανένα νέο διάλειμμα (έλεγχος #2, B2).
    if (e.rest <= 0 || t.current == null) return;
    final end = t.now.add(Duration(seconds: e.rest));
    setState(() => _restEnd = end);
    TrainingDevice.rest(end, title: 'Διάλειμμα', text: 'Επόμενο: $next', doneTitle: 'Τέλος διαλείμματος', doneText: 'Επόμενο: $next');
  }

  void _restAdd(int s) {
    final end = (_restEnd ?? t.now).add(Duration(seconds: s));
    setState(() => _restEnd = end);
    TrainingDevice.rest(end, title: 'Διάλειμμα', text: 'Συνέχισε όταν τελειώσει', doneTitle: 'Τέλος διαλείμματος', doneText: 'Επόμενο σετ');
  }

  void _restStop() {
    setState(() => _restEnd = null);
    TrainingDevice.restCancel();
  }

  // Round 1 (U5-30, αίτημα f9 → f6b): η σελίδα/το φύλλο ανοίγει με push, έξω από το ExerciseTheme της κατηγορίας·
  // χωρίς αυτό διακόπτες και δευτερεύοντα κουμπιά έβγαιναν μπλε δίπλα στα πορτοκαλί.
  @override
  Widget build(BuildContext context) => ExerciseTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) {
        final s = t.current;
        if (s == null) {
          // «Τέλος» στο ρολόι (έλεγχος 9/11, V-A-09): η προπόνηση έκλεισε εκεί· εδώ η σύνοψή της.
          final ended = t.endedByWatch;
          if (ended != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || t.current != null || t.endedByWatch != ended) return;
              t.endedByWatch = null;
              TrainingDevice.restCancel();
              Navigator.of(context).pushReplacement(SummaryPage.route(t, ended));
            });
          }
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    ended != null
                        ? 'Η προπόνηση τελείωσε από το ρολόι.'
                        : t.discardedByWatch
                            ? 'Η προπόνηση σβήστηκε από το ρολόι: δεν είχε κανένα σετ.'
                            : 'Δεν υπάρχει προπόνηση σε εξέλιξη.',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
              ),
            ),
          );
        }
        final c = Aigaio.of(context);
        // R8-U3-01: ✓ του 1ου σετ «πρώτης φοράς» στο ρολόι: η ερώτηση έρχεται εδώ, μόλις ζωγραφιστεί η σελίδα.
        if (t.firstAsk != null && !_asking) WidgetsBinding.instance.addPostFrameCallback((_) => _firstFromWatch(s));
        // «Ελεύθερη άσκηση» χωρίς ασκήσεις ακόμα: μόνο «Πρόσθεσε άσκηση».
        if (s.items.isEmpty) return _emptyFree(context, s);
        if (_idx >= s.items.length || _idx < 0) t.setFocusQuiet(s.items.length - 1);
        final e = s.items[_idx];
        final planned = t.program?.workout(s.workout);
        final routine = planned != null && routineLabel(planned) != null ? planned : null;
        final notes = programNotes(t.program, planned);
        final current = e.log.indexWhere((x) => !x.done);
        _follow('$_idx:$current');
        return Scaffold(
          appBar: AppBar(
            // Ο τίτλος μεγαλώνει ως 1,3×, για να μη γίνεται «Προπ…» δίπλα στο «Τέλος» (έλεγχος premium, S4). round1, U5-01:
            // χωρίς το διπλό κενό αριστερά, και μακρύ όνομα μικραίνει αντί να κόβεται.
            titleSpacing: 0,
            title: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(s.name, maxLines: 1, softWrap: false, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              ValueListenableBuilder<int>(
                valueListenable: _tick,
                builder: (_, __, ___) => Text(_clock(t.now.difference(s.start)),
                    style: TextStyle(fontSize: 13, color: c.textSecondary, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ])),
            // Σχέδια 9/11 (6β): «Τέλος» ως απαλό κουμπί και ⋮ για τα σπάνια («Αλλαγή άσκησης»).
            actions: [
              _finishButton(context),
              PopupMenuButton<String>(
                key: const ValueKey('sess-more'),
                tooltip: 'Περισσότερα',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (v) {
                  if (v == 'swap') _swap(context, e);
                  if (v == 'pain') _painSheet(context, e);
                  if (v == 'routine' && routine != null) openRoutineSheet(context, routine);
                  if (v == 'notes' && notes.isNotEmpty) openProgramNotesSheet(context, notes);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'swap', key: ValueKey('sess-swap'), child: Text('Αλλαγή άσκησης')),
                  // R7-A6-2: ενόχληση σε οποιοδήποτε σημείο της άσκησης (και αν σταματάς πριν από το τελευταίο σετ).
                  const PopupMenuItem(value: 'pain', key: ValueKey('sess-pain'), child: Text('Πόνεσε κάπου')),
                  // 13/11: το ζέσταμα και η αποθεραπεία της προπόνησης, αν το πρόγραμμα έχει.
                  if (routine != null) PopupMenuItem(value: 'routine', key: const ValueKey('sess-routine'), child: Text(routineLabel(routine)!)),
                  // round1, S7-11: οι κανόνες του προγράμματος, πάντα ένα πάτημα μακριά μέσα στην προπόνηση.
                  if (notes.isNotEmpty) const PopupMenuItem(value: 'notes', key: ValueKey('sess-notes'), child: Text(programNotesLabel)),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(builder: (context, k) {
              final wide = k.maxWidth >= 720;
              final ex = _exerciseCard(context, s, e);
              // round1, U6-24: το ζέσταμα πριν από το 1ο σετ και η αποθεραπεία μετά το τελευταίο, πάνω από την άσκηση.
              final allDone = s.items.every((x) => x.skipped || x.rowsDone);
              final routineRow = routine == null
                  ? null
                  : s.setsDone == 0 && routine.warmup.isNotEmpty
                      ? _routineRow(context, routine, 'Πρώτα ζέσταμα · ${countText(routine.warmup.length, 'βήμα', 'βήματα')}')
                      : allDone && routine.cooldown.isNotEmpty
                          ? _routineRow(context, routine, 'Αποθεραπεία · ${countText(routine.cooldown.length, 'βήμα', 'βήματα')}')
                          : null;
              final card = routineRow == null ? ex : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [routineRow, const SizedBox(height: 8), ex]);
              final rest = _restEnd == null ? null : _restBar(context, s);
              final actions = _actions(context, s, e);
              if (wide) {
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 320,
                        child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 8, 24), children: [
                          _hr(const EdgeInsets.only(bottom: 12)),
                          _list(context, s, vertical: true),
                        ]),
                      ),
                      Expanded(
                        child: Column(children: [
                          Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(8, 8, 20, 16), children: [card])),
                          // Το διάλειμμα πάνω από τα κουμπιά, όπως στο κινητό: εκεί που κοιτάς μετά το ✓.
                          if (rest != null) Padding(padding: const EdgeInsets.fromLTRB(8, 0, 20, 10), child: rest),
                          Padding(padding: const EdgeInsets.fromLTRB(8, 0, 20, 16), child: actions),
                        ]),
                      ),
                    ]),
                  ),
                );
              }
              return Column(children: [
                _hr(const EdgeInsets.fromLTRB(16, 8, 16, 0)),
                // Με μεγάλα γράμματα η λωρίδα των ασκήσεων ψηλώνει (πριν: σταθερά 54 dp, κομμένα γράμματα).
                SizedBox(height: MediaQuery.textScalerOf(context).scale(54).clamp(54.0, 96.0), child: _list(context, s, vertical: false)),
                Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [card])),
                if (rest != null) Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: rest),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  decoration: BoxDecoration(color: c.card, border: Border(top: BorderSide(color: c.hairline))),
                  child: actions,
                ),
              ]);
            }),
          ),
        );
      },
    );
  }

  /// Ζωντανοί παλμοί από το ρολόι. Χωρίς όριο και χωρίς παλμούς ποτέ: τίποτα. Παλμοί που σταμάτησαν: πορτοκαλί μήνυμα.
  /// Με όριο γιατρού και χωρίς παλμούς (έλεγχος 9/11, V-A-05): ΠΑΝΤΑ μήνυμα, και όταν το ρολόι δεν βρέθηκε, γιατί τότε
  /// καμία δόνηση δεν θα έρθει. Τα πρώτα [hrWaitSeconds] (30″, όσο και το ρολόι) με το ρολόι κοντά: ήρεμο «Περιμένω
  /// παλμούς από το ρολόι…» (ανοίγει μόνο του). Χωρίς ρολόι κοντά: αμέσως, γιατί δεν θα έρθουν.
  Widget _hr(EdgeInsets pad) => ListenableBuilder(
        listenable: Listenable.merge([WearLink.main.hr, WearLink.main.ready, _tick]),
        builder: (context, _) {
          final w = WearLink.main;
          final now = DateTime.now();
          final bpm = w.bpmAt(now);
          if (bpm != null) return Padding(padding: pad, child: HrBar(bpm: bpm, limit: t.hrLimit));
          final s = t.current;
          final last = w.hr.value;
          // Ήρθαν παλμοί σε αυτή την προπόνηση (όχι σε κάποια παλιότερη) και σταμάτησαν.
          final lost = last != null && (s == null || !last.$2.isBefore(s.start));
          final limit = t.hrLimit;
          // R8-U3-02: χωρίς όριο, το «Σφίξε λίγο το λουράκι» μόνο αν ήρθαν παλμοί σε ΑΥΤΗ την προπόνηση και σταμάτησαν
          // (πριν και με παλμούς από ένα πρωινό περπάτημα, πριν ακόμα έρθει ο πρώτος παλμός της προπόνησης).
          if (limit == null) return lost ? Padding(padding: pad, child: const HrStale()) : const SizedBox.shrink();
          if (!lost && w.ready.value && s != null && now.difference(s.start).inSeconds < hrWaitSeconds) {
            return Padding(padding: pad, child: const HrWaiting());
          }
          return Padding(padding: pad, child: HrStale(limit: limit, lost: lost, watchFound: w.ready.value));
        },
      );


  static String _clock(Duration d) {
    final m = d.inMinutes, s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// «Τέλος» (round1, U6-22: ίδιο κουμπί και στην άδεια «Ελεύθερη άσκηση»· U5-01: ως 1,3× όπως ο τίτλος, για να μην
  /// του τρώει τον χώρο με μεγάλα γράμματα).
  Widget _finishButton(BuildContext context) {
    final c = Aigaio.of(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: OutlinedButton(
        key: const ValueKey('sess-finish'),
        style: OutlinedButton.styleFrom(
          foregroundColor: c.exercise,
          backgroundColor: c.card,
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          side: BorderSide(color: c.hairline),
        ),
        onPressed: () => _finish(context),
        child: const Text('Τέλος', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  /// Μία γραμμή που ανοίγει το ζέσταμα ή την αποθεραπεία (round1, U6-24).
  Widget _routineRow(BuildContext context, Workout w, String label) {
    final c = Aigaio.of(context);
    return Material(
      color: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.hairline)),
      child: InkWell(
        key: const ValueKey('sess-routine-row'),
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () => openRoutineSheet(context, w),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Icon(Icons.self_improvement_rounded, size: 20, color: c.exercise),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.exercise))),
              Icon(Icons.chevron_right_rounded, color: c.exercise),
            ]),
          ),
        ),
      ),
    );
  }

  /// Η σημείωση της άσκησης στο πρόγραμμα (round1, S7-11), ή null.
  String? _itemNote(Session s, ExLog e) {
    for (final i in t.program?.workout(s.workout)?.items ?? const <PlanItem>[]) {
      if (i.ex == e.ex || i.ex == e.swappedFrom) {
        final n = i.note?.trim();
        return n == null || n.isEmpty ? null : n;
      }
    }
    return null;
  }

  /// Πλάτος της στήλης «Σετ»: μεγαλώνει με τα γράμματα (round1, U5-04), 30–46 dp.
  double _setColumn(BuildContext context) => MediaQuery.textScalerOf(context).scale(30).clamp(30.0, 46.0);

  Widget _head(Aigaio c, String text) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 13, color: c.textSecondary, fontWeight: FontWeight.w600)),
      );

  Widget _list(BuildContext context, Session s, {required bool vertical}) {
    final c = Aigaio.of(context);
    Widget item(int i) {
      final e = s.items[i];
      final on = i == _idx;
      final done = e.done.length;
      // R9-U3-08: με το «+ Σετ» μετρούν και οι γραμμές που πρόσθεσες («3/4», όχι πράσινο «3/3» με ένα σετ ακόμα).
      final rows = e.log.length > e.sets ? e.log.length : e.sets;
      final status = e.skipped ? '—' : '$done/$rows';
      final finished = e.rowsDone || e.skipped;
      return Padding(
        key: _chipKeys.putIfAbsent(i, () => GlobalKey()),
        padding: vertical ? const EdgeInsets.only(bottom: 8) : const EdgeInsets.only(right: 8),
        child: Material(
          color: on ? c.tint(c.exercise) : c.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(vertical ? 16 : 999),
            side: BorderSide(color: on ? c.exercise : c.hairline, width: on ? 1.6 : 1),
          ),
          child: InkWell(
            key: ValueKey('sess-ex-$i'),
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(vertical ? 16 : 999)),
            onTap: () => setState(() => _idx = i),
            child: Padding(
              padding: vertical ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12) : const EdgeInsets.symmetric(horizontal: 14),
              child: Row(mainAxisSize: vertical ? MainAxisSize.max : MainAxisSize.min, children: [
                if (vertical)
                  Expanded(child: Text(exName(e.ex), style: TextStyle(fontSize: 15, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: finished && !on ? c.textSecondary : c.text)))
                else
                  Text(exName(e.ex), style: TextStyle(fontSize: 14, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: finished && !on ? c.textSecondary : c.text)),
                const SizedBox(width: 8),
                Text(status, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: e.rowsDone ? c.good : c.textSecondary)),
              ]),
            ),
          ),
        ),
      );
    }

    Widget addChip() => Padding(
          padding: vertical ? const EdgeInsets.only(bottom: 8) : const EdgeInsets.only(right: 8),
          child: Material(
            color: c.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(vertical ? 16 : 999), side: BorderSide(color: c.exercise)),
            child: InkWell(
              key: const ValueKey('free-add-chip'),
              customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(vertical ? 16 : 999)),
              onTap: () => _addExercise(context),
              child: Padding(
                padding: vertical ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12) : const EdgeInsets.symmetric(horizontal: 14),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_rounded, size: 20, color: c.exercise),
                  const SizedBox(width: 4),
                  Text('Άσκηση', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.exercise)),
                ]),
              ),
            ),
          ),
        );

    if (vertical) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('ΑΣΚΗΣΕΙΣ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.textSecondary)),
        ),
        for (var i = 0; i < s.items.length; i++) item(i),
        if (s.isFree) addChip(),
      ]);
    }
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [for (var i = 0; i < s.items.length; i++) item(i), if (s.isFree) addChip()],
    );
  }

  Widget _exerciseCard(BuildContext context, Session s, ExLog e) {
    final c = Aigaio.of(context);
    final k = e.kind;
    final lib = ExLibrary.loaded;
    final ex = lib?.byId(e.ex);
    final current = e.log.indexWhere((x) => !x.done);
    final loadNow = current >= 0 ? e.log[current].load : (e.log.isEmpty ? null : e.log.last.load);
    // Τι αλλάζει στους δίσκους από την προηγούμενη άσκηση με το ίδιο όργανο.
    String? change;
    for (var i = _idx - 1; i >= 0; i--) {
      final p = s.items[i];
      if (p.skipped || p.log.isEmpty) continue;
      final ch = plateChange(p.kind, p.log.last.load, k, loadNow);
      if (ch != null) {
        change = ch;
        break;
      }
    }
    // Η τελευταία φορά με σετ (όχι μια «παράλειψη»). R7-A6-11: κάθε σετ με το φορτίο του, όταν άλλαξε μέσα στην άσκηση.
    final hist = [for (final h in t.historyOf(e.ex)) if (!h.$2.skipped && h.$2.done.isNotEmpty) h];
    String? lastTime;
    if (hist.isNotEmpty) {
      final (d, l) = hist.first;
      lastTime = 'Τελευταία φορά (${shortDayDate(d)}): ${l.doneText()}'
          '${l.rirAnswer == null ? '' : ' · άφησες ${l.rirAnswer == 4 ? '4+' : l.rirAnswer}'}';
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Σχέδια 9/11 (6β): «3 σετ × 12–15 · άφησε 2 · ξεκούραση 1:30». (Το αγγλικό δεν μπαίνει: η βιβλιοθήκη έχει
        // μόνο λέξεις αναζήτησης, όχι σύντομο όνομα.)
        // round1, U5-09: «Πώς γίνεται» στο ύψος του τίτλου (πριν 10 dp πιο χαμηλά στο ανοιχτό Fold).
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(exName(e.ex), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.2, color: c.text)),
            ]),
          ),
          if (ex != null && lib != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: c.exercise),
              onPressed: () => Navigator.of(context).push(ExerciseDetailPage.route(ex, lib)),
              child: const Text('Πώς γίνεται'),
            ),
        ]),
        const SizedBox(height: 8),
        // round1, S7-21: ⓘ δίπλα στο «άφησε», για να ξέρεις τι σημαίνει πριν από το 1ο σετ (πριν, μόνο μετά το τελευταίο).
        Row(children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${e.sets} σετ × ${e.lo == e.hi ? '${e.lo}' : '${e.lo}–${e.hi}'} · '),
                TextSpan(text: 'άφησε\u00A0${e.rir}', style: const TextStyle(fontWeight: FontWeight.w700)),
                // R7-U3-09: «ξεκούραση 2:00» ποτέ σε δύο γραμμές.
                TextSpan(text: ' · ξεκούραση\u00A0${clock(e.rest)}'),
              ]),
              key: const ValueKey('sess-plan'),
              style: TextStyle(fontSize: 15, height: 1.4, color: c.text),
            ),
          ),
          const InfoDot(rirInfo, key: ValueKey('rir-info')),
        ]),
        // round1, S7-11: η σημείωση της άσκησης από το πρόγραμμα (πριν δεν φαινόταν πουθενά).
        if (_itemNote(s, e) case final note?) ...[
          const SizedBox(height: 4),
          Text(note, key: const ValueKey('sess-item-note'), style: TextStyle(fontSize: 14, height: 1.4, color: c.text)),
        ],
        // R7-A6-7: ένα ✓ = και οι δύο πλευρές (έτσι μετρούν τα σετ, ο χρόνος και τα κιλά).
        if (perSideExercises.contains(e.ex)) ...[
          const SizedBox(height: 4),
          // R8-A6-6: «Έγινε» (το κουμπί) αντί για «✓», που δεν υπάρχει στη γραμματοσειρά (Inter) και έβγαινε κενό.
          Text('Κάθε σετ: δεξιά και αριστερά, μετά «Έγινε».',
              key: const ValueKey('sess-per-side'), style: TextStyle(fontSize: 14, height: 1.4, color: c.text)),
        ],
        if (hasLoad(k) || change != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.tint(c.exercise), borderRadius: BorderRadius.circular(16)),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Στήσιμο: ', style: TextStyle(fontWeight: FontWeight.w700, color: c.exercise)),
                TextSpan(text: setupText(k, loadNow)),
                if (change != null && change != 'ίδιοι δίσκοι') ...[
                  TextSpan(text: '\nΆλλαξε: ', style: TextStyle(fontWeight: FontWeight.w700, color: c.exercise)),
                  TextSpan(text: change),
                ],
              ]),
              style: TextStyle(fontSize: 14.5, height: 1.4, color: c.text),
            ),
          ),
        ],
        if (e.reason != null) ...[
          const SizedBox(height: 8),
          Text(e.reason!, style: TextStyle(fontSize: 13.5, height: 1.35, color: c.textSecondary)),
        ],
        if (lastTime != null) ...[
          const SizedBox(height: 4),
          Text(lastTime, style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
        ],
        const SizedBox(height: 12),
        if (e.skipped)
          Row(children: [
            Expanded(child: Text('Παραλείφθηκε', style: TextStyle(fontSize: 15, color: c.textSecondary))),
            TextButton(onPressed: () => t.skip(e, false), child: const Text('Αναίρεση')),
          ])
        else ...[
          // round1, U5-04: οι επικεφαλίδες σε μία γραμμή, ποτέ «Σε/τ» ή «Επαναλήψε/ις» με μεγάλα γράμματα.
          if (!veryLargeText(context))
          Row(children: [
            SizedBox(width: _setColumn(context), child: _head(c, 'Σετ')),
            if (hasLoad(k)) Expanded(child: _head(c, usesKg(k) ? 'Κιλά' : (isBand(k) ? 'Λάστιχο' : 'Βάρος'))),
            Expanded(child: _head(c, 'Επαναλήψεις')),
            const SizedBox(width: 52),
          ]),
          const SizedBox(height: 6),
          for (var i = 0; i < e.log.length; i++) _setRow(context, s, e, i, i == current),
          // R7-A6-2: «Πόνεσε κάπου;» σε κάθε σημείο της άσκησης, όχι μόνο μετά το τελευταίο σετ.
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, children: [
            TextButton.icon(onPressed: () => t.addSet(e), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Σετ')),
            TextButton(
              key: const ValueKey('sess-pain-btn'),
              style: TextButton.styleFrom(foregroundColor: c.warn, minimumSize: const Size(48, 48)),
              onPressed: () => _painSheet(context, e),
              child: const Text('Πόνεσε κάπου;'),
            ),
          ]),
          if ((e.complete && e.rirAnswer != null) || e.pain.isNotEmpty)
            Text(
              [
                if (e.complete && e.rirAnswer != null) 'Άφησες ${e.rirAnswer == 4 ? '4+' : e.rirAnswer}',
                if (e.pain.isNotEmpty) '${e.complete && e.rirAnswer != null ? 'ενόχληση' : 'Ενόχληση'}: ${e.pain.map((p) => painNames[p] ?? p).join(', ')}',
              ].join(' · '),
              key: const ValueKey('sess-pain-line'),
              style: TextStyle(fontSize: 13.5, color: e.pain.isEmpty ? c.textSecondary : c.warn),
            ),
        ],
      ]),
    );
  }

  Widget _setRow(BuildContext context, Session s, ExLog e, int i, bool isCurrent) {
    final c = Aigaio.of(context);
    final k = e.kind;
    final set = e.log[i];
    final band = isBand(k);
    final numStyle = TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: set.done ? c.textSecondary : c.text, fontFeatures: const [FontFeature.tabularFigures()]);
    // Λάστιχο: κουκκίδα στο χρώμα του και «30 lb» (σχέδια 9/11)· αλλιώς κιλά ή η ετικέτα του φορτίου.
    final loadText = !hasLoad(k) ? '' : (usesKg(k) ? kgText(set.load ?? 0) : (band ? '${(set.load ?? 0).round()} lb' : loadLabel(k, set.load)));
    Widget loadCell(TextStyle st) => Row(mainAxisSize: MainAxisSize.min, children: [
          if (band) BandDots(set.load, size: 16),
          Flexible(child: Text(loadText, maxLines: 1, overflow: TextOverflow.ellipsis, style: st)),
        ]);
    // Σετ που έγινε: γεμάτο πράσινο ✓· σετ που έρχεται: απαλό πλαίσιο με γκρι ✓ (πατιέται κι αυτό).
    Widget tick() => Semantics(
          button: true,
          label: set.done ? 'Αναίρεση σετ ${i + 1}' : 'Έγινε το σετ ${i + 1}',
          child: InkWell(
            key: ValueKey('sess-tick-$i'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => set.done ? t.untick(e, i) : _done(context, s, e, i),
            // 48 dp (πριν 46): το ελάχιστο για δάχτυλο, όπως τα υπόλοιπα κουμπιά της προπόνησης. Το ✓ πάνω στο πράσινο
            // με το χρώμα που διαβάζεται σε κάθε θέμα (τελικός έλεγχος, Συμβούλιο 5, U-1 και U-3).
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: set.done ? c.good : c.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: set.done ? c.good : c.hairline, width: set.done ? 2 : 1.5),
              ),
              child: Icon(Icons.check_rounded, color: set.done ? Aigaio.inkOn(c.good) : c.textTertiary),
            ),
          ),
        );
    if (isCurrent) {
      // Τρέχον σετ (σχέδια 9/11, 6β): μόνο οι μετρητές (όχι η τιμή δύο φορές), «Έγινε» από κάτω.
      // 13/11 (Συμβούλιο 5, Δ3): κουμπιά − / + 56 dp (ιδρωμένα χέρια, χωρίς να κοιτάς). Όπου δεν χωρούν οι δύο μετρητές
      // σε μία σειρά (στενή οθόνη), το Wrap βάζει τις επαναλήψεις από κάτω: ποτέ μικρότερα κουμπιά.
      // round1, U5-02 / U5-34: κάθε μετρητής με τη λέξη του δίπλα (στο κλειστό Fold πέφτουν ο ένας κάτω από τον άλλο και
      // δεν ξεχώριζαν), και ο αριθμός μεγαλύτερος (24 px). Ίδια κουμπιά 56 dp, ίδιο ύψος γραμμής.
      Widget named(Widget stepper, String word) => Row(mainAxisSize: MainAxisSize.min, children: [
            stepper,
            const SizedBox(width: 10),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(word, maxLines: 1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textSecondary)),
              ),
            ),
          ]);
      // Round 2 (R2-U2-10): ίδιο πλάτος τιμής στους δύο μετρητές, ώστε τα «+» και οι λέξεις «κιλά» / «επαναλήψεις» να
      // στοιχίζονται όταν ο ένας είναι κάτω από τον άλλο (πριν 60 και 44: 16 dp μετατόπιση).
      final valueWidth = usesKg(k) || band ? 60.0 : 88.0;
      final steppers = <Widget>[
        if (hasLoad(k))
          named(
            Stepper2(
              value: band ? '${(set.load ?? 0).round()}' : loadText,
              leading: band ? BandDots(set.load, size: 14) : null,
              width: valueWidth,
              button: 56,
              haptic: true,
              labelMinus: 'Λιγότερο βάρος',
              labelPlus: 'Περισσότερο βάρος',
              onMinus: shiftLoad(k, set.load, -1) == null ? null : () => t.setLoad(e, i, shiftLoad(k, set.load, -1)!),
              onPlus: shiftLoad(k, set.load, 1) == null ? null : () => t.setLoad(e, i, shiftLoad(k, set.load, 1)!),
            ),
            usesKg(k) ? 'κιλά' : (band ? 'lb' : 'βάρος'),
          ),
        named(
          Stepper2(
            value: '${set.reps}',
            width: hasLoad(k) ? valueWidth : 44.0,
            button: 56,
            haptic: true,
            labelMinus: 'Λιγότερες',
            labelPlus: 'Περισσότερες',
            onMinus: set.reps > 0 ? () => t.setReps(e, i, set.reps - 1) : null,
            onPlus: () => t.setReps(e, i, set.reps + 1),
          ),
          'επαναλήψεις',
        ),
      ];
      return KeyedSubtree(
        key: _currentKey,
        child: Container(
        key: ValueKey('sess-current-$i'),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(color: c.tint(c.exercise), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Σετ ${i + 1}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text))),
            Text('τώρα', style: TextStyle(fontSize: 13, color: c.textSecondary)),
          ]),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) => box.maxWidth < 470 || steppers.length < 2
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (var n = 0; n < steppers.length; n++) ...[if (n > 0) const SizedBox(height: 12), steppers[n]],
                  ])
                : Row(children: [Flexible(child: steppers[0]), const SizedBox(width: 24), Flexible(child: steppers[1])]),
          ),
          const SizedBox(height: 10),
          // «✓ Έγινε» πάντα δεξιά, το όνομα του λάστιχου αριστερά (με πολύ μεγάλα γράμματα το ένα κάτω από το άλλο).
          () {
            // R8-U3-07: η κουκκίδα στην 1η γραμμή του ονόματος όταν αυτό σπάει (όπως στη training_page), όχι στη μέση.
            final label = band
                ? Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.only(top: 2), child: BandDots(set.load, size: 14)),
                    Flexible(child: Text(bandName(set.load ?? 0), style: TextStyle(fontSize: 13.5, color: c.textSecondary))),
                  ])
                : const SizedBox.shrink();
            final doneBtn = Semantics(
                button: true,
                label: 'Έγινε το σετ ${i + 1}',
                excludeSemantics: true,
                child: FilledButton.icon(
                  key: ValueKey('sess-tick-$i'),
                  // Γράμματα που διαβάζονται σε κάθε θέμα: στα σκούρα το πράσινο είναι ανοιχτό και το λευκό χανόταν (U-3).
                  style: FilledButton.styleFrom(backgroundColor: c.good, foregroundColor: Aigaio.inkOn(c.good), minimumSize: const Size(120, 48)),
                  onPressed: () => _done(context, s, e, i),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Έγινε', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              );
            if (veryLargeText(context)) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (band) label,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: doneBtn),
              ]);
            }
            return Row(children: [Expanded(child: label), const SizedBox(width: 10), doneBtn]);
          }(),
        ]),
      ),
      );
    }
    if (veryLargeText(context)) {
      // Πολύ μεγάλα γράμματα: μία πρόταση ανά σετ («Σετ 1 · ● 30 lb × 14»), όχι στήλες με σπασμένες λέξεις.
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(children: [
          Expanded(
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
              Text('Σετ ${i + 1}', style: numStyle.copyWith(fontWeight: FontWeight.w600)),
              if (hasLoad(k)) loadCell(numStyle),
              Text('× ${set.reps}', style: numStyle),
            ]),
          ),
          tick(),
        ]),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(children: [
        SizedBox(width: _setColumn(context), child: Text('${i + 1}', style: numStyle)),
        if (hasLoad(k)) Expanded(child: loadCell(numStyle)),
        Expanded(child: Text('${set.reps}', style: numStyle)),
        SizedBox(width: 52, child: Align(alignment: Alignment.centerRight, child: tick())),
      ]),
    );
  }

  /// Ανοιχτό φύλλο «πόσες ακόμα θα έβγαζες;» (R8-U3-01): η ερώτηση για ✓ του ρολογιού περιμένει να κλείσει.
  bool _asking = false;

  Future<int?> _ask(BuildContext context, {required bool first, ExLog? e, ExLog? firstOf}) async {
    _asking = true;
    try {
      return await _askRir(context, first: first, e: e, firstOf: firstOf);
    } finally {
      _asking = false;
    }
  }

  /// Η απάντηση στο «Πρώτο σετ: πόσες ακόμα θα έβγαζες;» ([rir] 0–4, −1 = «Δεν ξέρω»): βάρος για τα επόμενα σετ, και τι
  /// άλλαξε (ή γιατί όχι). R8-U3-01: μόνο αν δεν απάντησε ήδη το ρολόι (η πρώτη απάντηση κερδίζει).
  void _calibrate(BuildContext context, ExLog e, int rir) {
    final r = t.answerFirst(e, rir);
    if (!r.applied || rir < 0) return;
    final v = r.load;
    // R8-A6-5: και όταν το «4+» δεν αλλάζει το βάρος (μεγάλο σκαλί), να λέγεται γιατί· πριν: τίποτα.
    final text = v != null ? 'Τα επόμενα σετ: ${loadLabel(e.kind, v)}.' : t.firstSetNote(e, rir);
    if (text != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// R8-U3-01: το 1ο σετ μιας άσκησης «πρώτης φοράς» έγινε ✓ στο ρολόι ([TrainingStore.firstAsk]): η ίδια ερώτηση με το ✓
  /// του κινητού, όσο δεν έχει γίνει στο μεταξύ άλλο σετ της άσκησης (τότε τα επόμενα σετ δεν περιμένουν πια τη βαθμονόμηση).
  Future<void> _firstFromWatch(Session s) async {
    final e = t.firstAsk;
    if (e == null || _asking || !mounted) return;
    t.firstAsk = null;
    if (t.current?.id != s.id || !s.items.contains(e) || !t.firstPending(e) || !e.log.first.done) return;
    final rir = await _ask(context, first: true, firstOf: e);
    if (!mounted || t.current?.id != s.id) return;
    if (rir != null) _calibrate(context, e, rir);
  }

  Future<void> _done(BuildContext context, Session s, ExLog e, int i) async {
    final first = t.asksFirstSet(e, i);
    t.tick(e, i);
    HapticFeedback.lightImpact();
    bool gone() => !context.mounted || t.current?.id != s.id;
    if (first) {
      final rir = await _ask(context, first: true, firstOf: e);
      if (gone()) return;
      // «Δεν ξέρω» (−1) μετρά κι αυτό ως απάντηση (R8-U3-01: η ερώτηση δεν ξαναγίνεται, ούτε στο ρολόι).
      if (rir != null) _calibrate(context, e, rir);
    }
    if (gone()) return;
    // R9-U3-08: η άσκηση τελειώνει όταν γίνουν ΟΛΕΣ οι γραμμές, και όσες πρόσθεσε το «+ Σετ» ([ExLog.rowsDone]), όπως
    // στο ρολόι: πριν, το ✓ του 3ου από 4 σετ ρωτούσε «Τελευταίο σετ» και πήγαινε στην επόμενη άσκηση.
    if (e.rowsDone) {
      if (e.rirAnswer == null) {
        final rir = await _ask(context, first: false, e: e);
        if (gone()) return;
        if (rir != null && rir >= 0) t.answer(e, rir);
      }
      if (gone()) return;
      final next = s.items.indexWhere((x) => !x.skipped && !x.rowsDone);
      if (next >= 0) {
        setState(() => _idx = next);
        _rest(e, exName(s.items[next].ex));
      } else if (s.isFree) {
        // Ελεύθερη: η επόμενη άσκηση δεν έχει διαλεχτεί ακόμα· το διάλειμμα μετρά κανονικά.
        _rest(e, 'νέα άσκηση');
      }
    } else {
      _rest(e, '${exName(e.ex)} · σετ ${e.done.length + 1}');
    }
  }

  /// «Πόσες ακόμα θα έβγαζες;» (0–4+). Στο τέλος της άσκησης και ενοχλήσεις.
  /// Δεν κλείνει κατά λάθος (έλεγχος 8/11): ή απάντηση ή «Δεν ξέρω» (−1, και τότε δεν ανεβαίνει τίποτα).
  /// R8-U3-01: [firstOf] = η άσκηση της ερώτησης του 1ου σετ· αν απαντηθεί στο ρολόι όσο το φύλλο είναι ανοιχτό (ή πάψει
  /// να εκκρεμεί), το φύλλο κλείνει μόνο του χωρίς απάντηση (null): ισχύει η απάντηση του ρολογιού.
  Future<int?> _askRir(BuildContext context, {required bool first, ExLog? e, ExLog? firstOf}) {
    var pick = -1;
    var closing = false;
    return showModalBottomSheet<int>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => ListenableBuilder(
        listenable: t,
        builder: (ctx, child) {
          final f = firstOf;
          if (f != null && !closing && !t.firstPending(f)) {
            closing = true;
            final route = ModalRoute.of(ctx);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // Μόνο αν το φύλλο είναι ακόμα το πάνω πάνω (ποτέ η σελίδα της προπόνησης από κάτω).
              if (ctx.mounted && route != null && route.isCurrent) Navigator.of(ctx).pop();
            });
          }
          return child!;
        },
        child: StatefulBuilder(builder: (ctx, set) {
        final c = Aigaio.of(ctx);
        // Με μεγάλα γράμματα το φύλλο κυλά (ποτέ ξεχείλισμα).
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(first ? 'Πρώτο σετ: πόσες ακόμα θα έβγαζες;' : 'Τελευταίο σετ: πόσες ακόμα θα έβγαζες;',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.25, color: c.text)),
            const SizedBox(height: 4),
            Text(
                first
                    ? 'Με καλή τεχνική. Από αυτό βρίσκεται το σωστό βάρος για τα επόμενα σετ.'
                    : 'Με καλή τεχνική. Αυτό είναι το «άφησε» του προγράμματος.',
                style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary)),
            const SizedBox(height: 14),
            Row(children: [
              for (var v = 0; v <= 4; v++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Material(
                      color: pick == v ? c.exerciseSolid : c.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: pick == v ? c.exerciseSolid : c.hairline, width: 1.5),
                      ),
                      child: InkWell(
                        key: ValueKey('rir-$v'),
                        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        onTap: () => set(() => pick = v),
                        child: SizedBox(
                          height: 54,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(v == 4 ? '4+' : '$v',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pick == v ? c.onSolid : c.text)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
            if (!first && e != null) ...[
              const SizedBox(height: 18),
              // Σχέδια 9/11 (6γ): πόνος σε κεχριμπάρι, χωρίς ✓ και χωρίς πράσινο.
              Text('Πόνεσε κάπου;', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
              Text('Μόνο αν ναι.', style: TextStyle(fontSize: 13, color: c.textSecondary)),
              const SizedBox(height: 10),
              _painChips(ctx, e, set),
              if (e.pain.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Σημειώνεται στη σύνοψη της προπόνησης.', style: TextStyle(fontSize: 13.5, color: c.warn)),
              ],
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('rir-ok'),
              style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(52)),
              onPressed: pick < 0
                  ? null
                  : () {
                      closing = true;
                      Navigator.of(ctx).pop(pick);
                    },
              child: const Text('Συνέχεια'),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const ValueKey('rir-unknown'),
              style: TextButton.styleFrom(foregroundColor: c.textSecondary, minimumSize: const Size.fromHeight(48)),
              onPressed: () {
                closing = true;
                Navigator.of(ctx).pop(-1);
              },
              child: const Text('Δεν ξέρω'),
            ),
          ]),
        );
      }),
      ),
    );
  }

  /// Τα σημεία της ενόχλησης (σχέδια 9/11, 6γ: κεχριμπάρι, χωρίς ✓ και χωρίς πράσινο). Στο φύλλο του τελευταίου σετ και
  /// στο «Πόνεσε κάπου;» ([_painSheet]).
  Widget _painChips(BuildContext ctx, ExLog e, StateSetter set) {
    final c = Aigaio.of(ctx);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final p in painNames.entries)
        () {
          final on = e.pain.contains(p.key);
          return Semantics(
            selected: on,
            button: true,
            child: Material(
              color: on ? c.warnBg : c.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: on ? c.warnLine : c.hairline, width: on ? 2 : 1.5),
              ),
              child: InkWell(
                key: ValueKey('pain-${p.key}'),
                customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () => set(() => t.togglePain(e, p.key)),
                child: Padding(
                  // round1, U5-12: 48 dp ύψος (πριν 43), εκεί που τα χέρια είναι πιο κουρασμένα.
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Text(p.value,
                      style: TextStyle(fontSize: 15, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? c.warn : c.text)),
                ),
              ),
            ),
          );
        }(),
    ]);
  }

  /// R7-A6-2: «Πόνεσε κάπου;» σε οποιοδήποτε σημείο της άσκησης (και αν σταματάς νωρίτερα). Η επόμενη φορά της άσκησης
  /// βγαίνει πιο ελαφριά ([nextTarget]). Στο ρολόι δεν υπάρχει αυτή η επιλογή.
  Future<void> _painSheet(BuildContext context, ExLog e) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = Aigaio.of(ctx);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Πόνεσε κάπου;', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.25, color: c.text)),
            const SizedBox(height: 4),
            Text('${exName(e.ex)}. Αν πονάς, σταμάτα την άσκηση: η επόμενη φορά της βγαίνει πιο ελαφριά.',
                style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary)),
            const SizedBox(height: 14),
            _painChips(ctx, e, set),
            if (e.pain.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Σημειώνεται στη σύνοψη της προπόνησης.', style: TextStyle(fontSize: 13.5, color: c.warn)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('pain-ok'),
              style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(52)),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Εντάξει'),
            ),
          ]),
        );
      }),
    );
  }

  Widget _restBar(BuildContext context, Session s) {
    return ValueListenableBuilder<int>(
      valueListenable: _tick,
      builder: (context, _, __) {
        final end = _restEnd;
        if (end == null) return const SizedBox.shrink();
        final left = end.difference(t.now);
        final secs = left.inSeconds < 0 ? 0 : left.inSeconds + (left.inMilliseconds % 1000 > 0 ? 1 : 0);
        Widget b(String label, VoidCallback f, Key key) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: FilledButton(
                key: key,
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF0F172A), minimumSize: const Size(56, 42)),
                onPressed: f,
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            );
        // R7-U4-2: η ετικέτα της ζωντανής περιοχής αλλάζει μόνο στις στιγμές του [restSpeaksNow]· η ακριβής αντίστροφη
        // μέτρηση είναι δικό της στοιχείο (λέγεται όταν το αγγίξεις, όχι μόνη της κάθε δευτερόλεπτο).
        if (_spokenEnd != end || restSpeaksNow(_spokenSecs, secs)) {
          _spokenEnd = end;
          _spokenSecs = secs;
        }
        return Semantics(
          container: true,
          liveRegion: true,
          label: 'Διάλειμμα, ${restLeftText(_spokenSecs ?? secs)}',
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            // round1, U5-07: στα σκούρα θέματα η λωρίδα δεν ξεχώριζε από το φόντο (1,05–1,10:1)· πορτοκαλί περίγραμμα.
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(20),
              border: Aigaio.of(context).dark ? Border.all(color: Aigaio.of(context).exercise, width: 1.5) : null,
            ),
            child: Row(children: [
              Expanded(
                child: Semantics(
                  key: const ValueKey('rest-left'),
                  container: true,
                  label: 'Τώρα ${restLeftText(secs)}',
                  child: ExcludeSemantics(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('ΔΙΑΛΕΙΜΜΑ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: Color(0xFFB8C0CC))),
                      Text('${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
                    ]),
                  ),
                ),
              ),
              b('+30″', () => _restAdd(30), const ValueKey('rest-plus')),
              // R7-U3 Β-Α2: ίδια λέξη με το ρολόι («Πάμε»)· εκεί το «Συνέχεια» είναι του περπατήματος.
              b('Πάμε', _restStop, const ValueKey('rest-stop')),
            ]),
          ),
        );
      },
    );
  }

  Widget _actions(BuildContext context, Session s, ExLog e) {
    final c = Aigaio.of(context);
    // round1, U5-08: όταν όλες οι ασκήσεις έγιναν (και με άλλη σειρά), το κουμπί λέει «Τέλος προπόνησης».
    final allDone = s.items.every((x) => x.skipped || x.rowsDone);
    final last = (allDone && !s.isFree) || _idx >= s.items.length - 1;
    // Μικρό εσωτερικό περιθώριο: στο στενό κινητό οι λέξεις χωράνε σε μία γραμμή.
    const pad = EdgeInsets.symmetric(horizontal: 6);
    // Σχέδια 9/11 (6β): δύο κουμπιά· η «Αλλαγή άσκησης» πήγε στο ⋮.
    return Row(children: [
      Expanded(
        flex: 5,
        child: OutlinedButton(
          key: const ValueKey('sess-skip'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              padding: pad,
              foregroundColor: c.text,
              // R2-U2-01: ανενεργή (με γραμμένα σετ) σε αχνό γκρι, όπως στη Διατροφή· ποτέ πιο «ζωντανή» από την ενεργή.
              disabledForegroundColor: c.textTertiary),
          onPressed: e.done.isNotEmpty ? null : () => t.skip(e, !e.skipped),
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(e.skipped ? 'Αναίρεση' : 'Παράλειψη', maxLines: 1, softWrap: false)),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 8,
        child: FilledButton(
          key: const ValueKey('sess-next'),
          style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(52), padding: pad),
          onPressed: last ? (s.isFree ? () => _addExercise(context) : () => _finish(context)) : () => setState(() => _idx++),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(last ? (s.isFree ? 'Νέα άσκηση' : 'Τέλος προπόνησης') : 'Επόμενη άσκηση',
                maxLines: 1, softWrap: false, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    ]);
  }

  /// «Ελεύθερη άσκηση»: διάλεξε από τη βιβλιοθήκη. Αν είναι ήδη μέσα, πάει σε αυτή (όχι διπλή).
  Future<void> _addExercise(BuildContext context) async {
    final s = t.current;
    if (s == null) return;
    final id = await pickExercise(context, already: {for (final e in s.items) e.ex});
    if (id == null || t.current?.id != s.id) return;
    final at = s.items.indexWhere((e) => e.ex == id);
    if (at >= 0) {
      setState(() => _idx = at);
      return;
    }
    t.addExercise(id);
  }

  Widget _emptyFree(BuildContext context, Session s) {
    final c = Aigaio.of(context);
    // round1, U6-27: «πίσω» από μια άδεια «Ελεύθερη άσκηση» (καμία άσκηση, κανένας παλμός) δεν αφήνει ανοιχτή προπόνηση
    // που μπλοκάρει τη μέρα· δεν υπάρχει τίποτα να χαθεί.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && t.current?.id == s.id && s.items.isEmpty && s.hr.isEmpty) {
          t.discard();
          TrainingDevice.restCancel();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(s.name, maxLines: 1, softWrap: false, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        actions: [
          _finishButton(context),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              _hr(const EdgeInsets.only(bottom: 12)),
              AppCard(
                key: const ValueKey('free-empty'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Διάλεξε την πρώτη άσκηση', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
                  const SizedBox(height: 6),
                  Text('Μετά από κάθε άσκηση προσθέτεις την επόμενη. Τα κιλά βγαίνουν από τις προηγούμενες φορές της ίδιας άσκησης· '
                      'σε άσκηση που κάνεις πρώτη φορά, μετά το 1ο σετ σε ρωτάει πώς πήγε, για να βρεθεί το σωστό βάρος.',
                      style: TextStyle(fontSize: 14.5, height: 1.45, color: c.textSecondary)),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    key: const ValueKey('free-add'),
                    style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(52)),
                    onPressed: () => _addExercise(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Πρόσθεσε άσκηση', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
      ),
    );
  }

  Future<void> _swap(BuildContext context, ExLog e) async {
    final lib = ExLibrary.loaded;
    if (lib == null) return;
    final base = lib.byId(e.swappedFrom ?? e.ex);
    final ids = <String>{...?base?.alt, if (e.swappedFrom != null) e.swappedFrom!};
    for (final x in lib.list) {
      if (x.group == base?.group) ids.add(x.id);
    }
    ids.remove(e.ex);
    // R7-A6-9: ασκήσεις «με προσοχή» (π.χ. βυθίσεις, ώμοι) στο τέλος της λίστας και με την προειδοποίησή τους, όπως στο
    // «Πρόσθεσε άσκηση» (ex_picker.dart)· πριν φαίνονταν σαν κάθε άλλη, ακόμα και μετά από ενόχληση στον ώμο.
    final ordered = [
      for (final id in ids) if (lib.byId(id)?.caution == null) id,
      for (final id in ids) if (lib.byId(id)?.caution != null) id,
    ];
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final c = Aigaio.of(ctx);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
              Text('Αντί για ${exName(e.ex)}', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c.text)),
              const SizedBox(height: 8),
              for (final id in ordered)
                ListTile(
                  key: ValueKey('swap-$id'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(exName(id)),
                  subtitle: lib.byId(id)?.caution == null
                      ? Text(lib.byId(id)?.equip ?? '')
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(lib.byId(id)?.equip ?? ''),
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(Icons.warning_amber_rounded, size: 15, color: c.warn),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(lib.byId(id)?.caution ?? '',
                                  key: ValueKey('swap-caution-$id'),
                                  style: TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600, color: c.warn)),
                            ),
                          ]),
                        ]),
                  trailing: (base?.alt.contains(id) ?? false) ? Text('προτεινόμενη', style: TextStyle(color: c.exercise, fontSize: 12.5)) : null,
                  onTap: () => Navigator.of(ctx).pop(id),
                ),
            ]),
          ),
        );
      },
    );
    if (pick != null) t.swap(e, pick);
  }

  Future<void> _finish(BuildContext context) async {
    final s = t.current;
    if (s == null) return;
    if (s.setsDone == 0) {
      final drop = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Κανένα σετ ακόμα'),
          content: const Text('Να σβηστεί αυτή η προπόνηση;'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Άκυρο')),
            TextButton(key: const ValueKey('sess-drop'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Σβήσιμο')),
          ],
        ),
      );
      if (drop == true) {
        t.discard();
        TrainingDevice.restCancel();
        if (context.mounted) Navigator.of(context).pop();
      }
      return;
    }
    // Νωρίτερα από το πρόγραμμα: ερώτηση, για να μη γραφτεί κατά λάθος μισή προπόνηση (η πρόοδος βγαίνει από αυτή).
    // R9-A6-5: ανά άσκηση, όχι με το σύνολο: ένα «+ Σετ» σε άλλη άσκηση δεν «καλύπτει» ένα σετ που λείπει. Μετρούν και οι
    // γραμμές που πρόσθεσες και δεν έγιναν ([ExLog.rowsDone], R9-U3-08): χωρίς αυτές δεν έγινε η ερώτηση «Τελευταίο σετ».
    final open = s.items.where((e) => !e.skipped && !e.rowsDone);
    final total = s.items.where((e) => !e.skipped).fold<int>(0, (a, e) => a + (e.log.length > e.sets ? e.log.length : e.sets));
    final did = s.items.where((e) => !e.skipped).fold<int>(0, (a, e) => a + e.done.length);
    if (open.isNotEmpty) {
      final end = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Τελείωσες νωρίτερα;'),
          content: Text('Έγιναν $did από $total σετ. Όσα δεν έγιναν δεν μετράνε στην πρόοδο. Αν σταμάτησες από πόνο, '
              'πάτα «Πόνεσα»: η επόμενη φορά της άσκησης βγαίνει πιο ελαφριά.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop('back'), child: const Text('Συνέχεια προπόνησης')),
            // R7-A6-2: σταμάτησες από πόνο: να μείνει γραμμένο (πριν δεν έμενε κανένα ίχνος).
            TextButton(key: const ValueKey('sess-finish-pain'), onPressed: () => Navigator.of(ctx).pop('pain'), child: const Text('Πόνεσα')),
            TextButton(key: const ValueKey('sess-finish-ok'), onPressed: () => Navigator.of(ctx).pop('end'), child: const Text('Τέλος')),
          ],
        ),
      );
      if ((end != 'end' && end != 'pain') || !context.mounted) return;
      if (end == 'pain') {
        // Η άσκηση που φαίνεται (εκεί σταμάτησες)· αν είναι ήδη τελειωμένη, η πρώτη που δεν τελείωσε και έχει σετ.
        final shown = _idx >= 0 && _idx < s.items.length ? s.items[_idx] : null;
        ExLog? painEx = shown != null && !shown.rowsDone ? shown : null;
        for (final x in s.items) {
          if (painEx == null && !x.skipped && !x.rowsDone && x.done.isNotEmpty) painEx = x;
        }
        painEx ??= shown;
        if (painEx != null) await _painSheet(context, painEx);
        if (!context.mounted || t.current?.id != s.id) return;
      }
    }
    _restStop();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(SummaryPage.route(t, s, live: true));
  }
}

/// Τέλος προπόνησης (ή μια παλιά προπόνηση): στοιχεία, τι αλλάζει την επόμενη φορά, πώς ένιωσες.
class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key, required this.training, required this.session, this.live = false});
  final TrainingStore training;
  final Session session;
  final bool live;

  static Route<void> route(TrainingStore t, Session s, {bool live = false}) => MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'Τέλος προπόνησης'), builder: (_) => SummaryPage(training: t, session: s, live: live));

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  int? _feel;

  @override
  void initState() {
    super.initState();
    _feel = widget.session.feel;
    // Οι παλμοί είναι στο δικό τους αρχείο (V-A-02): φορτώνονται τώρα, μόνο για αυτή τη σύνοψη.
    if (!widget.session.hrLoaded) {
      widget.training.ensureHr(widget.session).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  static const _feels = ['Πολύ εύκολα', 'Εύκολα', 'Καλά', 'Δύσκολα', 'Πολύ δύσκολα'];

  /// Διαγραφή με επιβεβαίωση· μετά «Αναίρεση» για λίγα δευτερόλεπτα, στην οθόνη από όπου ήρθες.
  Future<void> _delete(BuildContext context) async {
    final t = widget.training;
    final s = widget.session;
    final what = s.isCardio ? 'περπατήματος' : 'προπόνησης';
    final desc = s.isCardio
        ? '${shortDayDate(s.start)}, ${hoursMinutes(s.cardioMinutes ?? s.duration.inMinutes)}${kmValue(s) == null ? '' : ', ${kmValue(s)} km'}'
        : '${shortDayDate(s.start)}, ${s.name}, ${s.setsDone} σετ';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = Aigaio.of(ctx);
        return AlertDialog(
          title: Text('Διαγραφή $what;'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$desc. Φεύγει από το ιστορικό, την πρόοδο και τις συγκρίσεις.', style: TextStyle(fontSize: 15, height: 1.4, color: c.text)),
            const SizedBox(height: 8),
            Text('Αν κάνεις επαναφορά από παλιό αντίγραφο, δεν ξαναγυρίζει.', style: TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary)),
          ]),
          actions: [
            TextButton(key: const ValueKey('del-cancel'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Άκυρο')),
            FilledButton(
              key: const ValueKey('del-ok'),
              style: FilledButton.styleFrom(backgroundColor: c.bad, foregroundColor: Aigaio.inkOn(c.bad)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Διαγραφή'),
            ),
          ],
        );
      },
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final gone = t.deleteSession(s.id);
    Navigator.of(context).pop();
    if (gone == null) return;
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      // Round8 (R8-U2-1, f1): με «Αναίρεση» το μήνυμα δεν θα έκλεινε ποτέ μόνο του (Flutter ≥ 3.38).
      persist: false,
      content: Text('Διαγράφηκε: ${gone.isCardio ? 'περπάτημα' : gone.name} ${shortDayDate(gone.start)}'),
      action: SnackBarAction(label: 'Αναίρεση', onPressed: () => t.undoDelete(gone)),
    ));
  }

  // Round 1 (U5-30, αίτημα f9 → f6b): η σελίδα/το φύλλο ανοίγει με push, έξω από το ExerciseTheme της κατηγορίας·
  // χωρίς αυτό διακόπτες και δευτερεύοντα κουμπιά έβγαιναν μπλε δίπλα στα πορτοκαλί.
  @override
  Widget build(BuildContext context) => ExerciseTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final t = widget.training;
    final s = widget.session;
    final c = Aigaio.of(context);
    // Με το ρολόι της αποθήκης (όχι της συσκευής), για να ταιριάζει με την αρχή της προπόνησης.
    // Ξεχασμένη προπόνηση: η διάρκεια ως το τελευταίο ✓, όπως θα γραφτεί με την «Αποθήκευση» (όχι 20 ώρες).
    // R9-A8-1: ο ίδιος κανόνας με το [TrainingStore.finish]: από το τελευταίο ✓ ([Session.lastTick]), όχι τη «Συνέχεια».
    final stale = t.current == s && t.now.difference(s.lastTick) >= TrainingStore.staleAfter;
    final mins = (s.end ?? (stale ? s.lastTick : t.now)).difference(s.start).inMinutes;
    final prog = t.program?.workout(s.workout);

    // R7-A6-4: «Την επόμενη φορά» όπως θα τη δώσει η επόμενη προπόνηση: με τα σετ και το εύρος του προγράμματος (όχι
    // το κάτω όριο της μέρας, που μπορεί να ήταν χαμηλωμένο), και για μια εναλλακτική ο στόχος της άσκησης του
    // προγράμματος, που ξαναμπαίνει την επόμενη φορά (εκτός αν είναι η πιο δύσκολη παραλλαγή της, που συνεχίζει).
    PlanItem? planned(ExLog e) {
      for (final i in prog?.items ?? const <PlanItem>[]) {
        if (i.ex == e.ex || i.ex == e.swappedFrom) return i;
      }
      return null;
    }

    PlanItem itemFor(ExLog e) {
      final p = planned(e);
      if (p == null) return PlanItem(ex: e.ex, sets: e.sets, lo: e.lo, hi: e.hi, rir: e.rir, rest: e.rest);
      if (p.ex == e.ex) return p;
      if (p.next == e.ex) return PlanItem(ex: e.ex, sets: p.sets, lo: p.lo, hi: p.hi, rir: p.rir, rest: p.rest, note: p.note);
      return p;
    }

    // round1, U5-06: διάρκεια σε λέξεις («60» / «λεπτά», όχι «60′»). U5-10: ένα όνομα για το ίδιο νούμερο («σύνολο»), και
    // μία γραμμή όταν μετρούν και οι δύο αλτήρες ενός ζευγαριού (αλλιώς από τις γραμμές βγαίνει το μισό).
    final shownMins = s.isCardio ? (s.cardioMinutes ?? mins) : mins;
    final minsLabel = shownMins == 1 ? 'λεπτό' : 'λεπτά';
    final pairs = !s.isCardio && s.volume > 0 && s.items.any((x) => x.kind == LoadKind.dbPair && x.done.isNotEmpty);
    // R7-A6-7: και στις ασκήσεις μίας πλευράς τη φορά, ένα ✓ = δεξιά και αριστερά.
    final sides = !s.isCardio && s.volume > 0 && s.items.any((x) => perSideExercises.contains(x.ex) && usesKg(x.kind) && x.done.isNotEmpty);
    final stats0 = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          for (final (v, l) in s.isCardio
              ? [
                  ('$shownMins', minsLabel),
                  (kmValue(s) ?? '—', distanceFromSteps(s) ? 'km (από βήματα)' : 'km'),
                  (s.steps == null ? '—' : thousands(s.steps!), 'βήματα'),
                ]
              : [('$shownMins', minsLabel), ('${s.setsDone}', 'σετ'), (s.volume > 0 ? thousands(s.volume.round()) : '—', 'kg σύνολο')])
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(v, maxLines: 1, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c.text)),
                ),
                Text(l, style: TextStyle(fontSize: 13, color: c.textSecondary)),
              ]),
            ),
        ]),
        if (pairs || sides) ...[
          const SizedBox(height: 8),
          Text(
              pairs && sides
                  ? 'Στα ζευγάρια αλτήρων μετράνε και οι δύο αλτήρες, και στις ασκήσεις μίας πλευράς και οι δύο πλευρές.'
                  : pairs
                      ? 'Στα ζευγάρια αλτήρων μετράνε και οι δύο αλτήρες.'
                      : 'Στις ασκήσεις μίας πλευράς μετράνε και οι δύο πλευρές.',
              key: const ValueKey('sum-pairs'),
              style: TextStyle(fontSize: 13, height: 1.35, color: c.textSecondary)),
        ],
      ]),
    );

    final next = <Widget>[];
    final shownNext = <String>{};
    for (final e in s.items) {
      if (e.done.isEmpty && e.pain.isEmpty) continue;
      if (e.skipped && e.pain.isEmpty) continue;
      final item = itemFor(e);
      // Μία γραμμή ανά άσκηση της επόμενης φοράς (η άσκηση που άλλαξε και η εναλλακτική της δίνουν την ίδια).
      if (!shownNext.add(item.ex)) continue;
      final own = [for (final x in s.items) if (x.ex == item.ex) (s.start, x)];
      final history = widget.live ? [...own, ...t.historyOf(item.ex)] : t.historyOf(item.ex);
      // R9-A6-8: σε σύνοψη παλιότερης προπόνησης, αν η άσκηση έγινε και αργότερα, ο στόχος «Την επόμενη φορά» βγαίνει
      // από εκείνες τις μεταγενέστερες φορές και δεν αντιστοιχεί σε αυτή τη σύνοψη: δεν δείχνεται (ο σημερινός στόχος
      // φαίνεται στην Άσκηση). Αν αυτή είναι η τελευταία φορά της άσκησης, ο στόχος είναι πράγματι ο επόμενος.
      if (!widget.live && history.any((h) => h.$1.isAfter(s.start))) continue;
      final tg = nextTarget(item, history, t.now, caution: TrainingStore.isCaution(item.ex));
      final (col, arrow) = changeLook(context, tg.change);
      next.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 2, children: [
            Text(exName(item.ex), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
            Text(
              tg.variant != null ? '→ ${exName(tg.variant!)}' : '${targetLine(item, tg)}$arrow',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: col),
            ),
          ]),
          Text(tg.reason, style: TextStyle(fontSize: 13, height: 1.35, color: c.textSecondary)),
        ]),
      ));
    }

    // Ανά άσκηση: κάθε σετ με κιλά × επαναλήψεις και, αν υπάρχουν παλμοί, ♥ σετ και ♥ διάλειμμα (9/11).
    // round1, S6-8 (f6a): η αρχή κάθε σετ από τον ρυθμό της βιβλιοθήκης.
    final perEx = sessionSetHr(s, repSeconds: TrainingStore.repSeconds);
    final withHr = perEx.isNotEmpty;
    final exCards = <Widget>[
      for (var k = 0; k < s.items.length; k++)
        _ExerciseCard(e: s.items[k], hr: withHr ? perEx[k] : null, showHr: withHr, key: ValueKey('sum-ex-$k')),
    ];
    final hrCard = s.hrMax == null && !s.hasHr ? null : HrCard(session: s);

    // round1, S6-9 (f6a): προπόνηση που έκλεισε σήμερα από το ρολόι (ή περπάτημα): το «Πώς ένιωσες;» απαντιέται και εδώ, και
    // γράφεται αμέσως (t.setFeel). Παλιότερες: μόνο για ανάγνωση.
    final feelToday = !widget.live && t.sessions.any((x) => x.id == s.id) && sameDay(s.end ?? s.start, t.now);
    final feel = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Πώς ένιωσες;', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < 5; i++)
            Pill(
              key: ValueKey('feel-${i + 1}'),
              label: _feels[i],
              selected: _feel == i + 1,
              onTap: widget.live
                  ? () => setState(() => _feel = i + 1)
                  : feelToday
                      ? () {
                          t.setFeel(s, i + 1);
                          setState(() => _feel = i + 1);
                        }
                      : () {},
            ),
        ]),
      ]),
    );

    final nextCard = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Την επόμενη φορά', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
        ...next,
      ]),
    );

    // Fold/tablet: αριστερά τα στοιχεία, οι παλμοί και ό,τι άλλο· δεξιά οι ασκήσεις με τα σετ. Στο κινητό μία στήλη.
    final exRight = !s.isCardio && withHr;
    final del = widget.live || !t.sessions.any((x) => x.id == s.id)
        ? null
        : OutlinedButton.icon(
            key: const ValueKey('summary-delete'),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.bad,
              side: BorderSide(color: c.bad.withValues(alpha: .5)),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => _delete(context),
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(s.isCardio ? 'Διαγραφή περπατήματος' : 'Διαγραφή προπόνησης', style: const TextStyle(fontWeight: FontWeight.w600)),
          );
    // Με παλμούς οι ασκήσεις πάνε δεξιά (Fold ανοιχτό: δίπλα στο γράφημα)· χωρίς, όπως πριν.
    final others = <Widget>[
      if (next.isNotEmpty) nextCard,
      if (widget.live || s.feel != null || feelToday) feel,
      if (del != null) del,
    ];
    // Περπάτημα (9/11): ρυθμός, βήματα/λεπτό, παύσεις, ανά km (με GPS), πτώση παλμών στο 1′.
    final km = s.isCardio ? walkSplits(s) : const <KmSplit>[];
    final walk = <Widget>[
      // Σχέδια 12/11 (4ε): χρόνος στη ζώνη και «τεστ ομιλίας» στα πρώτα περπατήματα.
      if (ZoneTimeCard.shows(s)) ZoneTimeCard(session: s),
      if (TalkTestCard.shows(s, HealthStore.shared)) TalkTestCard(session: s, health: HealthStore.shared!),
      if (km.isNotEmpty) KmCard(splits: km),
      if (RecoveryCard.shows(s)) RecoveryCard(session: s),
    ];
    final extra = s.isCardio && WalkExtraCard.shows(s) ? WalkExtraCard(session: s) : null;
    // Γράφτηκε ως το τελευταίο στιγμιότυπο, γιατί η εφαρμογή του ρολογιού έκλεισε απότομα (V-A-03).
    final notes = [
      if (s.partial) 'Γράφτηκε ως τις ${hm(s.end ?? s.start)}: η εφαρμογή του ρολογιού έκλεισε πριν το «Τέλος».',
      // Έλεγχος του #91 (S1): το αρχείο παλμών δεν διαβάστηκε· κρατήθηκε, δεν σβήστηκε.
      if (s.hrBad != null) 'Οι παλμοί αυτής της προπόνησης δεν διαβάστηκαν· το αρχείο τους κρατήθηκε στην άκρη.',
    ];
    final partialNote = notes.isEmpty
        ? null
        : Padding(
            key: ValueKey(s.partial ? 'summary-partial' : 'summary-hrbad'),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(notes.join(' '), style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary)),
          );
    final stats = partialNote == null ? stats0 : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [stats0, const SizedBox(height: 8), partialNote]);
    final List<Widget> left, right;
    if (s.isCardio) {
      left = [stats, if (extra != null) extra, if (hrCard != null) hrCard];
      right = [...walk, ...others];
    } else {
      left = [stats, if (hrCard != null) hrCard, if (!exRight) ...exCards, if (exRight) ...others];
      right = [if (exRight) ...exCards else ...others];
    }
    final narrow = s.isCardio
        ? <Widget>[stats, if (extra != null) extra, if (hrCard != null) hrCard, ...walk, ...others]
        : <Widget>[stats, if (hrCard != null) hrCard, ...exCards, ...others];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.live
            // round1, U5-11: ο χρήστης πάτησε ο ίδιος «Τέλος»· όχι «σταμάτησε», που μοιάζει με σφάλμα.
            ? (s.items.every((e) => e.skipped || e.rowsDone) ? 'Μπράβο, τελείωσες' : 'Τέλος προπόνησης')
            : '${shortDayDate(s.start)} · ${s.name}'),
        automaticallyImplyLeading: !widget.live,
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, k) {
          const gap = SizedBox(height: 12);
          List<Widget> spaced(List<Widget> l) => [for (var i = 0; i < l.length; i++) ...[if (i > 0) gap, l[i]]];
          if (k.maxWidth < 720) {
            return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: spaced(narrow));
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(left))),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(right))),
                ]),
              ),
            ),
          );
        }),
      ),
      bottomNavigationBar: !widget.live
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  // Πίσω στην προπόνηση (αν πατήθηκε «Τέλος» κατά λάθος): τίποτα δεν έχει γραφτεί ακόμα ως τελειωμένο.
                  OutlinedButton(
                    key: const ValueKey('summary-back'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                    onPressed: () => Navigator.of(context).pushReplacement(SessionPage.route(t)),
                    child: const Text('Πίσω'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('summary-save'),
                      style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(52)),
                      onPressed: () {
                        t.finish(feel: _feel);
                        TrainingDevice.restCancel();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Αποθήκευση', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}

/// Μία άσκηση στη σύνοψη: κάθε σετ (κιλά × επαναλήψεις) και, με παλμούς, ♥ σετ / ♥ διάλειμμα και μέσος όρος.
class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({super.key, required this.e, required this.hr, required this.showHr});
  final ExLog e;
  final ExHr? hr;
  final bool showHr;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final head = TextStyle(fontSize: 12.5, color: c.textSecondary);
    final cell = TextStyle(fontSize: 15, color: c.text, fontFeatures: const [FontFeature.tabularFigures()]);
    final strong = cell.copyWith(fontWeight: FontWeight.w700);
    final done = [for (var i = 0; i < e.log.length; i++) if (e.log[i].done) i];
    // round1, U5-13: λάστιχα με κουκκίδα και «30 lb × 14» σε μία γραμμή, και επικεφαλίδα που λέει «λάστιχο», όχι «κιλά».
    final band = e.kind == LoadKind.band || e.kind == LoadKind.bandPair || e.kind == LoadKind.bandAssist;
    // Κουκκίδες μόνο για ένα λάστιχο (ή τη βοήθεια)· το ζευγάρι λάστιχων κρατά το «/πλευρά» του loadLabel.
    final dots = e.kind == LoadKind.band || e.kind == LoadKind.bandAssist;
    Widget setCell(SetLog x) {
      if (!hasLoad(e.kind)) return Text('${x.reps}', style: cell);
      if (dots && (x.load ?? 0) > 0) {
        return Row(children: [
          BandDots(x.load, size: 14),
          Flexible(child: Text('${(x.load ?? 0).round()}\u00A0lb × ${x.reps}', maxLines: 1, overflow: TextOverflow.ellipsis, style: cell)),
        ]);
      }
      return Text('${loadLabel(e.kind, x.load)} × ${x.reps}', style: cell);
    }
    final headText = usesKg(e.kind)
        ? 'κιλά × επαναλήψεις'
        : e.kind == LoadKind.bandAssist
            ? 'βοήθεια × επαναλήψεις'
            : band
                ? 'λάστιχο × επαναλήψεις'
                : hasLoad(e.kind)
                    ? 'βάρος × επαναλήψεις'
                    : 'επαναλήψεις';
    Widget row(List<Widget> cells, {bool line = true}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: line ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
          child: Row(children: [
            SizedBox(width: 40, child: cells[0]),
            // Round 2 (R2-U2-02): 8 dp ανάμεσα στη μεσαία στήλη και στους παλμούς (πριν «…επαναλήψεις♥ στο σετ»).
            Expanded(child: showHr ? Padding(padding: const EdgeInsets.only(right: 8), child: cells[1]) : cells[1]),
            if (showHr) ...[SizedBox(width: 66, child: cells[2]), const SizedBox(width: 8), SizedBox(width: 84, child: cells[3])],
          ]),
        );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(exName(e.ex), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text))),
          if (showHr)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.favorite_rounded, size: 15, color: hr?.avg == null ? c.textSecondary : c.exercise),
              const SizedBox(width: 4),
              Text(hr?.avg == null ? '—' : '~${hr!.avg}',
                  key: ValueKey('sum-ex-avg-${e.ex}'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: hr?.avg == null ? c.textSecondary : c.exercise)),
            ]),
        ]),
        if (showHr && hr?.avg != null) Text('μέσος όρος των σετ', style: head),
        const SizedBox(height: 6),
        if (e.skipped || done.isEmpty)
          Text(e.skipped ? 'Παραλείφθηκε' : 'Δεν έγινε', style: TextStyle(fontSize: 14.5, color: c.textSecondary))
        else ...[
          row([
            Text('σετ', style: head),
            FittedBox(
                key: ValueKey('sum-head-${e.ex}'),
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(headText, maxLines: 1, softWrap: false, style: head)),
            _HeartLabel('στο σετ', style: head, color: c.textSecondary),
            _HeartLabel('διάλειμμα', style: head, color: c.textSecondary),
          ]),
          for (var j = 0; j < done.length; j++)
            () {
              final i = done[j];
              final h = hr != null && i < hr!.sets.length ? hr!.sets[i] : null;
              final hSet = h?.set, hRest = h?.rest;
              return row([
                Text('${j + 1}', style: strong),
                setCell(e.log[i]),
                Text(h?.set == null ? '—' : '~${h!.set}', key: ValueKey('sum-set-${e.ex}-$i'), style: h?.set == null ? cell.copyWith(color: c.textSecondary) : strong),
                // round1, U5-16: βέλος μόνο όταν οι παλμοί του διαλείμματος είναι πράγματι πιο κάτω από του σετ, και
                // ουδέτερο χρώμα (η πτώση εξαρτάται από τη διάρκεια του διαλείμματος, όχι «καλό»).
                Text(hRest == null ? '—' : (hSet != null && hRest < hSet ? '↓ $hRest' : '$hRest'),
                    style: hRest == null ? cell.copyWith(color: c.textSecondary) : cell),
              ], line: j < done.length - 1);
            }(),
        ],
        // round1, U5-19: η ενόχληση που σημείωσες γράφεται στη σύνοψη της άσκησης, όπως λέει το φύλλο.
        if (e.pain.isNotEmpty)
          Padding(
            key: ValueKey('sum-pain-${e.ex}'),
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: c.warn),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Ενόχληση: ${e.pain.map((p) => painNames[p] ?? p).join(', ')}',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.warn)),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Μικρή καρδιά + λέξη (το «♥» ως γράμμα δεν υπάρχει σε κάθε γραμματοσειρά).
class _HeartLabel extends StatelessWidget {
  const _HeartLabel(this.text, {required this.style, required this.color});
  final String text;
  final TextStyle style;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.favorite_rounded, size: 12, color: color),
        const SizedBox(width: 3),
        Flexible(child: Text(text, style: style, overflow: TextOverflow.ellipsis)),
      ]);
}
