import 'package:flutter/material.dart';

import '../../exercise/ex_data.dart';
import '../../food/food_search.dart' show plain;
import '../../format.dart';
import '../../theme.dart';
import '../../training/equipment.dart';
import '../../training/program.dart';
import '../../training/training_store.dart';
import '../../widgets.dart';
import 'session_page.dart' show shiftLoad;
import 'training_common.dart';

/// Βασικές (πολυαρθρικές) ασκήσεις: μεγαλύτερο διάλειμμα.
const _compound = {'db_press', 'incline_press', 'dips', 'rdl', 'goblet', 'split_squat', 'db_row', 'hip_thrust', 'assisted_pullup', 'shoulder_press', 'pushup_handles', 'pushup_bench'};

PlanItem defaultItem(String ex) {
  final g = ExLibrary.loaded?.byId(ex)?.group;
  final small = g == 'arms' || g == 'abs' || g == 'shoulders' || ex == 'face_pull' || ex == 'band_er';
  return PlanItem(
    ex: ex,
    sets: 3,
    lo: small ? 10 : 8,
    hi: small ? 15 : 12,
    rir: 2,
    rest: _compound.contains(ex) ? 120 : (small ? 75 : 90),
  );
}

/// Πρόγραμμα: όνομα, μέρες, προπονήσεις. Νέο ή αλλαγές σε υπάρχον (αποθηκεύεται ως νέα έκδοση).
class ProgramEditorPage extends StatefulWidget {
  const ProgramEditorPage({super.key, required this.training, this.program});
  final TrainingStore training;
  final Program? program;

  static Route<void> route(TrainingStore t, Program? p) =>
      MaterialPageRoute<void>(settings: const RouteSettings(name: 'Πρόγραμμα'), builder: (_) => ProgramEditorPage(training: t, program: p));

  @override
  State<ProgramEditorPage> createState() => _ProgramEditorPageState();
}

class _ProgramEditorPageState extends State<ProgramEditorPage> {
  late final Program _p = widget.program?.copy() ??
      Program(
        id: 'p${widget.training.now.millisecondsSinceEpoch}',
        name: 'Το πρόγραμμά μου',
        workouts: [Workout(id: 'A', name: 'Προπόνηση Α'), Workout(id: 'B', name: 'Προπόνηση Β')],
        days: {5: 'A', 6: 'B', 7: 'A', 1: 'B'},
      );
  late final _name = TextEditingController(text: _p.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _nextId({required bool cardio}) {
    if (cardio) {
      var n = 1;
      while (_p.workout(n == 1 ? 'walk' : 'walk$n') != null) {
        n++;
      }
      return n == 1 ? 'walk' : 'walk$n';
    }
    for (final l in 'ΑΒΓΔΕΖΗΘ'.split('')) {
      final id = {'Α': 'A', 'Β': 'B', 'Γ': 'C', 'Δ': 'D', 'Ε': 'E', 'Ζ': 'F', 'Η': 'G', 'Θ': 'H'}[l]!;
      if (_p.workout(id) == null) return id;
    }
    return 'W${_p.workouts.length + 1}';
  }

  String _letter(String id) => const {'A': 'Α', 'B': 'Β', 'C': 'Γ', 'D': 'Δ', 'E': 'Ε', 'F': 'Ζ', 'G': 'Η', 'H': 'Θ'}[id] ?? id;

  Future<void> _save() async {
    _p.name = _name.text.trim().isEmpty ? 'Το πρόγραμμά μου' : _name.text.trim();
    final errors = validate(_p, exIds());
    if (errors.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Λείπει κάτι'),
          content: Text(errors.join('\n')),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Εντάξει'))],
        ),
      );
      return;
    }
    widget.training.saveProgram(_p, author: 'user');
    if (mounted) Navigator.of(context).pop();
  }

  // Round 1 (U5-30, αίτημα f9 → f6b): η σελίδα/το φύλλο ανοίγει με push, έξω από το ExerciseTheme της κατηγορίας·
  // χωρίς αυτό διακόπτες και δευτερεύοντα κουμπιά έβγαιναν μπλε δίπλα στα πορτοκαλί.
  @override
  Widget build(BuildContext context) => ExerciseTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final days = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Μέρες', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 4),
        for (var d = 1; d <= 7; d++)
          Row(children: [
            SizedBox(width: 110, child: Text(weekdayLong[d]!, style: TextStyle(fontSize: 15, color: c.text))),
            Expanded(
              child: DropdownButton<String?>(
                key: ValueKey('ed-day-$d'),
                isExpanded: true,
                value: _p.days[d],
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Ξεκούραση')),
                  for (final w in _p.workouts) DropdownMenuItem<String?>(value: w.id, child: Text(w.name)),
                ],
                onChanged: (v) => setState(() => v == null ? _p.days.remove(d) : _p.days[d] = v),
              ),
            ),
          ]),
      ]),
    );
    final workouts = [
      for (final w in _p.workouts)
        AppCard(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkoutEditorPage(workout: w)));
            setState(() {});
          },
          child: Row(children: [
            IconBadge(w.isCardio ? Icons.directions_walk_rounded : Icons.fitness_center_rounded, c.exercise),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(w.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
                // round1, U5-06 / U5-32: διάρκεια σε λέξεις, και όχι «Περπάτημα / Περπάτημα · 30′».
                Text(
                  w.isCardio
                      // R7-U3-15: με πλάνο ανά εβδομάδα, το εύρος του πλάνου (πριν «30 λεπτά» και την 4η εβδομάδα των 45).
                      ? [
                          if (w.cardio!.name != w.name) w.cardio!.name,
                          w.cardio!.plan.isEmpty
                              ? '${w.cardio!.minutes} λεπτά'
                              : '${w.cardio!.plan.first} → ${w.cardio!.plan.last} λεπτά (ανά εβδομάδα)',
                        ].join(' · ')
                      : '${countText(w.items.length, 'άσκηση', 'ασκήσεις')} · περίπου ${w.minutes} λεπτά',
                  style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                ),
                if (!w.isCardio && w.items.isNotEmpty)
                  Text(w.items.map((i) => exName(i.ex)).join(', '),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.textSecondary)),
              ]),
            ),
            // round1, U5-32: ο κάδος δεν σβήνει μια ολόκληρη προπόνηση χωρίς επιστροφή· «Αναίρεση» για 8 δευτερόλεπτα, όπως
            // στη διαγραφή μιας προπόνησης από το ιστορικό.
            IconButton(
              key: ValueKey('ed-delete-${w.id}'),
              tooltip: 'Διαγραφή',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () {
                final at = _p.workouts.indexOf(w);
                final days = <int, String>{for (final e in _p.days.entries) if (e.value == w.id) e.key: e.value};
                setState(() {
                  _p.workouts.remove(w);
                  _p.days.removeWhere((_, v) => v == w.id);
                });
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(
                    duration: const Duration(seconds: 8),
                    // Round8 (R8-U2-1, f1): με «Αναίρεση» το μήνυμα δεν θα έκλεινε ποτέ μόνο του (Flutter ≥ 3.38).
                    persist: false,
                    content: Text('Σβήστηκε: ${w.name}'),
                    action: SnackBarAction(
                      key: const ValueKey('ed-undo'),
                      label: 'Αναίρεση',
                      onPressed: () {
                        if (!mounted || _p.workouts.contains(w)) return;
                        setState(() {
                          _p.workouts.insert(at >= 0 && at <= _p.workouts.length ? at : _p.workouts.length, w);
                          _p.days.addAll(days);
                        });
                      },
                    ),
                  ));
              },
            ),
          ]),
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.program == null ? 'Νέο πρόγραμμα' : 'Αλλαγές'),
        actions: [TextButton(key: const ValueKey('ed-save'), onPressed: _save, child: const Text('Αποθήκευση')), const SizedBox(width: 6)],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
              TextField(
                key: const ValueKey('ed-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Όνομα', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              days,
              const SizedBox(height: 18),
              const SectionHeader('Προπονήσεις'),
              const SizedBox(height: 8),
              for (final w in workouts) ...[w, const SizedBox(height: 10)],
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  key: const ValueKey('ed-add-strength'),
                  onPressed: () => setState(() {
                    final id = _nextId(cardio: false);
                    _p.workouts.add(Workout(id: id, name: 'Προπόνηση ${_letter(id)}'));
                  }),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Προπόνηση με βάρη'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _p.workouts.add(Workout(id: _nextId(cardio: true), name: 'Περπάτημα', cardio: Cardio()))),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Αερόβιο'),
                ),
              ]),
              if (widget.program != null) ...[
                const SizedBox(height: 16),
                Text('Η αποθήκευση φτιάχνει νέα έκδοση. Οι παλιές προπονήσεις και τα κιλά τους δεν χάνονται.',
                    style: TextStyle(fontSize: 13, color: c.textSecondary)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Μία προπόνηση: ασκήσεις με σειρά (σύρσιμο), στόχοι, προσθήκη από τη βιβλιοθήκη.
class WorkoutEditorPage extends StatefulWidget {
  const WorkoutEditorPage({super.key, required this.workout});
  final Workout workout;

  @override
  State<WorkoutEditorPage> createState() => _WorkoutEditorPageState();
}

class _WorkoutEditorPageState extends State<WorkoutEditorPage> {
  Workout get w => widget.workout;
  late final _name = TextEditingController(text: w.name);

  @override
  void dispose() {
    w.name = _name.text.trim().isEmpty ? w.name : _name.text.trim();
    _name.dispose();
    super.dispose();
  }

  String _line(PlanItem i) {
    // Round 2 (R2-D-5): «ξεκούραση 1:30», όπως στην προπόνηση και στην επικόλληση (πριν «1′30″»).
    // R7-U3-14: «άφησε 3», η ίδια λέξη με την προπόνηση και την Άσκηση (πριν «ρεζέρβα 3» μόνο εδώ).
    final parts = [repsRange(i), 'ξεκούραση ${restText(i.rest)}', 'άφησε ${i.rir}'];
    if (hasLoad(i.kind)) parts.add(i.load == null ? 'βάρος: αυτόματα' : loadLabel(i.kind, i.load));
    return parts.join(' · ');
  }

  // Round 1 (U5-30, αίτημα f9 → f6b): η σελίδα/το φύλλο ανοίγει με push, έξω από το ExerciseTheme της κατηγορίας·
  // χωρίς αυτό διακόπτες και δευτερεύοντα κουμπιά έβγαιναν μπλε δίπλα στα πορτοκαλί.
  @override
  Widget build(BuildContext context) => ExerciseTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Όνομα', border: OutlineInputBorder())),
    );
    if (w.isCardio) {
      final cd = w.cardio!;
      return Scaffold(
        appBar: AppBar(title: const Text('Αερόβιο')),
        body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          header,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in Cardio.names.entries) Pill(label: a.value, selected: cd.activity == a.key, onTap: () => setState(() => cd.activity = a.key)),
                ]),
                const SizedBox(height: 14),
                // 13/11: με πλάνο ανά εβδομάδα, τα λεπτά τα δίνει το πλάνο· το «− / +» γυρίζει όταν το βγάλεις.
                if (cd.plan.isNotEmpty) ...[
                  Text('Διάρκεια ανά εβδομάδα: ${cd.plan.join(' · ')} λεπτά',
                      key: const ValueKey('ed-cardio-plan'), style: TextStyle(fontSize: 15, height: 1.4, color: c.text)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('ed-cardio-plan-off'),
                      style: TextButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 4)),
                      onPressed: () => setState(() {
                        cd.minutes = cd.plan.last;
                        cd.plan = [];
                      }),
                      child: const Text('Ίδια λεπτά κάθε εβδομάδα'),
                    ),
                  ),
                ] else
                  Row(children: [
                    Expanded(child: Text('Διάρκεια', style: TextStyle(fontSize: 15, color: c.text))),
                    // Round 2 (R2-D-5): «30 λεπτά» με ολόκληρη λέξη (πριν «30′»)· φαρδύτερη τιμή, όπως το «Αρχικό βάρος».
                    Stepper2(
                      value: cd.minutes == 1 ? '1 λεπτό' : '${cd.minutes} λεπτά',
                      width: 96,
                      onMinus: cardioMinutesMinus(cd.minutes) == null ? null : () => setState(() => cd.minutes = cardioMinutesMinus(cd.minutes)!),
                      onPlus: cardioMinutesPlus(cd.minutes) == null ? null : () => setState(() => cd.minutes = cardioMinutesPlus(cd.minutes)!),
                    ),
                  ]),
              ]),
            ),
          ),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(w.name)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('ed-add-ex'),
        backgroundColor: c.exerciseSolid,
        foregroundColor: c.onSolid,
        onPressed: () async {
          final id = await pickExercise(context);
          if (id != null) setState(() => w.items.add(defaultItem(id)));
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Άσκηση'),
      ),
      body: Column(children: [
        header,
        if (w.items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Πρόσθεσε ασκήσεις από τη βιβλιοθήκη. Η σειρά αλλάζει σέρνοντας από τις γραμμές δεξιά.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: c.textSecondary)),
          ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            itemCount: w.items.length,
            onReorderItem: (a, b) => setState(() => w.items.insert(b, w.items.removeAt(a))),
            itemBuilder: (context, i) {
              final it = w.items[i];
              return Padding(
                key: ObjectKey(it),
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                  onTap: () async {
                    await editItem(context, it);
                    setState(() {});
                  },
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(exName(it.ex), style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text)),
                        Text(_line(it), style: TextStyle(fontSize: 13, color: c.textSecondary)),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Αφαίρεση',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => w.items.removeAt(i)),
                    ),
                    ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded))),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Στόχοι μιας άσκησης: σετ, εύρος, διάλειμμα, ρεζέρβα, αρχικό βάρος.
Future<void> editItem(BuildContext context, PlanItem it) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = Aigaio.of(ctx);
        final k = it.kind;
        Widget row(String label, Widget w) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: c.text))), w]),
            );
        // Τουλάχιστον 2 σε όλες, ως να πει άλλα ο γιατρός (έλεγχος #2).
        const minRir = 2;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(exName(it.ex), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c.text)),
              const SizedBox(height: 8),
              row('Σετ', Stepper2(value: '${it.sets}', onMinus: it.sets > 1 ? () => set(() => it.sets--) : null, onPlus: it.sets < 10 ? () => set(() => it.sets++) : null)),
              row('Επαναλήψεις από', Stepper2(value: '${it.lo}', onMinus: it.lo > 1 ? () => set(() => it.lo--) : null, onPlus: it.lo < it.hi ? () => set(() => it.lo++) : null)),
              row('έως', Stepper2(value: '${it.hi}', onMinus: it.hi > it.lo ? () => set(() => it.hi--) : null, onPlus: it.hi < 50 ? () => set(() => it.hi++) : null)),
              row('Διάλειμμα', Stepper2(value: restText(it.rest), width: 72, onMinus: it.rest >= 15 ? () => set(() => it.rest -= 15) : null, onPlus: it.rest < 600 ? () => set(() => it.rest += 15) : null)),
              row('Άφησε (επαναλήψεις)', Stepper2(value: '${it.rir}', onMinus: it.rir > minRir ? () => set(() => it.rir--) : null, onPlus: it.rir < 4 ? () => set(() => it.rir++) : null)),
              if (hasLoad(k))
                row(
                  'Αρχικό βάρος',
                  Stepper2(
                    value: it.load == null ? 'αυτόματα' : (usesKg(k) ? kgText(it.load!) : loadLabel(k, it.load)),
                    width: 96,
                    onMinus: it.load == null ? null : () => set(() => it.load = shiftLoad(k, it.load, -1)),
                    onPlus: () => set(() => it.load = it.load == null ? available(k).first : (shiftLoad(k, it.load, 1) ?? it.load)),
                  ),
                ),
              if (hasLoad(k))
                Text('«Αυτόματα»: ξεκινά ελαφριά και το βρίσκει από τις απαντήσεις σου. Μετά την πρώτη φορά, το βάρος το ορίζει η πρόοδος.',
                    style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
              if (k == LoadKind.bar) Text('Μπάρα χωρίς βραχίονες ασφαλείας: άφησε τουλάχιστον 2.', style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Εντάξει'),
              ),
            ]),
          ),
        );
      }),
    );

/// Επιλογή άσκησης από τη βιβλιοθήκη, με αναζήτηση.
Future<String?> pickExercise(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        var q = '';
        return StatefulBuilder(builder: (ctx, set) {
          final c = Aigaio.of(ctx);
          final list = [
            for (final e in ExLibrary.loaded?.list ?? const <Ex>[])
              if (q.isEmpty || plain('${e.name} ${e.en} ${e.groupName} ${e.equip}').contains(plain(q))) e,
          ];
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.8,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  key: const ValueKey('pick-search'),
                  autofocus: false,
                  onChanged: (v) => set(() => q = v),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Αναζήτηση άσκησης', border: OutlineInputBorder()),
                ),
              ),
              Expanded(
                child: ListView(children: [
                  for (final g in exGroups.entries)
                    if (list.any((e) => e.group == g.key)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: Text(upperGr(g.value), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.textSecondary)),
                      ),
                      for (final e in list.where((e) => e.group == g.key))
                        ListTile(
                          key: ValueKey('pick-${e.id}'),
                          title: Text(e.name),
                          // R7-A6-9: η προειδοποίηση των ασκήσεων «με προσοχή», όπως στο «Πρόσθεσε άσκηση» (ex_picker.dart).
                          subtitle: e.caution == null
                              ? Text(e.equip)
                              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(e.equip),
                                  Row(children: [
                                    Icon(Icons.warning_amber_rounded, size: 15, color: c.warn),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text('Σταδιακά, χωρίς πόνο',
                                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.warn)),
                                    ),
                                  ]),
                                ]),
                          onTap: () => Navigator.of(ctx).pop(e.id),
                        ),
                    ],
                ]),
              ),
            ]),
          );
        });
      },
    );
