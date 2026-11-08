import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../exercise/ex_data.dart';
import '../../format.dart';
import '../../theme.dart';
import '../../training/equipment.dart';
import '../../training/program.dart';
import '../../training/session.dart';
import '../../training/symptoms.dart';
import '../../training/training_store.dart';
import '../../training/wear_link.dart';
import '../../widgets.dart';
import 'program_editor.dart';
import 'hr_widgets.dart';
import 'program_paste.dart';
import 'session_page.dart';
import 'symptom_sheet.dart';
import 'training_common.dart';

/// Άσκηση › Προπόνηση: η σημερινή προπόνηση, η εβδομάδα, το πρόγραμμα, οι τελευταίες προπονήσεις.
class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key, required this.training, this.now});
  final TrainingStore training;
  final DateTime? now;

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  late final Future<void> _ready = Future.wait([widget.training.load(), ExLibrary.load()]);
  String? _chosen;

  TrainingStore get t => widget.training;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (!t.ready || ExLibrary.loaded == null) {
          return PageFrame(title: 'Προπόνηση', onRefresh: () async {}, left: const [
            Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          ]);
        }
        return ListenableBuilder(
          listenable: Listenable.merge([t, WearLink.main.ready, WearLink.main.live]),
          builder: (context, _) => _page(context),
        );
      },
    );
  }

  DateTime get _now => widget.now ?? t.now;

  Widget _page(BuildContext context) {
    final c = Aigaio.of(context);
    final p = t.program;
    final today = _now;
    final cards = <Widget>[];
    final side = <Widget>[];

    if (t.readError) {
      cards.add(EmptyCard(
        icon: Icons.error_outline_rounded,
        color: c.bad,
        title: 'Δεν διαβάστηκαν οι προπονήσεις',
        text: 'Για να μη χαθεί τίποτα, δεν γράφεται καμία αλλαγή. Κλείσε και άνοιξε ξανά την εφαρμογή.',
      ));
    }
    if (t.saveError != null) {
      cards.add(Text(t.saveError!, style: TextStyle(color: c.bad, fontWeight: FontWeight.w600)));
    }

    final pending = t.pendingWatchSymptom;
    if (pending != null) cards.add(_watchSymptomCard(context));
    final cur = t.current;
    if (cur != null) cards.add(_resumeCard(context, cur));
    final walk = _liveWalk();
    if (walk != null) cards.add(_walkCard(context, walk));
    if (!t.approved) cards.add(_lockedCard(context));

    if (p == null) {
      cards.add(_noProgram(context));
    } else {
      final w = _chosen == null ? p.forDay(today) : p.workout(_chosen);
      cards.add(_todayCard(context, p, w, today));
      cards.add(_weekCard(context, p, today));
      side.add(_programCard(context, p));
    }
    final recent = [for (final s in t.sessions.reversed) if (s.finished) s].take(6).toList();
    if (recent.isNotEmpty) side.add(_recentCard(context, recent));
    if (t.approved) side.add(_doctorCard(context));
    if (t.symptoms.any((x) => x.code != watchCode)) side.add(SymptomHistoryCard(training: t));
    // Και στην καθημερινότητα (σκάλες, ανηφόρα), όχι μόνο στην προπόνηση.
    side.add(FeelButton(training: t, where: walk != null ? 'walk' : 'day'));

    return PageFrame(
      title: 'Προπόνηση',
      onRefresh: () async {},
      left: cards,
      right: side,
    );
  }

  // ---------------------------------------------------------------- κάρτες
  Widget _resumeCard(BuildContext context, Session s) {
    final c = Aigaio.of(context);
    return AppCard(
      onTap: () => _openSession(context),
      child: Row(children: [
        IconBadge(Icons.play_arrow_rounded, c.exercise),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s.name} σε εξέλιξη', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
            Text('Από ${hm(s.start)} · ${s.setsDone} σετ', style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
          ]),
        ),
        FilledButton(
          key: const ValueKey('train-resume'),
          style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid),
          onPressed: () => _openSession(context),
          child: const Text('Συνέχεια'),
        ),
      ]),
    );
  }

  Widget _lockedCard(BuildContext context) {
    final c = Aigaio.of(context);
    final why = t.lockReason;
    final symptom = why == 'red' || why == 'amber2';
    final title = symptom
        ? 'Η άσκηση κλείδωσε μετά από σύμπτωμα'
        : why == 'meds'
            ? 'Τα βάρη κλείδωσαν: νέο φάρμακο'
            : why == 'manual'
                ? 'Τα βάρη είναι σε παύση'
                : t.waitingTests
                    ? 'Τα βάρη περιμένουν τις εξετάσεις'
                    : 'Τα βάρη περιμένουν τον καρδιολόγο';
    final text = symptom
        ? 'Στις ${t.lockedAt == null ? '' : dayMonth(t.lockedAt!)} κατέγραψες ${why == 'red' ? 'σοβαρό σύμπτωμα' : 'σύμπτωμα για δεύτερη φορά μέσα σε 14 μέρες'}. '
            'Μέχρι να σε δει γιατρός: καμία άσκηση, ούτε γρήγορο περπάτημα (και το ρολόι δεν ξεκινά). '
            'Αν δεν σε έχει δει ακόμα, πάρε σήμερα τον καρδιολόγο σου. Αν ξανασυμβεί ή χειροτερέψει: 166.'
        : why == 'meds'
            ? 'Ανοίγει ξανά όταν ο γιατρός πει ότι το φάρμακο δεν αλλάζει την άσκηση (ή δώσει νέο όριο παλμών).'
            : t.waitingTests
                ? 'Ο γιατρός ζήτησε εξετάσεις. Ανοίγει όταν πάρεις έγκριση με τα αποτελέσματα. Μέχρι τότε: χαλαρό περπάτημα.'
                : 'Η προπόνηση ανοίγει όταν πεις ότι πήρες πράσινο φως. Μέχρι τότε: χαλαρό περπάτημα, σε ρυθμό που μπορείς να μιλάς. '
                    'Μπορείς ήδη να ετοιμάσεις το πρόγραμμα.';
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconBadge(Icons.lock_outline_rounded, symptom ? c.bad : c.exercise),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text))),
        ]),
        const SizedBox(height: 10),
        Text(text, style: TextStyle(fontSize: 15, height: 1.45, color: c.text)),
        if (symptom) ...[const SizedBox(height: 12), const Call166Button()],
        const SizedBox(height: 12),
        OutlinedButton(
          key: const ValueKey('train-approve'),
          onPressed: () => _approve(context),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(symptom || why == 'meds' ? 'Με είδε γιατρός' : 'Πήρα έγκριση'),
        ),
      ]),
    );
  }

  /// «Νιώθω κάτι» πατήθηκε στο ρολόι: τι ένιωσες;
  Widget _watchSymptomCard(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      onTap: () => feelSomething(context, t, where: 'watch'),
      child: Row(children: [
        IconBadge(Icons.monitor_heart_outlined, c.bad),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Στο ρολόι πάτησες «Νιώθω κάτι»', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
            Text('Πες τι ένιωσες, για να ξέρεις τι κάνεις τώρα.', style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
          ]),
        ),
        FilledButton(
          key: const ValueKey('watch-sym'),
          style: FilledButton.styleFrom(backgroundColor: c.bad, foregroundColor: onBad(c)),
          onPressed: () => feelSomething(context, t, where: 'watch'),
          child: const Text('Πες'),
        ),
      ]),
    );
  }

  Widget _noProgram(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Δεν υπάρχει πρόγραμμα ακόμα', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text)),
        const SizedBox(height: 6),
        Text('Ζήτα από τον Claude να σου φτιάξει ένα και επικόλλησέ το, ή φτιάξ’ το μόνος σου από τη βιβλιοθήκη.',
            style: TextStyle(fontSize: 15, height: 1.45, color: c.textSecondary)),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('train-paste'),
          style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(48)),
          onPressed: () => Navigator.of(context).push(ProgramPastePage.route(t)),
          icon: const Icon(Icons.content_paste_rounded),
          label: const Text('Επικόλληση προγράμματος'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('train-new'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: () => Navigator.of(context).push(ProgramEditorPage.route(t, null)),
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('Φτιάξε το μόνος σου'),
        ),
      ]),
    );
  }

  Widget _todayCard(BuildContext context, Program p, Workout? w, DateTime today) {
    final c = Aigaio.of(context);
    final strength = [for (final x in p.workouts) if (!x.isCardio) x];
    final dayName = weekdayLong[today.weekday]!;
    final children = <Widget>[];
    if (w == null) {
      children.add(Text('$dayName: ξεκούραση', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text)));
      children.add(Text('Αν θες, διάλεξε προπόνηση από κάτω.', style: TextStyle(fontSize: 14, color: c.textSecondary)));
    } else if (w.isCardio) {
      final cardio = w.cardio!;
      children.addAll([
        Text('ΣΗΜΕΡΑ · ${upperGr(w.name)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.textSecondary)),
        const SizedBox(height: 4),
        Text('${cardio.name} ${cardio.minutes}′', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.text)),
        if (cardio.note != null) Text(cardio.note!, style: TextStyle(fontSize: 14.5, color: c.textSecondary)),
        const SizedBox(height: 8),
        Text(
            WearLink.main.ready.value
                ? 'Ξεκινά από το ρολόι («Ξεκίνα» στην εφαρμογή του ρολογιού), με παλμούς και απόσταση. Αν έχεις μαζί το κινητό, το βλέπεις ζωντανά εδώ.'
                : 'Ξεκινά από το ρολόι, με παλμούς και απόσταση, όταν μπει η εφαρμογή του ρολογιού. Ως τότε τα βήματα μετριούνται στην «Κίνηση».',
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary)),
      ]);
    } else {
      children.add(Row(children: [
        Expanded(child: Text('ΣΗΜΕΡΑ · ${upperGr(w.name)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.textSecondary))),
        if (WearLink.main.ready.value) ...[
          Icon(Icons.watch_rounded, size: 15, color: c.good),
          const SizedBox(width: 3),
          Text('ρολόι έτοιμο', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.good)),
          const SizedBox(width: 10),
        ],
        Text('~${w.minutes}′', style: TextStyle(fontSize: 13, color: c.textSecondary)),
      ]));
      if (w.note != null) children.add(Text(w.note!, style: TextStyle(fontSize: 14, color: c.textSecondary)));
      for (final item in w.items) {
        final tg = t.targetFor(item);
        final (col, arrow) = changeLook(context, tg.change);
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          // Όνομα αριστερά, στόχος δεξιά· αν δεν χωράνε (μεγάλα γράμματα), ο στόχος πάει από κάτω.
          child: SizedBox(
            width: double.infinity,
            child: Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, runSpacing: 2, children: [
              Text(exName(item.ex), style: TextStyle(fontSize: 15, color: c.text)),
              Text('${targetLine(item, tg)}$arrow', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: col)),
            ]),
          ),
        ));
      }
      final setup = _setupHint(w);
      if (setup != null) children.add(Padding(padding: const EdgeInsets.only(top: 4), child: Text(setup, style: TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary))));
      children.add(const SizedBox(height: 12));
      final can = t.approved && t.current == null;
      children.add(FilledButton(
        key: const ValueKey('train-start'),
        style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(52)),
        onPressed: can ? () => _start(context, w) : null,
        child: Text(t.current != null ? 'Υπάρχει προπόνηση σε εξέλιξη' : (t.approved ? 'Ξεκίνα την προπόνηση' : 'Ανοίγει μετά την έγκριση'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ));
    }
    if (strength.length > 1 || (w == null && strength.isNotEmpty)) {
      children.add(const SizedBox(height: 12));
      children.add(Wrap(spacing: 8, runSpacing: 8, children: [
        for (final x in p.workouts)
          Pill(
            key: ValueKey('train-pick-${x.id}'),
            label: x.name,
            selected: (w?.id) == x.id,
            onTap: () => setState(() => _chosen = x.id),
          ),
      ]));
    }
    return AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
  }

  /// Ποιοι δίσκοι στους αλτήρες/μπάρα στην αρχή (από την πρώτη άσκηση κάθε οργάνου).
  String? _setupHint(Workout w) {
    final seen = <String>{};
    final parts = <String>[];
    for (final i in w.items) {
      final k = i.kind;
      final tool = switch (k) { LoadKind.dbPair || LoadKind.db => 'db', LoadKind.bar => 'bar', LoadKind.kb => 'kb', _ => '' };
      if (tool.isEmpty || !seen.add(tool)) continue;
      parts.add(setupText(k, t.targetFor(i).load));
    }
    return parts.isEmpty ? null : 'Στήσιμο: ${parts.join(' · ')}.';
  }

  Widget _weekCard(BuildContext context, Program p, DateTime today) {
    final c = Aigaio.of(context);
    final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    final week = t.weekOf(today);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Η εβδομάδα', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 10),
        Row(children: [
          for (var d = 1; d <= 7; d++)
            Expanded(child: () {
              final day = DateTime(monday.year, monday.month, monday.day + d - 1);
              final w = p.workout(p.days[d]);
              final ds = [for (final s in week) if (s.finished && sameDay(s.start, day)) s];
              final done = ds.isNotEmpty;
              // Ό,τι έγινε πράγματι εκείνη τη μέρα (μπορεί να διαφέρει από το πρόγραμμα), με ✓.
              final doneW = done ? p.workout(ds.last.workout) : null;
              final isToday = sameDay(day, today);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isToday ? c.tint(c.exercise) : c.background,
                  borderRadius: BorderRadius.circular(10),
                  border: isToday ? Border.all(color: c.exercise, width: 1.5) : null,
                ),
                child: Column(children: [
                  Text(dayShort[d]!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
                  const SizedBox(height: 2),
                  Text(
                    done
                        ? (doneW == null || doneW.isCardio || doneW.id.length > 2 ? '✓' : '${doneW.id} ✓')
                        : (w == null ? '—' : (w.isCardio ? 'Περ.' : w.id)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: done ? c.good : c.textSecondary, fontWeight: done ? FontWeight.w700 : FontWeight.w500),
                  ),
                ]),
              );
            }()),
        ]),
      ]),
    );
  }

  Widget _programCard(BuildContext context, Program p) {
    final c = Aigaio.of(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Το πρόγραμμα', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 4),
        Text(p.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text)),
        Text(
          'Έκδοση ${p.version} · ${p.author == 'claude' ? 'από τον Claude' : 'δικό σου'}${p.from == null ? '' : ' · από ${shortDayDate(p.from!)}'}',
          style: TextStyle(fontSize: 13.5, color: c.textSecondary),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            key: const ValueKey('train-edit'),
            onPressed: () => Navigator.of(context).push(ProgramEditorPage.route(t, p)),
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('Αλλαγές'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(ProgramPastePage.route(t)),
            icon: const Icon(Icons.content_paste_rounded, size: 18),
            label: const Text('Επικόλληση νέου'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('train-export'),
            onPressed: () => _export(context),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Αντιγραφή για τον Claude'),
          ),
        ]),
      ]),
    );
  }

  Widget _recentCard(BuildContext context, List<Session> recent) {
    final c = Aigaio.of(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Τελευταίες προπονήσεις', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 4),
        for (final s in recent)
          InkWell(
            onTap: () => Navigator.of(context).push(SummaryPage.route(t, s)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${shortDayDate(s.start)} · ${s.name}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                    Text(
                        s.isCardio
                            ? '${s.cardioMinutes}′${s.meters != null ? ' · ${(s.meters! / 1000).toStringAsFixed(2).replaceAll('.', ',')} km' : ''}${s.hrAvg != null ? ' · ♥ ${s.hrAvg}' : ''}'
                            : '${s.duration.inMinutes}′ · ${s.setsDone} σετ${s.volume > 0 ? ' · ${thousands(s.volume.round())} kg' : ''}${s.hrAvg != null ? ' · ♥ ${s.hrAvg}' : ''}',
                        style: TextStyle(fontSize: 13, color: c.textSecondary)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _doctorCard(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      onTap: () => _approve(context, edit: true),
      child: Row(children: [
        IconBadge(Icons.favorite_rounded, c.bad),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Οδηγίες γιατρού', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
            Text(
              [
                t.hrLimit != null ? 'όριο παλμών ${t.hrLimit}' : 'χωρίς όριο, με την κούραση',
                if (t.hrMeds) 'φάρμακο για τους παλμούς',
                if (t.limits != null && t.limits!.isNotEmpty) t.limits!,
              ].join(' · '),
              style: TextStyle(fontSize: 13.5, color: c.textSecondary),
            ),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: c.textTertiary),
      ]),
    );
  }

  // ---------------------------------------------------------------- ενέργειες
  Future<void> _approve(BuildContext context, {bool edit = false}) async {
    final r = await showModalBottomSheet<_Clearance>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ClearanceSheet(training: t, edit: edit),
    );
    if (r == null) return;
    switch (r.kind) {
      case 'tests':
        t.waitForTests(notes: r.notes);
      case 'pause':
        t.relock('manual');
      default:
        final limit = r.kind == 'limit' ? r.hr : null;
        if (edit) {
          t.setLimits(hr: limit, notes: r.notes, meds: r.meds);
        } else {
          t.approve(hr: limit, notes: r.notes, meds: r.meds);
        }
    }
  }

  Future<void> _start(BuildContext context, Workout w) async {
    // «Νιώθω κάτι» από το ρολόι χωρίς λεπτομέρειες: πρώτα αυτό, όχι προπόνηση (έλεγχος #2, T2-02).
    if (t.pendingWatchSymptom != null) {
      await feelSomething(context, t, where: 'watch');
      return;
    }
    // Σύμπτωμα σήμερα: όχι προπόνηση σήμερα.
    if (t.watchHold == 'today') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Σήμερα έγραψες σύμπτωμα: χωρίς άσκηση σήμερα. Αν χειροτερέψει: 166.'),
        duration: Duration(seconds: 6),
      ));
      return;
    }
    // Τις πρώτες 4 εβδομάδες και μετά από σύμπτωμα: «Πώς είσαι σήμερα;» πριν από τα βάρη.
    if (t.needsCheck && !await readinessCheck(context, t)) return;
    if (!context.mounted) return;
    t.start(w);
    // Ανοίγει και η εφαρμογή στο ρολόι (παλμοί, ✓ στον καρπό), αν υπάρχει.
    WearLink.main.openWatch();
    _openSession(context);
  }

  /// Περπάτημα που τρέχει τώρα στο ρολόι (ήρθε μήνυμα τα τελευταία 30″).
  Map<String, dynamic>? _liveWalk() {
    final l = WearLink.main.live.value;
    if (l == null) return null;
    final at = (l['at'] as num?)?.toInt() ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - at > 30000) return null;
    return l;
  }

  Widget _walkCard(BuildContext context, Map<String, dynamic> l) {
    final c = Aigaio.of(context);
    final sec = (l['sec'] as num?)?.toInt() ?? 0;
    final m = (l['m'] as num?)?.toDouble() ?? 0;
    final steps = (l['steps'] as num?)?.toInt() ?? 0;
    final bpm = (l['bpm'] as num?)?.toInt() ?? 0;
    String two(int v) => v.toString().padLeft(2, '0');
    final time = sec >= 3600 ? '${sec ~/ 3600}:${two(sec % 3600 ~/ 60)}:${two(sec % 60)}' : '${sec ~/ 60}:${two(sec % 60)}';
    String pace() {
      if (m < 50 || sec <= 0) return '—';
      final p = (sec / (m / 1000)).round();
      return '${p ~/ 60}′${two(p % 60)}″';
    }

    Widget stat(String v, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.text)),
            Text(label, style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
          ]),
        );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('ΠΕΡΠΑΤΗΜΑ ΣΤΟ ΡΟΛΟΪ · ΖΩΝΤΑΝΑ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.textSecondary)),
        const SizedBox(height: 8),
        if (bpm > 0) ...[HrBar(bpm: bpm, limit: t.hrLimit), const SizedBox(height: 10)],
        Row(children: [stat(time, 'χρόνος'), stat(m > 0 ? (m / 1000).toStringAsFixed(2).replaceAll('.', ',') : '—', 'km')]),
        const SizedBox(height: 8),
        Row(children: [stat(pace(), 'ανά km'), stat(steps > 0 ? thousands(steps) : '—', 'βήματα')]),
        const SizedBox(height: 6),
        Text('Τελειώνει από το ρολόι. Μόλις τελειώσει, γράφεται εδώ.', style: TextStyle(fontSize: 13, color: c.textSecondary)),
      ]),
    );
  }

  void _openSession(BuildContext context) => Navigator.of(context).push(SessionPage.route(t));

  Future<void> _export(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: t.exportForClaude(names: exNames())));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Αντιγράφηκε. Επικόλλησέ το στη συζήτηση με τον Claude.')));
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _Clearance {
  const _Clearance(this.kind, {this.hr, this.notes, this.meds = false});

  /// 'limit' | 'none' | 'tests' | 'pause'
  final String kind;
  final int? hr;
  final String? notes;
  final bool meds;
}

/// Έγκριση γιατρού (έλεγχος 8/11): όριο παλμών με έλεγχο τιμής, «χωρίς όριο, με την κούραση» ρητά,
/// «θέλει εξετάσεις» (μένει κλειδωμένο), φάρμακο για τους παλμούς, παύση.
class _ClearanceSheet extends StatefulWidget {
  const _ClearanceSheet({required this.training, required this.edit});
  final TrainingStore training;
  final bool edit;

  @override
  State<_ClearanceSheet> createState() => _ClearanceSheetState();
}

class _ClearanceSheetState extends State<_ClearanceSheet> {
  TrainingStore get t => widget.training;
  late String _kind = widget.edit ? (t.hrLimit != null ? 'limit' : 'none') : '';
  late final _hr = TextEditingController(text: t.hrLimit?.toString() ?? '');
  late final _notes = TextEditingController(text: t.limits ?? '');
  late bool _meds = t.hrMeds;
  bool _lowOk = false;

  @override
  void dispose() {
    _hr.dispose();
    _notes.dispose();
    super.dispose();
  }

  int? get _value => int.tryParse(_hr.text.trim());

  String? get _error {
    if (_kind != 'limit') return null;
    final v = _value;
    if (_hr.text.trim().isEmpty) return null;
    if (v == null || v < 80 || v > 220) return 'Γράψε αριθμό από 80 έως 220';
    return null;
  }

  bool get _valid {
    switch (_kind) {
      case 'limit':
        final v = _value;
        return v != null && v >= 80 && v <= 220 && (v >= 100 || _lowOk);
      case 'none':
      case 'tests':
        return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    Widget option(String k, String title, String sub) {
      final on = _kind == k;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: on ? c.tint(c.exercise) : c.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: on ? c.exercise : c.hairline, width: on ? 2 : 1),
          ),
          child: InkWell(
            key: ValueKey('clear-$k'),
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onTap: () => setState(() => _kind = k),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: on ? c.exercise : c.textTertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text)),
                    Text(sub, style: TextStyle(fontSize: 13, height: 1.3, color: c.textSecondary)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    final v = _value;
    final askLow = _kind == 'limit' && v != null && v >= 80 && v < 100;
    final label = _kind == 'tests' ? 'Αποθήκευση' : (widget.edit ? 'Αποθήκευση' : 'Πήρα έγκριση');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .9),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.edit ? 'Οδηγίες γιατρού' : 'Τι είπε ο καρδιολόγος;', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
            const SizedBox(height: 12),
            option('limit', 'Μου έδωσε όριο παλμών', 'Το ρολόι δονείται αν το ξεπεράσεις.'),
            if (_kind == 'limit') ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
                child: TextField(
                  key: const ValueKey('train-hr'),
                  controller: _hr,
                  autofocus: !widget.edit,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                  onChanged: (_) => setState(() => _lowOk = false),
                  decoration: InputDecoration(labelText: 'Όριο παλμών', suffixText: 'bpm', errorText: _error, border: const OutlineInputBorder()),
                ),
              ),
              if (askLow)
                CheckboxListTile(
                  key: const ValueKey('train-hr-low'),
                  contentPadding: EdgeInsets.zero,
                  value: _lowOk,
                  onChanged: (x) => setState(() => _lowOk = x == true),
                  title: Text('Έγραψες $v. Σωστά;', style: TextStyle(fontSize: 14.5, color: c.text)),
                ),
            ],
            option('none', 'Χωρίς όριο, με την κούραση', 'Δεν μου έδωσε αριθμό· πηγαίνω με το πόσο κουράζομαι.'),
            if (!widget.edit) option('tests', 'Θέλει πρώτα εξετάσεις', 'Τα βάρη μένουν κλειδωμένα μέχρι τα αποτελέσματα.'),
            const SizedBox(height: 4),
            SwitchListTile(
              key: const ValueKey('train-meds'),
              contentPadding: EdgeInsets.zero,
              value: _meds,
              onChanged: (x) => setState(() => _meds = x),
              title: Text('Παίρνω φάρμακο που κόβει τους παλμούς', style: TextStyle(fontSize: 14.5, color: c.text)),
              subtitle: Text('π.χ. β-αναστολέα. Οι παλμοί ανεβαίνουν λιγότερο: το όριο ισχύει μόνο αν το έδωσε ο γιατρός με το φάρμακο, αλλιώς πήγαινε με την κούραση.', style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Περιορισμοί (προαιρετικά)', hintText: 'π.χ. όχι βαριά πάνω από το κεφάλι', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('train-approve-ok'),
              style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(50)),
              onPressed: !_valid ? null : () => Navigator.of(context).pop(_Clearance(_kind, hr: _value, notes: _notes.text.trim(), meds: _meds)),
              child: Text(label),
            ),
            if (widget.edit) ...[
              const SizedBox(height: 6),
              TextButton(
                key: const ValueKey('train-pause'),
                onPressed: () => Navigator.of(context).pop(const _Clearance('pause')),
                child: Text('Παύση των βαρών (κλείδωμα ξανά)', style: TextStyle(color: c.bad)),
              ),
            ],
          ])),
        ),
      ),
    );
  }
}
