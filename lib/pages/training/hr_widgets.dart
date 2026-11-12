import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../training/hr_quality.dart';
import '../../training/session.dart';
import '../../training/wear_link.dart';

/// Ζωντανοί παλμοί από το ρολόι, με γραμμή ως το όριο του γιατρού (σχέδιο 3, 8/11).
class HrBar extends StatelessWidget {
  const HrBar({super.key, required this.bpm, this.limit, this.bare = false});
  final int bpm;
  final int? limit;

  /// Χωρίς δικό του πλαίσιο, μέσα σε άλλη κάρτα (σχέδια 9/11, «Άσκηση σήμερα»).
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final over = limit != null && bpm >= limit!;
    return Semantics(
      liveRegion: true,
      label: 'Παλμοί $bpm${limit == null ? '' : ', όριο $limit'}${over ? ', πάνω από το όριο' : ''}',
      child: Container(
        padding: bare ? EdgeInsets.zero : const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: bare
            ? null
            : BoxDecoration(
                color: over ? c.bad.withValues(alpha: .12) : c.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: over ? c.bad : c.hairline, width: over ? 1.5 : 1),
              ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Icon(Icons.favorite_rounded, color: c.heart, size: 22),
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

/// Δεν έρχονται παλμοί από το ρολόι: να φαίνεται, όχι να εξαφανίζεται η γραμμή (έλεγχος 8/11).
/// Με όριο γιατρού (έλεγχος 9/11, V-A-05): ξεκάθαρα ότι το όριο δεν σε προσέχει τώρα και τι να κάνεις, και όταν το ρολόι
/// δεν βρέθηκε καθόλου (πριν: τίποτα στην οθόνη).
class HrStale extends StatelessWidget {
  const HrStale({super.key, this.limit, this.lost = true, this.watchFound = true});
  final int? limit;

  /// Ήρθαν παλμοί σε αυτή την προπόνηση και σταμάτησαν (αλλιώς δεν ήρθε κανένας ακόμα).
  final bool lost;

  /// Βρέθηκε ρολόι με την εφαρμογή μας.
  final bool watchFound;

  /// Τι να κάνεις, ανάλογα με το γιατί δεν έρχονται.
  String get hint {
    final what = lost
        ? 'Σφίξε λίγο το λουρί, πάνω από το κόκαλο του καρπού.'
        : watchFound
            ? 'Στο ρολόι πάτα «Παλμοί εδώ».'
            : 'Το ρολόι δεν βρέθηκε: άνοιξε την εφαρμογή στο ρολόι και πάτα «Παλμοί εδώ».';
    return limit == null ? what : '$what Ως τότε πήγαινε με την κούραση: να μπορείς να μιλάς.';
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final lim = limit;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('hr-stale'),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: c.warnBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.warnLine, width: lim == null ? 1 : 1.5),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(Icons.warning_amber_rounded, color: c.warn, size: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Δεν έρχονται παλμοί από το ρολόι', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.text)),
              if (lim != null)
                Text('Το όριο ($lim) δεν σε προσέχει τώρα.',
                    key: const ValueKey('hr-limit-off'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.warn)),
              Text(hint, style: TextStyle(fontSize: 13, height: 1.3, color: c.textSecondary)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Τα πρώτα δευτερόλεπτα με το ρολόι κοντά (ανοίγει μόνο του και μπαίνει στην προπόνηση): ήρεμη γραμμή, όχι
/// προειδοποίηση. Ίδιος χρόνος με το ρολόι ([hrWaitSeconds]).
class HrWaiting extends StatelessWidget {
  const HrWaiting({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Container(
      key: const ValueKey('hr-waiting'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.hairline)),
      child: Row(children: [
        Icon(Icons.watch_rounded, color: c.textSecondary, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text('Περιμένω παλμούς από το ρολόι…', style: TextStyle(fontSize: 14, color: c.textSecondary))),
      ]),
    );
  }
}

/// Πόσα δευτερόλεπτα από την αρχή, με το ρολόι κοντά, περιμένει το κινητό τον πρώτο παλμό πριν πει «το όριο δεν σε
/// προσέχει». Ίδια με τον έλεγχο του ρολογιού (HrSilence, 30″), ώστε οι δύο να λένε το ίδιο την ίδια στιγμή.
const hrWaitSeconds = 30;

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

/// Ο υψηλότερος παλμός όπως τον γράφει η κάρτα (απόφαση 12/11, τελικός έλεγχος μ5). Στα βάρη με «~»: είναι ΜΙΑ στιγμιαία
/// τιμή του καρπού, και όταν σφίγγεις τη λαβή ο αισθητήρας χάνει την επαφή. Στο περπάτημα (σταθερή κίνηση) σκέτος.
String hrMaxText(int max, {required bool cardio}) => cardio ? '$max' : '~$max';

/// Η γραμμή κάτω από τους αριθμούς, μόνο στα βάρη (κείμενο εγκεκριμένο 12/11).
const hrMaxApproxText = 'Υψηλότερος: στιγμιαία τιμή, κατά προσέγγιση.';

/// Παλμοί μιας προπόνησης στη σύνοψη: μέσος, υψηλότερος, γράφημα με το όριο (σχέδιο 5, 8/11).
/// Έλεγχος 9/11 (V-B-04): κρίνεται ΜΟΝΟ με το όριο που ίσχυε σε αυτή την προπόνηση ([Session.limitUsed]). Χωρίς όριο
/// τότε, ή παλιά προπόνηση που δεν το κράτησε (πριν από την #90): μόνο οι παλμοί, χωρίς γραμμή ορίου και χωρίς κρίση
/// (ποτέ αναδρομικά με το σημερινό όριο).
class HrCard extends StatelessWidget {
  const HrCard({super.key, required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final lim = session.limitUsed;
    final h = HrSummary(session, lim);
    final mins = (h.overSec / 60).ceil();
    const which = 'το όριο';
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
          if (h.max != null) _stat(c, hrMaxText(h.max!, cardio: session.isCardio), 'υψηλότερος'),
          // Η τιμή της Προόδου («Παλμοί στο περπάτημα», σταθερό βάδισμα· έλεγχος του fix-accuracy, S8): να βρίσκεται.
          if (session.isCardio && session.steadyHr != null)
            KeyedSubtree(key: const ValueKey('hr-steady'), child: _stat(c, '${session.steadyHr}', 'από το 5′')),
        ]),
        // Απόφαση 12/11 (τελικός έλεγχος, μ5): στα βάρη ο υψηλότερος είναι μία στιγμιαία τιμή του καρπού. Το λέει η οθόνη.
        if (h.max != null && !session.isCardio) ...[
          const SizedBox(height: 4),
          Text(hrMaxApproxText, key: const ValueKey('hr-max-approx'), style: TextStyle(fontSize: 12.5, height: 1.35, color: c.textSecondary)),
        ],
        if (session.hr.length >= 2) ...[
          const SizedBox(height: 10),
          SizedBox(height: 70, child: CustomPaint(painter: _HrChart(session.hr, lim, c))),
        ],
        if (lim != null) ...[
          const SizedBox(height: 8),
          Text(
            h.overSec > 0
                ? 'Πάνω από $which ($lim) για περίπου $mins′.'
                : (h.max != null && h.max! >= lim)
                    ? 'Έφτασες στιγμιαία $which ($lim).'
                    // Ο καρπός μετρά λιγότερο όσο δυναμώνει η προσπάθεια (Boudreaux 2018· έλεγχος #2).
                    // Στο περπάτημα ο καρπός μετρά καλά (σταθερή κίνηση)· η επιφύλαξη ισχύει μόνο για τα βάρη.
                    : session.isCardio
                        ? 'Το ρολόι δεν έδειξε παλμούς πάνω από $which ($lim).'
                        : 'Το ρολόι δεν έδειξε παλμούς πάνω από $which ($lim). Στα βάρη ο καρπός συχνά μετρά πιο χαμηλά· '
                            'πρώτα μετράει πώς νιώθεις.',
            key: const ValueKey('hr-limit-line'),
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: h.overSec > 0 ? c.bad : c.text),
          ),
        ],
        if (session.hrGap case final g?) ...[
          const SizedBox(height: 6),
          // Πόσο γρήγορα έφταναν οι παλμοί από το ρολόι (8/11): μέτρο για το πόσο μπορεί να αργήσει η ειδοποίηση.
          Builder(builder: (context) {
            final (text, warn) = hrGapText(g, session.hrMode, session.hrDel, lim != null);
            return Text(text, key: const ValueKey('hr-gap'), style: TextStyle(fontSize: 12.5, height: 1.35, color: warn ? c.exercise : c.textSecondary));
          }),
        ],
        // 13/11: πόσες τιμές ήρθαν με καλή επαφή, όπως τις μέτρησε το ρολόι (μόνο όταν το ρολόι στέλνει καταμέτρηση).
        if (hrQualityFromDiag(session.watchDiag) case final q?) ...[
          const SizedBox(height: 6),
          Text(hrQualityText(q), key: const ValueKey('hr-quality'), style: TextStyle(fontSize: 12.5, height: 1.35, color: c.textSecondary)),
        ],
        // Έλεγχος του γ2 (S1): με όριο, ρολόι σε «default» (ούτε ανά 5″ ούτε αισθητήρας): η δόνηση μπορεί να άργησε.
        if (lim != null && session.hrMode == 'default') ...[
          const SizedBox(height: 4),
          Text(slowAlarmText, key: const ValueKey('hr-slow'), style: TextStyle(fontSize: 12.5, height: 1.35, color: c.exercise)),
        ],
        // Έλεγχος γ2 (W2-14): γιατί σταμάτησε η μέτρηση στο ρολόι (για τη δοκιμή στη συσκευή), όχι μια γενική φράση.
        if (session.watchErr case final e?) ...[
          const SizedBox(height: 4),
          Text('Σφάλμα στο ρολόι: $e', key: const ValueKey('hr-watch-err'), style: TextStyle(fontSize: 12, height: 1.3, color: c.textSecondary)),
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

/// Το ρολόι στέλνει παλμούς αργά με σβηστή οθόνη (ούτε ανά 5″ ούτε αισθητήρας αφύπνισης· έλεγχος του γ2, S1). Ίδιο
/// κείμενο με το ρολόι, χωρίς αριθμό που δεν έχει μετρηθεί.
const slowAlarmText = 'Με σβηστή οθόνη η δόνηση του ορίου μπορεί να αργήσει λίγα λεπτά σε αυτό το ρολόι.';

/// Πόσο συχνά ήρθαν οι παλμοί από το ρολόι, για τη σύνοψη (8/11· έλεγχος γ2, W2-08). [gap]: μεγαλύτερο κενό (″),
/// [deliveries]: πόσες φορές ήρθαν (ρολόι από γ2· null = παλιό ρολόι), [hasLimit]: είχε όριο. Επιστρέφει (κείμενο,
/// προειδοποίηση). Όλο το περπάτημα σε μία-δύο φορές δεν είναι «κάθε λίγα δευτερόλεπτα»· χωρίς όριο δεν υπάρχει
/// ειδοποίηση που «άργησε».
(String, bool) hrGapText(int gap, String? mode, int? deliveries, bool hasLimit) {
  final late = hasLimit ? ' Η ειδοποίηση μπορεί να άργησε.' : '';
  if (deliveries != null && deliveries < 3) {
    return (deliveries <= 1 ? 'Οι παλμοί ήρθαν όλοι μαζί, μία φορά.$late' : 'Οι παλμοί ήρθαν όλοι μαζί, σε $deliveries φορές.$late', true);
  }
  if (gap <= 12) {
    return ('Οι παλμοί έφταναν κάθε λίγα δευτερόλεπτα (μεγαλύτερο κενό $gap″)${mode == 'sensor' ? ', απευθείας από τον αισθητήρα' : ''}.', false);
  }
  final t = gap < 120 ? '$gap″' : '${(gap / 60).round()}′';
  return (hasLimit ? 'Μεγαλύτερο κενό στους παλμούς: $t. Τόσο μπορεί να άργησε η ειδοποίηση.' : 'Οι παλμοί έλειπαν έως $t.', true);
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
                // Έλεγχος 9/11 (03-Χ1, 04-L6): μέσος όρος των τελευταίων 10″ (όχι το ελάχιστο, που δείχνει πιο χαμηλά)·
                // η πτώση εξαρτάται από τη διάρκεια του διαλείμματος και το σετ.
                p('Οι παλμοί λίγο πριν ξεκινήσεις το επόμενο σετ (ο μέσος όρος των τελευταίων 10 δευτερολέπτων του διαλείμματος). '
                    'Το πόσο πέφτουν εξαρτάται από το πόσο κράτησε το διάλειμμα και πόσο βαρύ ήταν το σετ. Στο τελευταίο σετ '
                    'δεν υπάρχει διάλειμμα.'),
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
