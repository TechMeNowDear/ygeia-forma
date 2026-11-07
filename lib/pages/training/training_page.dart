import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../exercise/ex_data.dart';
import '../../format.dart';
import '../../theme.dart';
import '../../training/equipment.dart';
import '../../training/program.dart';
import '../../training/session.dart';
import '../../training/training_store.dart';
import '../../widgets.dart';
import 'program_editor.dart';
import 'program_paste.dart';
import 'session_page.dart';
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
        return ListenableBuilder(listenable: t, builder: (context, _) => _page(context));
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

    final cur = t.current;
    if (cur != null) cards.add(_resumeCard(context, cur));
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
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconBadge(Icons.lock_outline_rounded, c.exercise),
          const SizedBox(width: 12),
          Expanded(child: Text('Τα βάρη περιμένουν τον καρδιολόγο', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text))),
        ]),
        const SizedBox(height: 10),
        Text(
          'Η προπόνηση ανοίγει όταν πεις ότι πήρες πράσινο φως. Μέχρι τότε: χαλαρό περπάτημα, σε ρυθμό που μπορείς να μιλάς. '
          'Μπορείς ήδη να ετοιμάσεις το πρόγραμμα.',
          style: TextStyle(fontSize: 15, height: 1.45, color: c.text),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const ValueKey('train-approve'),
          onPressed: () => _approve(context),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('Πήρα έγκριση'),
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
        Text('ΣΗΜΕΡΑ · ${w.name.toUpperCase()}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.textSecondary)),
        const SizedBox(height: 4),
        Text('${cardio.name} ${cardio.minutes}′', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.text)),
        if (cardio.note != null) Text(cardio.note!, style: TextStyle(fontSize: 14.5, color: c.textSecondary)),
        const SizedBox(height: 8),
        Text('Θα ξεκινά από το ρολόι, με παλμούς και απόσταση, όταν έρθει η εφαρμογή του ρολογιού. Ως τότε τα βήματα μετριούνται στην «Κίνηση».',
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary)),
      ]);
    } else {
      children.add(Row(children: [
        Expanded(child: Text('ΣΗΜΕΡΑ · ${w.name.toUpperCase()}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.textSecondary))),
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
              final done = week.any((s) => s.finished && sameDay(s.start, day));
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
                    w == null ? '—' : (w.isCardio ? 'Περ.' : w.id) + (done ? ' ✓' : ''),
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
                    Text('${s.duration.inMinutes}′ · ${s.setsDone} σετ${s.volume > 0 ? ' · ${thousands(s.volume.round())} kg' : ''}',
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
              [if (t.hrLimit != null) 'όριο παλμών ${t.hrLimit}', if (t.limits != null && t.limits!.isNotEmpty) t.limits!].join(' · ').ifEmpty('Χωρίς όριο παλμών'),
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
    final hr = TextEditingController(text: t.hrLimit?.toString() ?? '');
    final notes = TextEditingController(text: t.limits ?? '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final c = Aigaio.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(edit ? 'Οδηγίες γιατρού' : 'Πράσινο φως από τον καρδιολόγο', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
            const SizedBox(height: 8),
            Text('Αν σου έδωσε όριο παλμών ή περιορισμούς, γράψ’ τα εδώ. Το όριο θα φαίνεται στην προπόνηση.',
                style: TextStyle(fontSize: 14.5, height: 1.4, color: c.textSecondary)),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('train-hr'),
              controller: hr,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
              decoration: const InputDecoration(labelText: 'Όριο παλμών (προαιρετικά)', suffixText: 'bpm', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Περιορισμοί (προαιρετικά)', hintText: 'π.χ. όχι βαριά πάνω από το κεφάλι', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('train-approve-ok'),
              style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(50)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(edit ? 'Αποθήκευση' : 'Πήρα έγκριση'),
            ),
          ]),
        );
      },
    );
    if (ok != true) return;
    final v = int.tryParse(hr.text.trim());
    final limit = v != null && v >= 80 && v <= 220 ? v : null;
    if (edit) {
      t.setLimits(hr: limit, notes: notes.text.trim());
    } else {
      t.approve(hr: limit, notes: notes.text.trim());
    }
  }

  void _start(BuildContext context, Workout w) {
    t.start(w);
    _openSession(context);
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
