import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../exercise/ex_data.dart';
import '../../exercise/ex_names.dart';
import '../../format.dart' show hm, longDate, sameDay, upperGr;
import '../../reference.dart' show MetricInfo;
import '../../theme.dart';
import '../../training/equipment.dart';
import '../../training/progression.dart';
import '../../training/program.dart';
import '../../training/session.dart';
import '../../training/training_store.dart';
import '../../widgets.dart' show AppCard, IconBadge;

/// Όνομα άσκησης από τη βιβλιοθήκη· αν αυτή δεν φορτώθηκε ακόμα, από τον σταθερό πίνακα ονομάτων (round1, S6-2 / S7-01:
/// προπόνηση που ξεκινούσε από τη Σήμερα έδειχνε «db_press» αντί για το όνομα). Το σκέτο id μόνο για άγνωστη άσκηση.
String exName(String id) => ExLibrary.loaded?.byId(id)?.name ?? exNamesById[id] ?? id;

Map<String, String> exNames() => {for (final e in ExLibrary.loaded?.list ?? const <Ex>[]) e.id: e.name};

Set<String> exIds() => {for (final e in ExLibrary.loaded?.list ?? const <Ex>[]) e.id};

/// «3 × 8–12», ή «3 × 10» όταν lo = hi.
String repsRange(PlanItem i) => '${i.sets} × ${i.lo == i.hi ? '${i.lo}' : '${i.lo}–${i.hi}'}';

/// «1:30», «0:45», «2:00»: λεπτά:δευτερόλεπτα, όπως η αντίστροφη μέτρηση του διαλείμματος και η «ξεκούραση 1:30» της
/// προπόνησης (round 2, R2-D-5: πριν «1′30″», «45″» στον επεξεργαστή προγράμματος).
String restText(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// «3 × 9», ή «10, 10, 9» όταν διαφέρουν.
String repsList(List<int> r) {
  if (r.isEmpty) return '';
  if (r.every((x) => x == r.first)) return '${r.length} × ${r.first}';
  return r.join(', ');
}

/// Στόχος σε μία γραμμή: «11,8 kg · 3 × 9».
String targetLine(PlanItem item, Target t) {
  final k = item.kind;
  final reps = repsList(t.reps);
  return hasLoad(k) ? '${loadLabel(k, t.load)} · $reps' : reps;
}

/// Χρώμα και βελάκι της αλλαγής.
(Color, String) changeLook(BuildContext context, Change c) {
  final a = Aigaio.of(context);
  return switch (c) {
    Change.up || Change.variant => (a.good, ' ↑'),
    // round1, U5-26: όχι «10 +1» (διαβαζόταν σαν πράξη)· οι αριθμοί δίπλα έχουν ήδη την επιπλέον επανάληψη.
    Change.more => (a.good, ' · +1\u00A0επανάληψη'),
    Change.down || Change.back => (a.textSecondary, ' ↓'),
    Change.pain => (a.warn, ''),
    _ => (a.textSecondary, ''),
  };
}

/// Χρώματα των λάστιχων (για την κουκκίδα δίπλα στα lb).
const bandColors = <String, Color>{
  'yellow': Color(0xFFEAB308),
  'blue': Color(0xFF2563EB),
  'green': Color(0xFF16A34A),
  'black': Color(0xFF1F2937),
  'red': Color(0xFFDC2626),
};

/// Κουκκίδες στο χρώμα των λάστιχων ενός φορτίου (σχέδια 9/11: «● 30 lb» αντί για «πράσινο (30 lb)»).
class BandDots extends StatelessWidget {
  const BandDots(this.lb, {super.key, this.size = 14});
  final double? lb;
  final double size;

  @override
  Widget build(BuildContext context) {
    final names = (lb ?? 0) <= 0 ? const <String>[] : (bandCombos()[lb!.round()] ?? const <String>[]);
    if (names.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final n in names)
        Container(
          width: size,
          height: size,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: bandColors[n] ?? Colors.grey,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 1)],
          ),
        ),
    ]);
  }
}

/// «Πράσινο λάστιχο · 30 lb», «Πράσινο + κίτρινο λάστιχο · 40 lb».
String bandName(double lb) {
  final names = bandCombos()[lb.round()];
  // Αδιάσπαστο κενό: «30 lb» ποτέ σε δύο γραμμές.
  if (names == null || names.isEmpty) return '${lb.round()}\u00A0lb';
  final t = names.map((n) => bandNames[n]).join(' + ');
  return '${t[0].toUpperCase()}${t.substring(1)} λάστιχο · ${lb.round()}\u00A0lb';
}

class Stepper2 extends StatelessWidget {
  const Stepper2(
      {super.key,
      required this.value,
      required this.onMinus,
      required this.onPlus,
      this.width = 64,
      this.button = 40,
      this.labelMinus = 'Λιγότερο',
      this.labelPlus = 'Περισσότερο',
      this.leading,
      this.haptic = false});
  final String value;

  /// Κάτι πριν από την τιμή (π.χ. η κουκκίδα του λάστιχου).
  final Widget? leading;
  final VoidCallback? onMinus, onPlus;
  final double width;

  /// Μέγεθος κουμπιών −/+ (56 στο τρέχον σετ της προπόνησης: ιδρωμένα χέρια· 13/11, Δ3).
  final double button;
  final String labelMinus, labelPlus;

  /// Μικρή δόνηση αφής σε κάθε πάτημα, για να το νιώθεις χωρίς να κοιτάς (προπόνηση· Συμβούλιο 5, Δ4, έγκριση 13/11).
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    Widget b(IconData i, VoidCallback? f, String label) => Semantics(
          button: true,
          label: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: f == null || !haptic
                ? f
                : () {
                    HapticFeedback.selectionClick();
                    f();
                  },
            child: Container(
              width: button,
              height: button,
              decoration: BoxDecoration(border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(10), color: c.card),
              child: Icon(i, size: button >= 56 ? 26 : 20, color: f == null ? c.textTertiary : c.text),
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      b(Icons.remove_rounded, onMinus, labelMinus),
      SizedBox(
        width: width,
        // Ο αριθμός σε μία γραμμή που μικραίνει αν χρειαστεί, ποτέ «11,7 / 5» σε δύο γραμμές (σχέδια 9/11).
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // Round 2 (R2-U2-10): 4 dp ανάμεσα στην κουκκίδα του λάστιχου και στον αριθμό (πριν 2: «●30» κολλητά).
            if (leading != null) ...[leading!, const SizedBox(width: 4)],
            Text(value,
                maxLines: 1,
                textAlign: TextAlign.center,
                // round1, U5-34: στο τρέχον σετ (κουμπιά 56 dp) ο αριθμός που κοιτάς είναι μεγαλύτερος.
                style: TextStyle(fontSize: button >= 56 ? 24 : 19, fontWeight: FontWeight.w800, color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
      ),
      b(Icons.add_rounded, onPlus, labelPlus),
    ]);
  }
}

/// Μικρό «χάπι» επιλογής (στο πλάτος του).
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.selected, required this.onTap, this.height = 40});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.exerciseSolid : c.card,
        shape: StadiumBorder(side: BorderSide(color: selected ? c.exerciseSolid : c.hairline)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: (height - 20) / 2),
            child: Text(label, style: TextStyle(fontSize: 14.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: selected ? c.onSolid : c.text)),
          ),
        ),
      ),
    );
  }
}

/// Ένα λάστιχο (όχι βοήθεια, όχι ζευγάρι ανά χέρι): δείχνεται με κουκκίδα και lb.
bool isBand(LoadKind k) => k == LoadKind.band;

// ---------------------------------------------------------------------------
// Ζέσταμα και αποθεραπεία (13/11)
// ---------------------------------------------------------------------------

/// Το όνομα του κουμπιού, ανάλογα με το τι έχει η προπόνηση· null αν δεν έχει τίποτα από τα δύο.
String? routineLabel(Workout w) => w.warmup.isEmpty && w.cooldown.isEmpty
    ? null
    : (w.cooldown.isEmpty ? 'Ζέσταμα' : (w.warmup.isEmpty ? 'Αποθεραπεία' : 'Ζέσταμα και αποθεραπεία'));

/// Κουμπί που ανοίγει τα βήματα του ζεστάματος και της αποθεραπείας. Δεν φαίνεται αν η προπόνηση δεν έχει κανένα.
class RoutineButton extends StatelessWidget {
  const RoutineButton(this.workout, {super.key});
  final Workout workout;

  @override
  Widget build(BuildContext context) {
    final label = routineLabel(workout);
    if (label == null) return const SizedBox.shrink();
    final c = Aigaio.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('routine-open'),
        style: TextButton.styleFrom(foregroundColor: c.exercise, minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 4)),
        onPressed: () => openRoutineSheet(context, workout),
        icon: const Icon(Icons.self_improvement_rounded, size: 20),
        label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

Future<void> openRoutineSheet(BuildContext context, Workout w) => showModalBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: 'Ζέσταμα και αποθεραπεία'),
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final c = Aigaio.of(context);
        Widget part(String title, List<String> steps) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text)),
              const SizedBox(height: 6),
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // round1, U6-24: χώρος και για «10.» με μεγάλα γράμματα.
                    SizedBox(width: 32, child: Text('${i + 1}.', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.textSecondary))),
                    Expanded(child: Text(steps[i], style: TextStyle(fontSize: 15, height: 1.4, color: c.text))),
                  ]),
                ),
            ]);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(key: const ValueKey('routine-sheet'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (w.warmup.isNotEmpty) part('Ζέσταμα, πριν', w.warmup),
            if (w.warmup.isNotEmpty && w.cooldown.isNotEmpty) const SizedBox(height: 18),
            if (w.cooldown.isNotEmpty) part('Αποθεραπεία, μετά', w.cooldown),
          ]),
        );
      },
    );

// ---------------------------------------------------------------------------
// Σημειώσεις του προγράμματος (round1, S7-11 / U6-25)
// ---------------------------------------------------------------------------

/// Η σημείωση του προγράμματος (κανόνες ασφάλειας, «άφησε», τι κάνεις με πόνο στο στήθος) και της προπόνησης. Πριν
/// φαινόταν ΜΟΝΟ μία φορά, στην επικόλληση· τώρα είναι πάντα ένα πάτημα μακριά, στην «Προπόνηση» και μέσα στην προπόνηση.
List<(String, String)> programNotes(Program? p, Workout? w) => [
      if (p?.note case final n? when n.trim().isNotEmpty) ('Το πρόγραμμα', n.trim()),
      if (w?.note case final n? when n.trim().isNotEmpty) (w!.name, n.trim()),
    ];

/// Κουμπί «Σημειώσεις του προγράμματος»· δεν φαίνεται αν δεν υπάρχει καμία.
class ProgramNotesButton extends StatelessWidget {
  const ProgramNotesButton(this.program, {super.key, this.workout});
  final Program? program;
  final Workout? workout;

  @override
  Widget build(BuildContext context) {
    final notes = programNotes(program, workout);
    if (notes.isEmpty) return const SizedBox.shrink();
    final c = Aigaio.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('program-notes'),
        style: TextButton.styleFrom(foregroundColor: c.exercise, minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 4)),
        onPressed: () => openProgramNotesSheet(context, notes),
        icon: const Icon(Icons.info_outline_rounded, size: 20),
        label: const Text(programNotesLabel, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

const programNotesLabel = 'Σημειώσεις του προγράμματος';

Future<void> openProgramNotesSheet(BuildContext context, List<(String, String)> notes) => showModalBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: programNotesLabel),
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) {
        final c = Aigaio.of(context);
        return SingleChildScrollView(
          key: const ValueKey('program-notes-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(programNotesLabel, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
            for (final (title, text) in notes) ...[
              const SizedBox(height: 14),
              Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text)),
              const SizedBox(height: 4),
              Text(text, style: TextStyle(fontSize: 15, height: 1.45, color: c.text)),
            ],
          ]),
        );
      },
    );

/// «Άφησε N» (round1, S7-21): η πιο σημαντική οδηγία της προπόνησης, εξηγημένη πριν από το σετ (πριν μόνο μετά το
/// τελευταίο). Η πρόταση για το λάθος της εκτίμησης: Halperin 2022 (οι άνθρωποι υποεκτιμούν περίπου κατά μία επανάληψη
/// πόσες τους μένουν).
const rirInfo = MetricInfo(
  title: 'Άφησε: πόσες επαναλήψεις σου μένουν',
  what: 'Σταματάς το σετ όταν νιώθεις ότι θα έβγαζες ακόμα τόσες επαναλήψεις με καλή τεχνική. «Άφησε 3» = σταματάς '
      'όταν σου μένουν περίπου 3.',
  shows: 'Όσο πιο κοντά στο όριο, τόσο ανεβαίνει η πίεση· γι’ αυτό δεν φτάνουμε ποτέ ως εκεί. Στο τέλος κάθε άσκησης σε '
      'ρωτάω πόσες σου έμεναν: από την απάντηση βγαίνει το βάρος της επόμενης φοράς.',
  accuracy: 'Στην αρχή όλοι το υπολογίζουμε χοντρικά, και συνήθως νομίζουμε ότι μας μένουν λιγότερες απ’ όσες μένουν. '
      'Με την ώρα γίνεται πιο εύκολο.',
  cite: 'Halperin κ.ά. 2022 (Sports Med): ακρίβεια στην εκτίμηση των επαναλήψεων ως την αποτυχία.',
);

/// Σύντομο όνομα προπόνησης για «Η εβδομάδα» (round1, U5-27): από το ελληνικό όνομα, όχι ο εσωτερικός κωδικός
/// («Πάνω μέρος Α» → «ΠΑ», «Κάτω μέρος Β» → «ΚΒ», «Προπόνηση Β» → «Β», «Πόδια» → «ΠΟ»).
String shortWorkoutName(Workout w) {
  final p = w.name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (p.isEmpty) return upperGr(w.id.length <= 2 ? w.id : w.id.substring(0, 2));
  final last = p.last.length == 1 ? upperGr(p.last) : '';
  if (p.length >= 3) return upperGr(p.first.substring(0, 1)) + last;
  if (p.length == 2 && last.isNotEmpty) return last;
  final n = p.first;
  return upperGr(n.length < 2 ? n : n.substring(0, 2));
}

// ---------------------------------------------------------------------------
// «Ξεχασμένη προπόνηση;» (στην «Προπόνηση» και στη «Σήμερα»)
// ---------------------------------------------------------------------------

/// «τη Δευτέρα 16 Νοεμβρίου», «το Σάββατο 21 Νοεμβρίου», «την Πέμπτη 12 Νοεμβρίου» (round1, U6-14).
String onDay(DateTime d) => '${switch (d.weekday) { DateTime.monday => 'τη', DateTime.saturday => 'το', _ => 'την' }} ${longDate(d)}';

/// Ανοιχτή προπόνηση χωρίς κίνηση εδώ και ώρες (έλεγχος 9/11, V-A-09): «Τέλος (στις 19:22)» με το τελευταίο ✓ ως τέλος.
/// round1, S6-14: η ίδια κάρτα και στη «Σήμερα» (πριν εκεί έγραφε «Συνέχισε την προπόνηση… ξεκίνησες 18:02» σαν να ήταν
/// σημερινή). U6-01: χωρίς σετ, το «Σβήσιμο» ρωτά πρώτα· και αν υπάρχουν παλμοί ή το ρολόι δεν βρίσκεται τώρα (τα σετ
/// του μπορεί να μην έχουν έρθει ακόμα), το γεμάτο κουμπί είναι η «Συνέχεια».
class ForgottenWorkout extends StatelessWidget {
  const ForgottenWorkout(
      {super.key,
      required this.training,
      required this.session,
      required this.now,
      required this.watchReady,
      required this.onResume,
      this.keyPrefix = 'train'});
  final TrainingStore training;
  final Session session;
  final DateTime now;
  final bool watchReady;
  final VoidCallback onResume;

  /// Πρόθεμα των κλειδιών («train» στην «Προπόνηση», «today» στη «Σήμερα»).
  final String keyPrefix;

  Future<void> _drop(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Σβήσιμο προπόνησης;'),
        content: const Text('Δεν έχει κανένα σετ εδώ. Αν έκανες σετ στο ρολόι, πάτα «Συνέχεια» και περίμενε να έρθουν.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Άκυρο')),
          TextButton(key: ValueKey('$keyPrefix-forgotten-drop-ok'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Σβήσιμο')),
        ],
      ),
    );
    if (ok == true && identical(training.current, session)) training.discard();
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final s = session;
    final last = s.lastActivity;
    final when = sameDay(s.start, now) ? 'στις ${hm(s.start)}' : '${onDay(s.start)} στις ${hm(s.start)}';
    final none = s.setsDone == 0;
    final waitWatch = none && (s.hr.isNotEmpty || !watchReady);
    final filled = FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size(0, 48));
    final plain = TextButton.styleFrom(minimumSize: const Size(0, 48));
    final resume = waitWatch
        ? FilledButton(key: ValueKey('$keyPrefix-forgotten-resume'), style: filled, onPressed: onResume, child: const Text('Συνέχεια'))
        : TextButton(key: ValueKey('$keyPrefix-forgotten-resume'), style: plain, onPressed: onResume, child: const Text('Συνέχεια'));
    final Widget main;
    if (!none) {
      main = FilledButton(
        key: ValueKey('$keyPrefix-forgotten-end'),
        style: filled,
        onPressed: () => training.finish(end: last),
        child: Text('Τέλος (στις ${hm(last)})'),
      );
    } else if (waitWatch) {
      main = TextButton(key: ValueKey('$keyPrefix-forgotten-drop'), style: plain, onPressed: () => _drop(context), child: const Text('Σβήσιμο'));
    } else {
      main = FilledButton(key: ValueKey('$keyPrefix-forgotten-drop'), style: filled, onPressed: () => _drop(context), child: const Text('Σβήσιμο'));
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconBadge(Icons.history_toggle_off_rounded, c.exercise),
          const SizedBox(width: 12),
          Expanded(child: Text('Ξεχασμένη προπόνηση;', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text))),
        ]),
        const SizedBox(height: 8),
        Text(
          none
              ? 'Η «${s.name}» που ξεκίνησε $when είναι ακόμα ανοιχτή, χωρίς κανένα σετ.'
              : 'Η «${s.name}» που ξεκίνησε $when είναι ακόμα ανοιχτή. Τελευταίο σετ στις ${hm(last)}.',
          style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: waitWatch ? [resume, main] : [main, resume]),
      ]),
    );
  }
}
