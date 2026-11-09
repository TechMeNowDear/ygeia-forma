import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../training/session.dart';
import '../../training/wear_link.dart';

/// Ζωντανοί παλμοί από το ρολόι, με γραμμή ως το όριο του γιατρού (σχέδιο 3, 8/11).
class HrBar extends StatelessWidget {
  const HrBar({super.key, required this.bpm, this.limit});
  final int bpm;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final over = limit != null && bpm >= limit!;
    return Semantics(
      liveRegion: true,
      label: 'Παλμοί $bpm${limit == null ? '' : ', όριο $limit'}${over ? ', πάνω από το όριο' : ''}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: over ? c.bad.withValues(alpha: .12) : c.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: over ? c.bad : c.hairline, width: over ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Icon(Icons.favorite_rounded, color: c.bad, size: 22),
            const SizedBox(width: 8),
            Text('$bpm', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: over ? c.bad : c.text, height: 1)),
            const SizedBox(width: 4),
            Text('bpm', style: TextStyle(fontSize: 13, color: c.textSecondary)),
            const Spacer(),
            if (over)
              Flexible(
                child: Text('Ξεκουράσου μέχρι να πέσουν', textAlign: TextAlign.end, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c.bad)),
              )
            else if (limit != null)
              Text('όριο $limit', style: TextStyle(fontSize: 13, color: c.textSecondary)),
          ]),
          if (limit != null) ...[
            const SizedBox(height: 8),
            SizedBox(height: 10, child: CustomPaint(painter: _BarPainter(bpm, limit!, c))),
          ],
        ]),
      ),
    );
  }
}

/// Οι παλμοί σταμάτησαν να έρχονται από το ρολόι: να φαίνεται, όχι να εξαφανίζεται η γραμμή (έλεγχος 8/11).
class HrStale extends StatelessWidget {
  const HrStale({super.key, this.limit});
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('hr-stale'),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: c.exercise.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.exercise),
        ),
        child: Row(children: [
          Icon(Icons.heart_broken_outlined, color: c.exercise, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Οι παλμοί δεν έρχονται από το ρολόι', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.text)),
              Text(
                limit == null ? 'Σφίξε λίγο το λουρί, πάνω από το κόκαλο του καρπού.' : 'Σφίξε λίγο το λουρί. Μέχρι να ξανάρθουν, πήγαινε με την κούραση.',
                style: TextStyle(fontSize: 13, height: 1.3, color: c.textSecondary),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.bpm, this.limit, this.c);
  final int bpm, limit;
  final Aigaio c;

  @override
  void paint(Canvas canvas, Size size) {
    const lo = 60.0;
    final hi = limit + 20.0;
    double x(num v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0) * size.width;
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(0, 2, size.width, 6), const Radius.circular(3));
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFF60A5FA), Color(0xFF34D399), Color(0xFFFBBF24), Color(0xFFF97316), Color(0xFFEF4444)])
            .createShader(r.outerRect),
    );
    // Το όριο του γιατρού: λευκή γραμμή με περίγραμμα.
    final lx = x(limit);
    canvas.drawRect(Rect.fromLTWH(lx - 1.5, 0, 3, size.height), Paint()..color = c.text);
    // Οι παλμοί τώρα.
    final bx = x(bpm);
    canvas.drawCircle(Offset(bx, 5), 5.5, Paint()..color = c.card);
    canvas.drawCircle(Offset(bx, 5), 4, Paint()..color = c.text);
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.bpm != bpm || old.limit != limit || old.c != c;
}

/// Παλμοί μιας προπόνησης στη σύνοψη: μέσος, υψηλότερος, γράφημα με το όριο (σχέδιο 5, 8/11).
class HrCard extends StatelessWidget {
  const HrCard({super.key, required this.session, this.limit});
  final Session session;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final h = HrSummary(session, limit);
    final mins = (h.overSec / 60).ceil();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Παλμοί', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text))),
          Text('από το ρολόι', style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
          IconButton(
            key: const ValueKey('hr-info'),
            tooltip: 'Πώς διαβάζονται οι παλμοί',
            onPressed: () => showHrInfo(context, cardio: session.isCardio),
            icon: Icon(Icons.info_outline_rounded, color: c.textSecondary),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 18, runSpacing: 4, children: [
          if (h.avg != null) _stat(c, '${h.avg}', 'μέσος'),
          if (h.max != null) _stat(c, '${h.max}', 'υψηλότερος'),
        ]),
        if (session.hr.length >= 2) ...[
          const SizedBox(height: 10),
          SizedBox(height: 70, child: CustomPaint(painter: _HrChart(session.hr, limit, c))),
        ],
        if (limit != null) ...[
          const SizedBox(height: 8),
          Text(
            h.overSec > 0
                ? 'Πάνω από το όριο ($limit) για περίπου $mins′.'
                : (h.max != null && h.max! >= limit!)
                    ? 'Έφτασες στιγμιαία το όριο ($limit).'
                    // Ο καρπός μετρά λιγότερο όσο δυναμώνει η προσπάθεια (Boudreaux 2018· έλεγχος #2).
                    // Στο περπάτημα ο καρπός μετρά καλά (σταθερή κίνηση)· η επιφύλαξη ισχύει μόνο για τα βάρη.
                    : session.isCardio
                        ? 'Το ρολόι δεν έδειξε παλμούς πάνω από το όριο ($limit).'
                        : 'Το ρολόι δεν έδειξε παλμούς πάνω από το όριο ($limit). Στα βάρη ο καρπός συχνά μετρά πιο χαμηλά· '
                            'πρώτα μετράει πώς νιώθεις.',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: h.overSec > 0 ? c.bad : c.text),
          ),
        ],
        if (session.hrGap case final g?) ...[
          const SizedBox(height: 6),
          // Πόσο γρήγορα έφταναν οι παλμοί από το ρολόι (8/11): μέτρο για το πόσο μπορεί να αργήσει η ειδοποίηση.
          Text(
            g <= 12
                ? 'Οι παλμοί έφταναν κάθε λίγα δευτερόλεπτα (μεγαλύτερο κενό $g″)${session.hrMode == 'sensor' ? ', απευθείας από τον αισθητήρα' : ''}.'
                : 'Μεγαλύτερο κενό στους παλμούς: ${g < 120 ? '$g″' : '${(g / 60).round()}′'}. Τόσο μπορεί να άργησε η ειδοποίηση.',
            key: const ValueKey('hr-gap'),
            style: TextStyle(fontSize: 12.5, height: 1.35, color: g <= 12 ? c.textSecondary : c.exercise),
          ),
        ],
      ]),
    );
  }

  Widget _stat(Aigaio c, String v, String l) => Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(v, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.text, height: 1)),
        const SizedBox(width: 4),
        Text(l, style: TextStyle(fontSize: 13, color: c.textSecondary)),
      ]);
}

class _HrChart extends CustomPainter {
  _HrChart(this.hr, this.limit, this.c);
  final List<List<int>> hr;
  final int? limit;
  final Aigaio c;

  @override
  void paint(Canvas canvas, Size size) {
    var lo = hr.map((p) => p[1]).reduce(math.min).toDouble();
    var hi = hr.map((p) => p[1]).reduce(math.max).toDouble();
    if (limit != null) {
      hi = math.max(hi, limit! + 5.0);
      lo = math.min(lo, limit! - 40.0);
    }
    if (hi - lo < 20) hi = lo + 20;
    final t0 = hr.first[0].toDouble(), t1 = math.max(hr.last[0].toDouble(), t0 + 1);
    Offset at(List<int> p) => Offset((p[0] - t0) / (t1 - t0) * size.width, size.height - (p[1] - lo) / (hi - lo) * size.height);
    if (limit != null) {
      final y = size.height - (limit! - lo) / (hi - lo) * size.height;
      final dash = Paint()
        ..color = c.bad
        ..strokeWidth = 1.2;
      for (double x = 0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), dash);
      }
    }
    final path = Path()..moveTo(at(hr.first).dx, at(hr.first).dy);
    for (final p in hr.skip(1)) {
      final o = at(p);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = c.exercise,
    );
  }

  @override
  bool shouldRepaint(_HrChart old) => old.hr != hr || old.limit != limit || old.c != c;
}

/// «Πώς διαβάζονται οι παλμοί»: ορισμοί και όρια, χωρίς να γεμίζει η οθόνη της σύνοψης (9/11).
Future<void> showHrInfo(BuildContext context, {bool cardio = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final c = Aigaio.of(ctx);
      Widget h(String t) => Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(t, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text)),
          );
      Widget p(String t) => Text(t, style: TextStyle(fontSize: 14.5, height: 1.45, color: c.text));
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .85),
          child: SingleChildScrollView(
            key: const ValueKey('hr-info-sheet'),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Πώς διαβάζονται οι παλμοί', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
              h('Από πού έρχονται'),
              p('Από τον αισθητήρα του ρολογιού, μία μέτρηση το δευτερόλεπτο, όσο τρέχει η προπόνηση ή το περπάτημα στο ρολόι. '
                  'Αν το ρολόι δεν ήταν σε προπόνηση (π.χ. δεν πάτησες «Παλμοί εδώ»), δεν υπάρχουν παλμοί για εκείνη την ώρα.'),
              if (!cardio) ...[
                h('Παλμοί στο σετ'),
                p('Ο μέσος όρος των παλμών στα τελευταία 30 δευτερόλεπτα ως τη στιγμή που πάτησες ✓. '
                    'Ίδιο παράθυρο για κάθε σετ, ώστε τα σετ να συγκρίνονται μεταξύ τους.'),
                h('Παλμοί στο διάλειμμα'),
                p('Ως πόσο χαμηλά έπεσαν οι παλμοί πριν ξεκινήσεις το επόμενο σετ (ο χαμηλότερος μέσος όρος 10 δευτερολέπτων). '
                    'Όσο πιο κάτω πέφτουν, τόσο καλύτερα ξεκουράζεσαι. Στο τελευταίο σετ δεν υπάρχει διάλειμμα.'),
                h('Παλμοί της άσκησης (πάνω δεξιά)'),
                p('Ο μέσος όρος των σετ της άσκησης που έχουν τιμή.'),
                h('Γιατί «~»'),
                p('Στα βάρη ο καρπός μετρά κατά προσέγγιση: όταν σφίγγεις τη λαβή, ο αισθητήρας χάνει λίγο την επαφή. '
                    'Γι’ αυτό δείχνουμε μόνο μέσους όρους, όχι το υψηλότερο κάθε σετ.'),
              ],
              h('Γιατί «—»'),
              p('Λιγότερες από 3 μετρήσεις σε εκείνο το διάστημα: καλύτερα κενό παρά αριθμός από μία-δύο τιμές.'),
              h('Για πιο σωστές μετρήσεις'),
              p('Λουρί σφιχτό αλλά άνετο, το ρολόι ένα με δύο δάχτυλα πάνω από το κόκαλο του καρπού. '
                  'Στα βάρη, αν μπορείς, μη λυγίζεις πολύ τον καρπό.'),
            ]),
          ),
        ),
      );
    },
  );
}
