import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../exercise/ex_data.dart';
import '../../format.dart';
import '../../theme.dart';
import '../../training/equipment.dart';
import '../../training/progression.dart';
import '../../training/program.dart';
import '../../training/session.dart';
import '../../training/training_device.dart';
import '../../training/training_store.dart';
import '../../training/wear_link.dart';
import '../../widgets.dart';
import '../exercise_detail.dart';
import 'hr_widgets.dart';
import 'symptom_sheet.dart';
import 'training_common.dart';

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
      t.setFocusQuiet(i < 0 ? s.items.length - 1 : i);
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
          // Π.χ. «Σταμάτησα» στο ρολόι: η προπόνηση σταμάτησε, ρωτάμε τι ένιωσες (έλεγχος #2).
          final pending = t.pendingWatchSymptom != null && t.sessions.isNotEmpty && t.sessions.last.stopped;
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(pending ? 'Η προπόνηση σταμάτησε από το ρολόι.' : 'Δεν υπάρχει προπόνηση σε εξέλιξη.',
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
                  if (pending) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey('sess-stopped-tell'),
                      onPressed: () async {
                        await feelSomething(context, t, where: 'watch');
                        if (context.mounted) Navigator.of(context).maybePop();
                      },
                      child: const Text('Πες τι ένιωσες'),
                    ),
                  ],
                ]),
              ),
            ),
          );
        }
        if (_idx >= s.items.length) t.setFocusQuiet(s.items.length - 1);
        final c = Aigaio.of(context);
        final e = s.items[_idx];
        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ValueListenableBuilder<int>(
                valueListenable: _tick,
                builder: (_, __, ___) => Text(_clock(t.now.difference(s.start)),
                    style: TextStyle(fontSize: 13, color: c.textSecondary, fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ]),
            actions: [
              TextButton.icon(
                key: const ValueKey('feel'),
                style: TextButton.styleFrom(foregroundColor: c.bad),
                onPressed: () async {
                  await feelSomething(context, t, where: 'session');
                  // Το σύμπτωμα σταματά την προπόνηση: πίσω στην αρχή της προπόνησης.
                  if (context.mounted && t.current == null) Navigator.of(context).maybePop();
                },
                icon: const Icon(Icons.monitor_heart_outlined, size: 20),
                label: const Text('Νιώθω κάτι'),
              ),
              TextButton(key: const ValueKey('sess-finish'), onPressed: () => _finish(context), child: const Text('Τέλος')),
              const SizedBox(width: 6),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(builder: (context, k) {
              final wide = k.maxWidth >= 720;
              final ex = _exerciseCard(context, s, e);
              // «Νιώθω κάτι» από το ρολόι: πρώτο απ’ όλα.
              final card = t.pendingWatchSymptom == null
                  ? ex
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Material(
                        color: c.bad.withValues(alpha: .1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.bad)),
                        child: ListTile(
                          key: const ValueKey('sess-watch-sym'),
                          leading: Icon(Icons.monitor_heart_outlined, color: c.bad),
                          title: const Text('Στο ρολόι πάτησες «Νιώθω κάτι»'),
                          subtitle: const Text('Πες τι ένιωσες'),
                          onTap: () async {
                            await feelSomething(context, t, where: 'watch');
                            if (context.mounted && t.current == null) Navigator.of(context).maybePop();
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      ex,
                    ]);
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
                SizedBox(height: 54, child: _list(context, s, vertical: false)),
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

  /// Ζωντανοί παλμοί από το ρολόι. Χωρίς ρολόι: τίποτα. Με ρολόι που δεν στέλνει: πορτοκαλί μήνυμα.
  Widget _hr(EdgeInsets pad) => ListenableBuilder(
        listenable: Listenable.merge([WearLink.main.hr, WearLink.main.ready, _tick]),
        builder: (context, _) {
          final w = WearLink.main;
          final bpm = w.bpmAt(DateTime.now());
          if (bpm != null) return Padding(padding: pad, child: HrBar(bpm: bpm, limit: t.hrLimit));
          if (w.hr.value != null || (w.ready.value && t.hrLimit != null)) return Padding(padding: pad, child: HrStale(limit: t.hrLimit));
          return const SizedBox.shrink();
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

    if (vertical) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text('ΑΣΚΗΣΕΙΣ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.textSecondary)),
        ),
        for (var i = 0; i < s.items.length; i++) item(i),
      ]);
    }
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [for (var i = 0; i < s.items.length; i++) item(i)],
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
          '${l.rirAnswer == null ? '' : ' · ρεζέρβα ${l.rirAnswer == 4 ? '4+' : l.rirAnswer}'}';
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(exName(e.ex), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: c.text))),
          if (ex != null && lib != null)
            TextButton(
              onPressed: () => Navigator.of(context).push(ExerciseDetailPage.route(ex, lib)),
              child: const Text('Πώς γίνεται'),
            ),
        ]),
        Text('${repsRange(PlanItem(ex: e.ex, sets: e.sets, lo: e.lo, hi: e.hi))} · ρεζέρβα ${e.rir} · διάλειμμα ${restText(e.rest)}',
            style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
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
          Row(children: [
            SizedBox(width: 30, child: Text('Σετ', style: TextStyle(fontSize: 13, color: c.textSecondary, fontWeight: FontWeight.w600))),
            if (hasLoad(k)) Expanded(child: Text(usesKg(k) ? 'Κιλά' : 'Λάστιχο', style: TextStyle(fontSize: 13, color: c.textSecondary, fontWeight: FontWeight.w600))),
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
              'Ρεζέρβα ${e.rirAnswer == 4 ? '4+' : e.rirAnswer}${e.pain.isEmpty ? '' : ' · ενόχληση: ${e.pain.map((p) => painNames[p]).join(', ')}'}',
              style: TextStyle(fontSize: 13.5, color: e.pain.isEmpty ? c.textSecondary : c.bad),
            ),
        ],
      ]),
    );
  }

  Widget _setRow(BuildContext context, Session s, ExLog e, int i, bool isCurrent) {
    final c = Aigaio.of(context);
    final k = e.kind;
    final set = e.log[i];
    final numStyle = TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: set.done ? c.textSecondary : c.text, fontFeatures: const [FontFeature.tabularFigures()]);
    final loadText = !hasLoad(k) ? '' : (usesKg(k) ? kgText(set.load ?? 0) : loadLabel(k, set.load));
    Widget tick() => Semantics(
          button: true,
          label: set.done ? 'Αναίρεση σετ ${i + 1}' : 'Έγινε το σετ ${i + 1}',
          child: InkWell(
            key: ValueKey('sess-tick-$i'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => set.done ? t.untick(e, i) : _done(context, s, e, i),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: set.done ? c.good : c.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.good, width: 2),
              ),
              child: Icon(Icons.check_rounded, color: set.done ? Colors.white : c.good),
            ),
          ),
        );
    // Τρέχον σετ: τα −/+ σε δική τους γραμμή, σε πλήρες μέγεθος 48 dp (χωρίς FittedBox που τα μίκραινε στα ~30 dp·
    // έλεγχος 8/11, UX-02). Σε στενή οθόνη πάνε σε δύο γραμμές.
    final Widget row;
    if (isCurrent) {
      row = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(width: 30, child: Text('${i + 1}', style: numStyle)),
          Expanded(
            child: Text(
              hasLoad(k) ? '$loadText${usesKg(k) ? ' kg' : ''} × ${set.reps}' : '× ${set.reps}',
              style: numStyle,
            ),
          ),
          SizedBox(width: 52, child: Align(alignment: Alignment.centerRight, child: tick())),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 8, children: [
          if (hasLoad(k))
            Stepper2(
              value: loadText,
              width: usesKg(k) ? 56 : 92,
              button: 48,
              labelMinus: 'Λιγότερο βάρος',
              labelPlus: 'Περισσότερο βάρος',
              onMinus: shiftLoad(k, set.load, -1) == null ? null : () => t.setLoad(e, i, shiftLoad(k, set.load, -1)!),
              onPlus: shiftLoad(k, set.load, 1) == null ? null : () => t.setLoad(e, i, shiftLoad(k, set.load, 1)!),
            ),
          Stepper2(
            value: '${set.reps}',
            width: 40,
            button: 48,
            labelMinus: 'Λιγότερες',
            labelPlus: 'Περισσότερες',
            onMinus: set.reps > 0 ? () => t.setReps(e, i, set.reps - 1) : null,
            onPlus: () => t.setReps(e, i, set.reps + 1),
          ),
        ]),
      ]);
    } else {
      row = Row(children: [
        SizedBox(width: 30, child: Text('${i + 1}', style: numStyle)),
        if (hasLoad(k)) Expanded(child: Text(loadText, style: numStyle)),
        Expanded(child: Text('${set.reps}', style: numStyle)),
        SizedBox(width: 52, child: Align(alignment: Alignment.centerRight, child: tick())),
      ]);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: isCurrent ? const EdgeInsets.symmetric(horizontal: 6, vertical: 6) : const EdgeInsets.symmetric(horizontal: 6),
      decoration: isCurrent ? BoxDecoration(color: c.tint(c.exercise), borderRadius: BorderRadius.circular(14)) : null,
      child: row,
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
        if (rir == -2) {
          // Ενόχληση στον αριστερό ώμο μαζί με σημάδι από την καρδιά: «Νιώθω κάτι» (έλεγχος #2, U2-07).
          await feelSomething(context, t, where: 'session');
          if (context.mounted && t.current == null) Navigator.of(context).maybePop();
          return;
        }
        if (rir != null && rir >= 0) t.answer(e, rir);
      }
      if (gone()) return;
      final next = s.items.indexWhere((x) => !x.skipped && !x.complete);
      if (next >= 0) {
        setState(() => _idx = next);
        _rest(e, exName(s.items[next].ex));
      }
    } else {
      _rest(e, '${exName(e.ex)} · σετ ${e.done.length + 1}');
    }
  }

  /// «Πόσες ακόμα θα έβγαζες;» (0–4+). Στο τέλος της άσκησης και ενοχλήσεις.
  /// Δεν κλείνει κατά λάθος (έλεγχος 8/11): ή απάντηση ή «Δεν ξέρω» (−1, και τότε δεν ανεβαίνει τίποτα).
  /// −2: «Νιώθω κάτι» από την ερώτηση για τον αριστερό ώμο.
  Future<int?> _askRir(BuildContext context, {required bool first, ExLog? e}) {
    var pick = -1;
    return showModalBottomSheet<int>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = Aigaio.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(first ? 'Πρώτο σετ: πόσες ακόμα θα έβγαζες;' : 'Τελευταίο σετ: πόσες ακόμα θα έβγαζες;',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c.text)),
            const SizedBox(height: 4),
            Text(first ? 'Με καλή τεχνική. Από αυτό βρίσκεται το σωστό βάρος για τα επόμενα σετ.' : 'Με καλή τεχνική, χωρίς να «κλέψεις».',
                style: TextStyle(fontSize: 14, color: c.textSecondary)),
            const SizedBox(height: 14),
            Row(children: [
              for (var v = 0; v <= 4; v++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Material(
                      color: pick == v ? c.tint(c.exercise) : c.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: pick == v ? c.exercise : c.hairline, width: pick == v ? 2 : 1),
                      ),
                      child: InkWell(
                        key: ValueKey('rir-$v'),
                        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        onTap: () => set(() => pick = v),
                        child: SizedBox(
                          height: 54,
                          child: Center(child: Text(v == 4 ? '4+' : '$v', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c.text))),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
            if (!first && e != null) ...[
              const SizedBox(height: 14),
              Text('Ενόχληση; (προαιρετικά)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in painNames.entries)
                  FilterChip(
                    key: ValueKey('pain-${p.key}'),
                    label: Text(p.value),
                    selected: e.pain.contains(p.key),
                    onSelected: (_) => set(() => t.togglePain(e, p.key)),
                  ),
              ]),
              // Ο αριστερός ώμος μπορεί να είναι η καρδιά: μία ερώτηση, όχι υπόθεση για μυ (έλεγχος #2, U2-07).
              if (e.pain.contains('shoulderL')) ...[
                const SizedBox(height: 12),
                Container(
                  key: const ValueKey('pain-cardiac'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.bad.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.bad.withValues(alpha: .6)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Νιώθεις μαζί και σφίξιμο ή πίεση στο στήθος, λαχάνιασμα, κρύο ιδρώτα ή ζάλη;',
                        style: TextStyle(fontSize: 14.5, height: 1.35, fontWeight: FontWeight.w600, color: c.text)),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      key: const ValueKey('rir-cardiac'),
                      style: OutlinedButton.styleFrom(foregroundColor: c.bad, side: BorderSide(color: c.bad), minimumSize: const Size.fromHeight(46)),
                      onPressed: () => Navigator.of(ctx).pop(-2),
                      child: const Text('Ναι → Νιώθω κάτι'),
                    ),
                  ]),
                ),
              ],
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('rir-ok'),
              style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(50)),
              onPressed: pick < 0 ? null : () => Navigator.of(ctx).pop(pick),
              child: const Text('Συνέχεια'),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const ValueKey('rir-unknown'),
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
    return Row(children: [
      Expanded(
        flex: 5,
        child: OutlinedButton(
          key: const ValueKey('sess-swap'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), padding: pad),
          onPressed: () => _swap(context, e),
          child: const Text('Αλλαγή', maxLines: 1, softWrap: false),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 5,
        child: OutlinedButton(
          key: const ValueKey('sess-skip'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), padding: pad),
          onPressed: e.done.isNotEmpty ? null : () => t.skip(e, !e.skipped),
          child: Text(e.skipped ? 'Αναίρεση' : 'Παράλειψη', maxLines: 1, softWrap: false),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 8,
        child: FilledButton(
          key: const ValueKey('sess-next'),
          style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(50), padding: pad),
          onPressed: last ? () => _finish(context) : () => setState(() => _idx++),
          child: Text(last ? 'Τέλος προπόνησης' : 'Επόμενη άσκηση', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
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
  }

  static const _feels = ['Πολύ εύκολα', 'Εύκολα', 'Καλά', 'Δύσκολα', 'Πολύ δύσκολα'];

  @override
  Widget build(BuildContext context) {
    final t = widget.training;
    final s = widget.session;
    final c = Aigaio.of(context);
    // Με το ρολόι της αποθήκης (όχι της συσκευής), για να ταιριάζει με την αρχή της προπόνησης.
    final mins = (s.end ?? t.now).difference(s.start).inMinutes;
    final prog = t.program?.workout(s.workout);

    PlanItem itemFor(ExLog e) {
      PlanItem? base;
      for (final i in prog?.items ?? const <PlanItem>[]) {
        if (i.ex == e.ex) base = i;
      }
      return PlanItem(ex: e.ex, sets: e.sets, lo: e.lo, hi: e.hi, rir: e.rir, rest: e.rest, next: base?.next, load: base?.load);
    }

    final stats = AppCard(
      child: Row(children: [
        for (final (v, l) in s.isCardio
            ? [
                ('${s.cardioMinutes ?? mins}′', 'διάρκεια'),
                (s.meters == null ? '—' : (s.meters! / 1000).toStringAsFixed(2).replaceAll('.', ','), 'km'),
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

    final done = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Τι έκανες', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
        for (final e in s.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 2, children: [
              Text(exName(e.ex), style: TextStyle(fontSize: 15, color: e.skipped || e.done.isEmpty ? c.textSecondary : c.text)),
              Text(
                e.skipped
                    ? 'παραλείφθηκε'
                    : e.done.isEmpty
                        ? 'δεν έγινε'
                        : '${hasLoad(e.kind) ? '${loadLabel(e.kind, e.workLoad)} · ' : ''}${e.done.map((x) => x.reps).join(', ')}',
                style: TextStyle(fontSize: 14, color: c.textSecondary),
              ),
            ]),
          ),
      ]),
    );

    final hrCard = s.hrMax == null ? null : HrCard(session: s, limit: t.hrLimit);

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

    final left = <Widget>[stats, if (hrCard != null) hrCard, if (!s.isCardio) done];
    final right = <Widget>[if (next.isNotEmpty) nextCard, if (widget.live || s.feel != null) feel];
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
            return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: spaced([...left, ...right]));
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
