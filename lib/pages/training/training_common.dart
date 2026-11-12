import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../exercise/ex_data.dart';
import '../../theme.dart';
import '../../training/equipment.dart';
import '../../training/progression.dart';
import '../../training/program.dart';

/// Όνομα άσκησης από τη βιβλιοθήκη (ή το id, αν δεν φορτώθηκε ακόμα).
String exName(String id) => ExLibrary.loaded?.byId(id)?.name ?? id;

Map<String, String> exNames() => {for (final e in ExLibrary.loaded?.list ?? const <Ex>[]) e.id: e.name};

Set<String> exIds() => {for (final e in ExLibrary.loaded?.list ?? const <Ex>[]) e.id};

/// «3 × 8–12», ή «3 × 10» όταν lo = hi.
String repsRange(PlanItem i) => '${i.sets} × ${i.lo == i.hi ? '${i.lo}' : '${i.lo}–${i.hi}'}';

/// «2′», «1′30″», «45″».
String restText(int s) {
  if (s < 60) return '$s″';
  final m = s ~/ 60, r = s % 60;
  return r == 0 ? '$m′' : '$m′$r″';
}

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
    Change.more => (a.good, ' +1'),
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
            if (leading != null) ...[leading!, const SizedBox(width: 2)],
            Text(value,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
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
                    SizedBox(width: 26, child: Text('${i + 1}.', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.textSecondary))),
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
