import 'package:flutter/material.dart';

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

class Stepper2 extends StatelessWidget {
  const Stepper2(
      {super.key, required this.value, required this.onMinus, required this.onPlus, this.width = 64, this.button = 40, this.labelMinus = 'Λιγότερο', this.labelPlus = 'Περισσότερο'});
  final String value;
  final VoidCallback? onMinus, onPlus;
  final double width;

  /// Μέγεθος κουμπιών −/+ (48 στην προπόνηση: ιδρωμένα χέρια, έλεγχος 8/11 UX-02).
  final double button;
  final String labelMinus, labelPlus;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    Widget b(IconData i, VoidCallback? f, String label) => Semantics(
          button: true,
          label: label,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: f,
            child: Container(
              width: button,
              height: button,
              decoration: BoxDecoration(border: Border.all(color: c.hairline), borderRadius: BorderRadius.circular(10), color: c.card),
              child: Icon(i, size: 20, color: f == null ? c.textTertiary : c.text),
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      b(Icons.remove_rounded, onMinus, labelMinus),
      SizedBox(
        width: width,
        child: Text(value, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
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
