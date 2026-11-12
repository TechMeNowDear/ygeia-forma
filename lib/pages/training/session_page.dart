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

  @override
  void initState() {
    super.initState();
    final s = t.current;
    if (s != null) {
      final i = s.items.indexWhere((e) => !e.skipped && !e.complete);
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

  @override
  Widget build(BuildContext context) {
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
        // «Ελεύθερη άσκηση» χωρίς ασκήσεις ακόμα: μόνο «Πρόσθεσε άσκηση».
        if (s.items.isEmpty) return _emptyFree(context, s);
        if (_idx >= s.items.length || _idx < 0) t.setFocusQuiet(s.items.length - 1);
        final e = s.items[_idx];
        return Scaffold(
          appBar: AppBar(
            // Ο τίτλος μεγαλώνει ως 1,3×, για να μη γίνεται «Προπ…» δίπλα στο «Τέλος» (έλεγχος premium, S4).
            title: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ValueListenableBuilder<int>(
                valueListenable: _tick,
                builder: (_, __, ___) => Text(_clock(t.now.difference(s.start)),
                    style: TextStyle(fontSize: 13, color: c.textSecondary, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ])),
            // Σχέδια 9/11 (6β): «Τέλος» ως απαλό κουμπί και ⋮ για τα σπάνια («Αλλαγή άσκησης»).
            actions: [
              OutlinedButton(
                key: const ValueKey('sess-finish'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.exercise,
                  backgroundColor: c.card,
                  minimumSize: const Size(64, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  side: BorderSide(color: c.hairline),
                ),
                onPressed: () => _finish(context),
                child: const Text('Τέλος', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              PopupMenuButton<String>(
                key: const ValueKey('sess-more'),
                tooltip: 'Περισσότερα',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (v) {
                  if (v == 'swap') _swap(context, e);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'swap', key: ValueKey('sess-swap'), child: Text('Αλλαγή άσκησης')),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(builder: (context, k) {
              final wide = k.maxWidth >= 720;
              final ex = _exerciseCard(context, s, e);
              final card = ex;
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
          if (limit == null) return last != null ? Padding(padding: pad, child: const HrStale()) : const SizedBox.shrink();
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

  Widget _list(BuildContext context, Session s, {required bool vertical}) {
    final c = Aigaio.of(context);
    Widget item(int i) {
      final e = s.items[i];
      final on = i == _idx;
      final done = e.done.length;
      final status = e.skipped ? '—' : '$done/${e.sets}';
      final finished = e.complete || e.skipped;
      return Padding(
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
                Text(status, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: e.complete ? c.good : c.textSecondary)),
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
    final hist = t.historyOf(e.ex);
    String? lastTime;
    if (hist.isNotEmpty) {
      final (d, l) = hist.first;
      lastTime = 'Τελευταία φορά (${shortDayDate(d)}): '
          '${hasLoad(k) ? '${loadLabel(k, l.workLoad)} · ' : ''}${l.done.map((x) => x.reps).join(', ')}'
          '${l.rirAnswer == null ? '' : ' · άφησες ${l.rirAnswer == 4 ? '4+' : l.rirAnswer}'}';
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Σχέδια 9/11 (6β): «3 σετ × 12–15 · άφησε 2 · ξεκούραση 1:30». (Το αγγλικό δεν μπαίνει: η βιβλιοθήκη έχει
        // μόνο λέξεις αναζήτησης, όχι σύντομο όνομα.)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '${e.sets} σετ × ${e.lo == e.hi ? '${e.lo}' : '${e.lo}–${e.hi}'} · '),
            TextSpan(text: 'άφησε ${e.rir}', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' · ξεκούραση ${clock(e.rest)}'),
          ]),
          key: const ValueKey('sess-plan'),
          style: TextStyle(fontSize: 15, height: 1.4, color: c.text),
        ),
        if (hasLoad(k) || change != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.tint(c.exercise), borderRadius: BorderRadius.circular(14)),
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
          if (!veryLargeText(context))
          Row(children: [
            SizedBox(width: 30, child: Text('Σετ', style: TextStyle(fontSize: 13, color: c.textSecondary, fontWeight: FontWeight.w600))),
            if (hasLoad(k)) Expanded(child: Text(usesKg(k) ? 'Κιλά' : (isBand(k) ? 'Λάστιχο' : 'Βάρος'), style: TextStyle(fontSize: 13, color: c.textSecondary, fontWeight: FontWeight.w600))),
            Expanded(child: Text('Επαναλήψεις', style: TextStyle(fontSize: 13, color: c.textSecondary, fontWeight: FontWeight.w600))),
            const SizedBox(width: 52),
          ]),
          const SizedBox(height: 6),
          for (var i = 0; i < e.log.length; i++) _setRow(context, s, e, i, i == current),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: () => t.addSet(e), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Σετ')),
          ),
          if (e.complete && e.rirAnswer != null)
            Text(
              'Άφησες ${e.rirAnswer == 4 ? '4+' : e.rirAnswer}${e.pain.isEmpty ? '' : ' · ενόχληση: ${e.pain.map((p) => painNames[p]).join(', ')}'}',
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
      // Τρέχον σετ (σχέδια 9/11, 6β): μόνο οι μετρητές (όχι η τιμή δύο φορές), κουμπιά 48 dp, «Έγινε» από κάτω.
      final steppers = <Widget>[
        if (hasLoad(k))
          Stepper2(
            value: band ? '${(set.load ?? 0).round()}' : loadText,
            leading: band ? BandDots(set.load, size: 14) : null,
            // Σχέδια 9/11 (6β) και έλεγχος premium (S4): οι δύο μετρητές σε μία σειρά και στο κλειστό Fold.
            width: usesKg(k) || band ? 52 : 80,
            button: 44,
            haptic: true,
            labelMinus: 'Λιγότερο βάρος',
            labelPlus: 'Περισσότερο βάρος',
            onMinus: shiftLoad(k, set.load, -1) == null ? null : () => t.setLoad(e, i, shiftLoad(k, set.load, -1)!),
            onPlus: shiftLoad(k, set.load, 1) == null ? null : () => t.setLoad(e, i, shiftLoad(k, set.load, 1)!),
          ),
        Stepper2(
          value: '${set.reps}',
          width: 36,
          button: 44,
          haptic: true,
          labelMinus: 'Λιγότερες',
          labelPlus: 'Περισσότερες',
          onMinus: set.reps > 0 ? () => t.setReps(e, i, set.reps - 1) : null,
          onPlus: () => t.setReps(e, i, set.reps + 1),
        ),
      ];
      return Container(
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
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.spaceBetween, children: steppers),
          const SizedBox(height: 10),
          // «✓ Έγινε» πάντα δεξιά, το όνομα του λάστιχου αριστερά (με πολύ μεγάλα γράμματα το ένα κάτω από το άλλο).
          () {
            final label = band
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    BandDots(set.load, size: 14),
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
        SizedBox(width: 30, child: Text('${i + 1}', style: numStyle)),
        if (hasLoad(k)) Expanded(child: loadCell(numStyle)),
        Expanded(child: Text('${set.reps}', style: numStyle)),
        SizedBox(width: 52, child: Align(alignment: Alignment.centerRight, child: tick())),
      ]),
    );
  }

  Future<void> _done(BuildContext context, Session s, ExLog e, int i) async {
    t.tick(e, i);
    HapticFeedback.lightImpact();
    final first = i == 0 && t.isFirstTime(e.ex) && hasLoad(e.kind) && e.done.length == 1 && e.sets > 1;
    bool gone() => !context.mounted || t.current?.id != s.id;
    if (first) {
      final rir = await _askRir(context, first: true);
      if (gone()) return;
      if (rir != null && rir >= 0) {
        final v = t.calibrateAfterFirst(e, rir);
        if (v != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Τα επόμενα σετ: ${loadLabel(e.kind, v)}.')));
        }
      }
    }
    if (gone()) return;
    if (e.complete) {
      if (e.rirAnswer == null) {
        final rir = await _askRir(context, first: false, e: e);
        if (gone()) return;
        if (rir != null && rir >= 0) t.answer(e, rir);
      }
      if (gone()) return;
      final next = s.items.indexWhere((x) => !x.skipped && !x.complete);
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
  Future<int?> _askRir(BuildContext context, {required bool first, ExLog? e}) {
    var pick = -1;
    return showModalBottomSheet<int>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
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
              Wrap(spacing: 8, runSpacing: 8, children: [
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
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            child: Text(p.value,
                                style: TextStyle(fontSize: 15, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? c.warn : c.text)),
                          ),
                        ),
                      ),
                    );
                  }(),
              ]),
              if (e.pain.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Σημειώνεται στη σύνοψη της προπόνησης.', style: TextStyle(fontSize: 13.5, color: c.warn)),
              ],
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('rir-ok'),
              style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(52)),
              onPressed: pick < 0 ? null : () => Navigator.of(ctx).pop(pick),
              child: const Text('Συνέχεια'),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const ValueKey('rir-unknown'),
              style: TextButton.styleFrom(foregroundColor: c.textSecondary, minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.of(ctx).pop(-1),
              child: const Text('Δεν ξέρω'),
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
        return Semantics(
          liveRegion: true,
          label: 'Διάλειμμα, μένουν $secs δευτερόλεπτα',
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ΔΙΑΛΕΙΜΜΑ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: Color(0xFFB8C0CC))),
                  Text('${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
                ]),
              ),
              b('+30″', () => _restAdd(30), const ValueKey('rest-plus')),
              b('Συνέχεια', _restStop, const ValueKey('rest-stop')),
            ]),
          ),
        );
      },
    );
  }

  Widget _actions(BuildContext context, Session s, ExLog e) {
    final c = Aigaio.of(context);
    final last = _idx >= s.items.length - 1;
    // Μικρό εσωτερικό περιθώριο: στο στενό κινητό οι λέξεις χωράνε σε μία γραμμή.
    const pad = EdgeInsets.symmetric(horizontal: 6);
    // Σχέδια 9/11 (6β): δύο κουμπιά· η «Αλλαγή άσκησης» πήγε στο ⋮.
    return Row(children: [
      Expanded(
        flex: 5,
        child: OutlinedButton(
          key: const ValueKey('sess-skip'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), padding: pad, foregroundColor: c.text),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(s.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        actions: [
          TextButton(key: const ValueKey('sess-finish'), onPressed: () => _finish(context), child: const Text('Τέλος')),
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
              for (final id in ids)
                ListTile(
                  key: ValueKey('swap-$id'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(exName(id)),
                  subtitle: Text(lib.byId(id)?.equip ?? ''),
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
    final total = s.items.where((e) => !e.skipped).fold<int>(0, (a, e) => a + e.sets);
    if (s.setsDone < total) {
      final end = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Τελείωσες νωρίτερα;'),
          content: Text('Έγιναν ${s.setsDone} από $total σετ. Όσα δεν έγιναν δεν μετράνε στην πρόοδο.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Συνέχεια προπόνησης')),
            TextButton(key: const ValueKey('sess-finish-ok'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Τέλος')),
          ],
        ),
      );
      if (end != true || !context.mounted) return;
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
        ? '${shortDayDate(s.start)}, ${s.cardioMinutes ?? s.duration.inMinutes}′${kmValue(s) == null ? '' : ', ${kmValue(s)} km'}'
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
      content: Text('Διαγράφηκε: ${gone.isCardio ? 'περπάτημα' : gone.name} ${shortDayDate(gone.start)}'),
      action: SnackBarAction(label: 'Αναίρεση', onPressed: () => t.undoDelete(gone)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.training;
    final s = widget.session;
    final c = Aigaio.of(context);
    // Με το ρολόι της αποθήκης (όχι της συσκευής), για να ταιριάζει με την αρχή της προπόνησης.
    // Ξεχασμένη προπόνηση: η διάρκεια ως το τελευταίο ✓, όπως θα γραφτεί με την «Αποθήκευση» (όχι 20 ώρες).
    final mins = (s.end ?? (t.current == s && t.isStale(s) ? s.lastActivity : t.now)).difference(s.start).inMinutes;
    final prog = t.program?.workout(s.workout);

    PlanItem itemFor(ExLog e) {
      PlanItem? base;
      for (final i in prog?.items ?? const <PlanItem>[]) {
        if (i.ex == e.ex) base = i;
      }
      return PlanItem(ex: e.ex, sets: e.sets, lo: e.lo, hi: e.hi, rir: e.rir, rest: e.rest, next: base?.next, load: base?.load);
    }

    final stats0 = AppCard(
      child: Row(children: [
        for (final (v, l) in s.isCardio
            ? [
                ('${s.cardioMinutes ?? mins}′', 'διάρκεια'),
                (kmValue(s) ?? '—', distanceFromSteps(s) ? 'km (από βήματα)' : 'km'),
                (s.steps == null ? '—' : thousands(s.steps!), 'βήματα'),
              ]
            : [('$mins′', 'διάρκεια'), ('${s.setsDone}', 'σετ'), (s.volume > 0 ? thousands(s.volume.round()) : '—', 'kg όγκος')])
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c.text)),
              Text(l, style: TextStyle(fontSize: 13, color: c.textSecondary)),
            ]),
          ),
      ]),
    );

    final next = <Widget>[];
    for (final e in s.items) {
      if (e.skipped || e.done.isEmpty) continue;
      final history = widget.live ? [(s.start, e), ...t.historyOf(e.ex)] : t.historyOf(e.ex);
      final item = itemFor(e);
      final tg = nextTarget(item, history, t.now, caution: TrainingStore.isCaution(e.ex));
      final (col, arrow) = changeLook(context, tg.change);
      next.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 2, children: [
            Text(exName(e.ex), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
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
    final perEx = sessionSetHr(s);
    final withHr = perEx.isNotEmpty;
    final exCards = <Widget>[
      for (var k = 0; k < s.items.length; k++)
        _ExerciseCard(e: s.items[k], hr: withHr ? perEx[k] : null, showHr: withHr, key: ValueKey('sum-ex-$k')),
    ];
    final hrCard = s.hrMax == null && !s.hasHr ? null : HrCard(session: s);

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
              onTap: widget.live ? () => setState(() => _feel = i + 1) : () {},
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
      if (widget.live || s.feel != null) feel,
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
            ? (s.items.every((e) => e.skipped || e.complete) ? 'Μπράβο, τελείωσες' : 'Η προπόνηση σταμάτησε')
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
    String setText(SetLog x) => hasLoad(e.kind) ? '${loadLabel(e.kind, x.load)} × ${x.reps}' : '${x.reps} επαν.';
    Widget row(List<Widget> cells, {bool line = true}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: line ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
          child: Row(children: [
            SizedBox(width: 40, child: cells[0]),
            Expanded(child: cells[1]),
            if (showHr) ...[SizedBox(width: 74, child: cells[2]), const SizedBox(width: 8), SizedBox(width: 88, child: cells[3])],
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
            Text(hasLoad(e.kind) ? 'κιλά × επαναλήψεις' : 'επαναλήψεις', style: head),
            _HeartLabel('στο σετ', style: head, color: c.textSecondary),
            _HeartLabel('διάλειμμα', style: head, color: c.textSecondary),
          ]),
          for (var j = 0; j < done.length; j++)
            () {
              final i = done[j];
              final h = hr != null && i < hr!.sets.length ? hr!.sets[i] : null;
              return row([
                Text('${j + 1}', style: strong),
                Text(setText(e.log[i]), style: cell),
                Text(h?.set == null ? '—' : '~${h!.set}', key: ValueKey('sum-set-${e.ex}-$i'), style: h?.set == null ? cell.copyWith(color: c.textSecondary) : strong),
                Text(h?.rest == null ? '—' : '↓ ${h!.rest}', style: h?.rest == null ? cell.copyWith(color: c.textSecondary) : cell.copyWith(color: c.good)),
              ], line: j < done.length - 1);
            }(),
        ],
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
