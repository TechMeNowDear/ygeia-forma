import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../exercise/ex_data.dart';
import '../../format.dart';
import '../../theme.dart';
import '../../data.dart' show HealthStore;
import '../../training/equipment.dart';
import '../../training/progress.dart';
import '../../trends.dart' show TrendPeriod;
import '../../training/program.dart';
import '../../training/progression.dart' show Change;
import '../../training/session.dart';
import '../../training/training_store.dart';
import '../../training/wear_link.dart';
import '../../widgets.dart';
import 'program_editor.dart';
import 'hr_widgets.dart';
import 'program_paste.dart';
import 'progress_page.dart';
import 'session_page.dart';
import 'training_common.dart';

/// Άσκηση › Προπόνηση: η σημερινή προπόνηση, η εβδομάδα, το πρόγραμμα, οι τελευταίες προπονήσεις.
class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key, required this.training, this.now, this.health, this.onOpenTrends});
  final TrainingStore training;
  final DateTime? now;

  /// Για την «Πρόοδο»: σώμα και ξεκούραση από τις «Τάσεις», και μετάβαση σε αυτές.
  final HealthStore? health;
  final VoidCallback? onOpenTrends;

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
          listenable: Listenable.merge(
              [t, WearLink.main.ready, WearLink.main.live, WearLink.main.sentLimit, WearLink.main.watchLimit, WearLink.main.watchNewer]),
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
        title: t.newerFile ? 'Ενημέρωσε την εφαρμογή' : 'Δεν διαβάστηκαν οι προπονήσεις',
        text: t.newerFile
            ? 'Οι προπονήσεις γράφτηκαν από νεότερη έκδοση της εφαρμογής. Ως την ενημέρωση δεν γράφεται τίποτα, για να μη χαθεί.'
            : 'Για να μη χαθεί τίποτα, δεν γράφεται καμία αλλαγή, και ό,τι έγινε στο ρολόι περιμένει εκεί. Κλείσε και άνοιξε ξανά την εφαρμογή.',
      ));
    }
    if (t.saveError != null) {
      cards.add(Text(t.saveError!, style: TextStyle(color: c.bad, fontWeight: FontWeight.w600)));
    }
    // Αποτέλεσμα από ρολόι νεότερης έκδοσης (V-A-08): περιμένει στο ρολόι.
    if (WearLink.main.watchNewer.value) {
      cards.add(EmptyCard(
        key: const ValueKey('train-watch-newer'),
        icon: Icons.system_update_rounded,
        color: c.exercise,
        title: 'Ενημέρωσε την εφαρμογή στο κινητό',
        text: 'Το ρολόι έχει νεότερη έκδοση. Ό,τι έγινε εκεί περιμένει στο ρολόι και περνά μόλις ενημερωθεί το κινητό.',
      ));
    }

    final cur = t.current;
    if (cur != null) cards.add(t.isStale(cur) ? _forgottenCard(context, cur) : _resumeCard(context, cur));
    final walk = _liveWalk();
    if (walk != null) cards.add(_walkCard(context, walk));

    if (p == null) {
      cards.add(_noProgram(context));
      if (cur == null) cards.add(_freeCard(context));
    } else {
      final w = _chosen == null ? p.forDay(today) : p.workout(_chosen);
      cards.add(_todayCard(context, p, w, today));
      final strengthDone = [for (final x in t.sessions.reversed) if (x.finished && !x.isCardio) x];
      final lastStrength = strengthDone.isEmpty ? null : strengthDone.first;
      if (lastStrength != null) cards.add(_lastCard(context, lastStrength));
      if (cur == null) cards.add(_freeCard(context));
      cards.add(_weekCard(context, p, today));
      side.add(_programCard(context, p));
    }
    side.add(_progressCard(context));
    final recent = [for (final s in t.sessions.reversed) if (s.finished) s].take(6).toList();
    if (recent.isNotEmpty) side.add(_recentCard(context, recent));
    side.add(_hrLimitCard(context));
    // Προπονήσεις που δεν διαβάστηκαν (V-A-10): κρατιούνται στο αρχείο, όχι χαμένες· μόνο μια μικρή σημείωση.
    final badHr = t.sessions.where((s) => s.hrBad != null).length;
    if (t.quarantine.isNotEmpty || badHr > 0) {
      final n = t.quarantine.length;
      side.add(Padding(
        key: const ValueKey('train-quarantine'),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          [
            if (n > 0)
              n == 1
                  ? '1 καταγραφή προπόνησης δεν διαβάστηκε· κρατιέται στο αρχείο και μπαίνει στο αντίγραφο.'
                  : '$n καταγραφές προπόνησης δεν διαβάστηκαν· κρατιούνται στο αρχείο και μπαίνουν στο αντίγραφο.',
            if (badHr > 0)
              badHr == 1
                  ? 'Οι παλμοί 1 προπόνησης δεν διαβάστηκαν· το αρχείο τους κρατήθηκε στην άκρη.'
                  : 'Οι παλμοί $badHr προπονήσεων δεν διαβάστηκαν· τα αρχεία τους κρατήθηκαν στην άκρη.',
          ].join(' '),
          style: TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary),
        ),
      ));
    }

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
            Text('Από ${sameDay(s.start, _now) ? '' : '${shortDayDate(s.start)} '}${hm(s.start)} · ${s.setsDone} σετ',
                style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
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

  /// «Ξεχασμένη προπόνηση;» (έλεγχος 9/11, V-A-09): ανοιχτή χωρίς κίνηση εδώ και 3 ώρες. Ένα πάτημα «Τέλος (στις 19:22)» με
  /// το τελευταίο ✓ ως τέλος· ποτέ διάρκεια 20 ωρών. Χωρίς κανένα σετ: «Σβήσιμο».
  Widget _forgottenCard(BuildContext context, Session s) {
    final c = Aigaio.of(context);
    final last = s.lastActivity;
    final when = sameDay(s.start, _now) ? 'στις ${hm(s.start)}' : '${longDate(s.start)} στις ${hm(s.start)}';
    final none = s.setsDone == 0;
    return AppCard(
      key: const ValueKey('train-forgotten'),
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
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (none)
            FilledButton(
              key: const ValueKey('train-forgotten-drop'),
              style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size(0, 48)),
              onPressed: () => t.discard(),
              child: const Text('Σβήσιμο'),
            )
          else
            FilledButton(
              key: const ValueKey('train-forgotten-end'),
              style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size(0, 48)),
              onPressed: () => t.finish(end: last),
              child: Text('Τέλος (στις ${hm(last)})'),
            ),
          TextButton(
            key: const ValueKey('train-forgotten-resume'),
            style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => _openSession(context),
            child: const Text('Συνέχεια'),
          ),
        ]),
      ]),
    );
  }

  /// «Πρόοδος» (9/11): οι δύο πιο ξεκάθαρες αλλαγές (μόνο από την προπόνηση· το σώμα φαίνεται μέσα στη σελίδα).
  Widget _progressCard(BuildContext context) {
    final c = Aigaio.of(context);
    final walk = walkProgress(t.sessions, _now, TrendPeriod.month);
    final strength = strengthProgress(t.sessions, _now, TrendPeriod.month);
    final top = progressHighlights(walk, strength, const []).take(2).map((e) => e.$1).toList();
    final sub = top.isNotEmpty
        ? top.join(' · ')
        : (walk.insufficient && strength.isEmpty
            ? 'Η πρώτη σύγκριση μετά από λίγες εβδομάδες προπόνησης και περπατήματος.'
            : 'Καμία ξεκάθαρη αλλαγή τον τελευταίο μήνα.');
    return AppCard(
      key: const ValueKey('train-progress'),
      onTap: () => Navigator.of(context).push(ProgressPage.route(t, health: widget.health, onOpenTrends: widget.onOpenTrends, now: widget.now)),
      child: Row(children: [
        IconBadge(Icons.trending_up_rounded, c.exercise),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Πρόοδος', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
            Text(sub, style: TextStyle(fontSize: 13.5, height: 1.35, color: c.textSecondary)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: c.textSecondary),
      ]),
    );
  }

  /// «Ελεύθερη άσκηση» (9/11): χωρίς πρόγραμμα, διαλέγεις τις ασκήσεις τη στιγμή. Το ρολόι ακολουθεί όπως πάντα.
  Widget _freeCard(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      key: const ValueKey('train-free'),
      onTap: () => _startFree(context),
      child: Row(children: [
        IconBadge(Icons.add_rounded, c.exercise),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ελεύθερη άσκηση', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
            Text('Διαλέγεις τις ασκήσεις τη στιγμή, μία-μία.', style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: c.textSecondary),
      ]),
    );
  }

  void _startFree(BuildContext context) {
    if (t.current != null) return;
    t.startFree();
    WearLink.main.openWatch();
    _openSession(context);
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
        // Και χωρίς πρόγραμμα να φαίνεται ότι το ρολόι βρέθηκε (9/11).
        if (WearLink.main.ready.value) ...[
          const SizedBox(height: 10),
          Row(key: const ValueKey('train-watch-ready'), children: [
            Icon(Icons.watch_rounded, size: 16, color: c.good),
            const SizedBox(width: 4),
            Text('ρολόι έτοιμο', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.good)),
          ]),
        ],
      ]),
    );
  }

  /// ⋮ του προγράμματος (σχέδια 9/11, 6α): αλλαγές, επικόλληση νέου, αντιγραφή, και άλλη προπόνηση για σήμερα.
  Widget _programMenu(BuildContext context, Program p, {Workout? w, required String key, bool picks = true}) {
    final others = [if (picks) for (final x in p.workouts) if (x.id != w?.id) x];
    return PopupMenuButton<String>(
      key: ValueKey(key),
      tooltip: 'Πρόγραμμα',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) {
        switch (v) {
          case 'edit':
            Navigator.of(context).push(ProgramEditorPage.route(t, p));
          case 'paste':
            Navigator.of(context).push(ProgramPastePage.route(t));
          case 'export':
            _export(context);
          default:
            if (v.startsWith('pick:')) setState(() => _chosen = v.substring(5));
        }
      },
      itemBuilder: (_) => [
        for (final x in others)
          PopupMenuItem(value: 'pick:${x.id}', key: ValueKey('train-pick-${x.id}'), child: Text('Σήμερα: ${x.name}')),
        if (others.isNotEmpty) const PopupMenuDivider(),
        const PopupMenuItem(value: 'edit', key: ValueKey('train-edit'), child: Text('Αλλαγές στο πρόγραμμα')),
        const PopupMenuItem(value: 'paste', key: ValueKey('train-paste-new'), child: Text('Επικόλληση νέου')),
        const PopupMenuItem(value: 'export', key: ValueKey('train-export'), child: Text('Αντιγραφή για τον Claude')),
      ],
    );
  }

  bool _allItems = false;

  Widget _todayCard(BuildContext context, Program p, Workout? w, DateTime today) {
    final c = Aigaio.of(context);
    final dayName = weekdayLong[today.weekday]!;
    final children = <Widget>[];
    final title = TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.15, color: c.text);
    final aux = TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary);
    if (w == null) {
      children.add(Text('$dayName: ξεκούραση', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.text)));
      children.add(Text('Αν θες, διάλεξε προπόνηση από το ⋮.', style: TextStyle(fontSize: 14, color: c.textSecondary)));
    } else if (w.isCardio) {
      final cardio = w.cardio!;
      children.addAll([
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(cardio.name, maxLines: 1, style: title)),
        Text(['${cardio.minutes} λεπτά', if (cardio.note != null && cardio.note!.trim().isNotEmpty) cardio.note!.trim()].join(' · '), style: aux),
        const SizedBox(height: 12),
        Text(
            WearLink.main.ready.value
                ? 'Ξεκινά από το ρολόι: πάτα «${cardio.name}», με παλμούς και απόσταση. Αν έχεις μαζί το κινητό, το βλέπεις ζωντανά εδώ.'
                : 'Ξεκινά από το ρολόι, με παλμούς και απόσταση, όταν μπει η εφαρμογή του ρολογιού. Ως τότε τα βήματα μετριούνται στην «Κίνηση».',
            style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary)),
      ]);
    } else {
      children.add(FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(w.name, maxLines: 1, style: title)));
      children.add(Text('${countText(w.items.length, 'άσκηση', 'ασκήσεις')} · περίπου ${w.minutes} λεπτά', style: aux));
      if (w.note != null) children.add(Text(w.note!, style: TextStyle(fontSize: 14, color: c.textSecondary)));
      final shown = _allItems || w.items.length <= 6 ? w.items : w.items.take(5).toList();
      for (var n = 0; n < shown.length; n++) {
        final item = shown[n];
        final tg = t.targetFor(item);
        final en = ExLibrary.loaded?.byId(item.ex)?.en ?? '';
        final k = item.kind;
        // Σχέδια 9/11 (6α): «ανεβαίνει» αντί για «↑», σε λέξη· +1 επανάληψη γράφεται στη γραμμή του στόχου.
        final (String, Color)? pill = switch (tg.change) {
          Change.up || Change.variant => ('ανεβαίνει', c.good),
          Change.down || Change.back => ('πιο ελαφρύ', c.textSecondary),
          Change.pain => ('πόνεσε', c.warn),
          _ => null,
        };
        final reps = repsList(tg.reps);
        final more = tg.change == Change.more ? ' · +1 επανάληψη' : '';
        children.add(Container(
          key: ValueKey('train-item-${item.ex}'),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: n < shown.length - 1 ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: exName(item.ex), style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                    if (en.isNotEmpty) TextSpan(text: ' · $en', style: TextStyle(color: c.textSecondary)),
                  ]),
                  style: const TextStyle(fontSize: 15, height: 1.35),
                ),
              ),
              if (pill != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: c.tint(pill.$2), borderRadius: BorderRadius.circular(999)),
                  child: Text(pill.$1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pill.$2)),
                ),
              ],
            ]),
            Text('${item.sets} σετ × ${item.lo == item.hi ? '${item.lo}' : '${item.lo}–${item.hi}'} · άφησε ${item.rir}', style: aux),
            if (isBand(k) && (tg.load ?? 0) > 0)
              Row(children: [
                BandDots(tg.load, size: 14),
                Flexible(child: Text('${bandName(tg.load!)} · $reps$more', style: TextStyle(fontSize: 14, color: c.text, fontFeatures: tabular))),
              ])
            else
              Text('${hasLoad(k) ? '${loadLabel(k, tg.load)} · ' : ''}$reps$more', style: TextStyle(fontSize: 14, color: c.text, fontFeatures: tabular)),
          ]),
        ));
      }
      if (shown.length < w.items.length) {
        final rest = w.items.length - shown.length;
        children.add(Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('train-more-items'),
            style: TextButton.styleFrom(foregroundColor: c.textSecondary, padding: EdgeInsets.zero),
            onPressed: () => setState(() => _allItems = true),
            child: Text(rest == 1 ? 'και 1 ακόμα άσκηση' : 'και $rest ακόμα ασκήσεις'),
          ),
        ));
      }
      children.add(const SizedBox(height: 12));
      final can = t.current == null;
      children.add(FilledButton(
        key: const ValueKey('train-start'),
        style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(52)),
        onPressed: can ? () => _start(context, w) : null,
        child: Text(t.current != null ? 'Υπάρχει προπόνηση σε εξέλιξη' : 'Ξεκίνα την προπόνηση',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ));
      children.add(const SizedBox(height: 12));
      children.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.directions_walk_rounded, size: 18, color: c.textSecondary),
        const SizedBox(width: 6),
        Expanded(child: Text('Για περπάτημα: στο ρολόι πάτα «Περπάτημα».', style: aux)),
      ]));
    }
    return AppCard(
      key: const ValueKey('train-today'),
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: CardHeader(icon: Icons.fitness_center_rounded, title: 'Σήμερα', color: c.exercise)),
          _programMenu(context, p, w: w, key: 'train-today-more'),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ]),
    );
  }

  /// Ποιοι δίσκοι στους αλτήρες/μπάρα στην αρχή (από την πρώτη άσκηση κάθε οργάνου).
  String? _setupHint(Workout w) {
    final seen = <String>{};
    final parts = <String>[];
    for (final i in w.items) {
      final k = i.kind;
      final tool = switch (k) { LoadKind.dbPair || LoadKind.db => 'db', LoadKind.bar => 'bar', LoadKind.kb => 'kb', LoadKind.bandPair => 'bands', _ => '' };
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
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Το πρόγραμμα', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text))),
          // Σχέδια 9/11 (6α): τα τρία κουμπιά του προγράμματος στο ⋮.
          _programMenu(context, p, key: 'train-program-more', picks: false),
        ]),
        const SizedBox(height: 4),
        Text(p.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text)),
        Text(
          'Έκδοση ${p.version} · ${p.author == 'claude' ? 'από τον Claude' : 'δικό σου'}${p.from == null ? '' : ' · από ${shortDayDate(p.from!)}'}',
          style: TextStyle(fontSize: 13.5, color: c.textSecondary),
        ),
      ]),
    );
  }

  /// «Τελευταία φορά · Πέμ 5/11» (σχέδια 9/11, 6α): διάρκεια, σετ, σύνολο κιλών· πάτημα → σύνοψη.
  Widget _lastCard(BuildContext context, Session s) {
    final c = Aigaio.of(context);
    Widget stat(String v, String unit, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
                  if (unit.isNotEmpty) TextSpan(text: ' $unit', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textSecondary)),
                ]),
                maxLines: 1,
                style: const TextStyle(fontFeatures: tabular),
              ),
            ),
            Text(label, style: TextStyle(fontSize: 13, color: c.textSecondary)),
          ]),
        );
    return AppCard(
      key: const ValueKey('train-last'),
      onTap: () => Navigator.of(context).push(SummaryPage.route(t, s)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader(
          icon: Icons.check_rounded,
          title: 'Τελευταία φορά · ${shortDayDate(s.start)}',
          color: c.good,
          trailing: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
        ),
        const SizedBox(height: 10),
        Row(children: [
          stat('${s.duration.inMinutes}', 'λ', 'διάρκεια'),
          stat('${s.setsDone}', '', 'σετ'),
          stat(s.volume > 0 ? thousands(s.volume.round()) : '—', s.volume > 0 ? 'kg' : '', 'σύνολο κιλών'),
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

  /// Όριο παλμών από τον γιατρό: αν υπάρχει, το ρολόι δονείται όσο μετρά άσκηση και οι παλμοί μείνουν πάνω του.
  /// Έλεγχος 9/11 (V-B-05, V-A-05): όχι απόλυτη υπόσχεση, και φαίνεται αν το όριο έφτασε στο ρολόι.
  Widget _hrLimitCard(BuildContext context) {
    final c = Aigaio.of(context);
    final hr = t.hrLimit;
    final link = WearLink.main;
    final sent = hr != null && link.sentLimit.value == '$hr';
    // Έλεγχος 9/11 (V-A-06): «✓» μόνο όταν το ίδιο το ρολόι πει ότι έχει αυτό το όριο.
    final acked = link.watchLimit.value;
    final (String, Color, IconData)? watch = hr == null
        ? (acked != null && acked != 'null'
            ? ('Το ρολόι έχει ακόμα όριο $acked: άνοιξε την εφαρμογή στο ρολόι για να το σβήσει.', c.exercise, Icons.watch_rounded)
            : null)
        : acked == '$hr'
            ? ('Στο ρολόι ✓ όριο $hr', c.good, Icons.watch_rounded)
            : sent
                ? ('Στάλθηκε· θα επιβεβαιωθεί μόλις ανοίξεις την εφαρμογή στο ρολόι (ή την ενημερώσεις εκεί).', c.textSecondary, Icons.watch_rounded)
                : link.ready.value
                    ? ('Στέλνεται στο ρολόι…', c.textSecondary, Icons.watch_rounded)
                    : ('Το ρολόι δεν βρέθηκε τώρα: δεν ξέρω αν έχει αυτό το όριο.', c.warn, Icons.watch_rounded);
    return AppCard(
      key: const ValueKey('train-hrlimit'),
      onTap: () => _editHrLimit(context),
      child: Row(children: [
        IconBadge(Icons.favorite_rounded, c.heart),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Όριο παλμών από τον γιατρό', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
            Text(hr != null ? '$hr bpm · δόνηση στο ρολόι όσο μετρά άσκηση' : 'Κανένα. Πάτα αν σου δώσει ο γιατρός.',
                style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
            if (watch != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(key: const ValueKey('train-hr-watch'), crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 1), child: Icon(watch.$3, size: 15, color: watch.$2)),
                  const SizedBox(width: 4),
                  Expanded(child: Text(watch.$1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: watch.$2))),
                ]),
              ),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: c.textTertiary),
      ]),
    );
  }

  // ---------------------------------------------------------------- ενέργειες
  Future<void> _editHrLimit(BuildContext context) async {
    final r = await showModalBottomSheet<_HrChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _HrLimitSheet(current: t.hrLimit),
    );
    if (r != null) t.setHrLimit(r.hr);
  }

  Future<void> _start(BuildContext context, Workout w) async {
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
    final time = clock(sec);
    String pace() => m < 50 || sec <= 0 ? '—' : paceText(sec / (m / 1000));

    Widget stat(String v, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.text)),
            Text(label, style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
          ]),
        );
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            l['rec'] == true
                ? 'ΠΕΡΠΑΤΗΜΑ · ΛΕΠΤΟ ΑΠΟΚΑΤΑΣΤΑΣΗΣ'
                : l['paused'] == true
                    ? 'ΠΕΡΠΑΤΗΜΑ ΣΤΟ ΡΟΛΟΪ · ΣΕ ΠΑΥΣΗ'
                    : 'ΠΕΡΠΑΤΗΜΑ ΣΤΟ ΡΟΛΟΪ · ΖΩΝΤΑΝΑ',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: l['paused'] == true ? c.exercise : c.textSecondary)),
        const SizedBox(height: 8),
        if (bpm > 0) ...[HrBar(bpm: bpm, limit: t.hrLimit), const SizedBox(height: 10)],
        Row(children: [stat(time, 'χρόνος'), stat(m > 0 ? (m / 1000).toStringAsFixed(2).replaceAll('.', ',') : '—', 'km')]),
        const SizedBox(height: 8),
        Row(children: [stat(pace(), 'ρυθμός'), stat(steps > 0 ? thousands(steps) : '—', 'βήματα')]),
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

/// Η σταθερή πρόταση για τα φάρμακα στη φόρμα ορίου (έλεγχος 9/11, V-B-06· ESC 2020, Pelliccia κ.ά., Eur Heart J 2021:
/// οι παλμοί προπόνησης ισχύουν με β-αναστολέα μόνο αν η ικανότητα μετρήθηκε με το φάρμακο).
/// Έλεγχος του #90 (Σ-7): να μη διαβάζεται σαν «σβήσε το όριο του γιατρού»· ρωτάς τον γιατρό, και πάντα και με την κούραση.
const hrLimitBetaBlockerText = 'Αν παίρνεις β-αναστολέα, το όριο ισχύει μόνο αν βγήκε από τεστ κοπώσεως που έγινε με το '
    'φάρμακο· αλλιώς ρώτα τον γιατρό. Και πάντα πήγαινε και με την κούραση: να μπορείς να μιλάς.';

/// «Πότε δεν έρχεται δόνηση» (ⓘ της φόρμας ορίου): τι κάνει το ρολόι και τι το κινητό, χωριστά.
const hrLimitMoreText = 'Το ρολόι δονείται μόνο όσο μετρά άσκηση: περπάτημα ή προπόνηση που ξεκίνησε στο ρολόι, ή «Παλμοί εδώ» '
    'στην προπόνηση του κινητού.\n'
    '• Στο ρολόι: αν δεν μετρά παλμούς (χαλαρό λουρί, λείπει η άδεια παλμών του ρολογιού), δονείται μία φορά για να το '
    'ξέρεις (μία μακριά και δύο σύντομες· τρεις σύντομες αν χάθηκαν στη μέση). Πάνω από το όριο: τρεις μακριές.\n'
    '• Στο κινητό: αν δεν φτάνουν παλμοί (ρολόι μακριά ή χωρίς «Παλμοί εδώ»), το γράφει στην οθόνη της προπόνησης. Αν το '
    'ρολόι δεν μετρά άσκηση, δεν έρχεται καμία δόνηση.\n'
    'Στα βάρη ο καρπός συχνά μετρά λιγότερους παλμούς από τους πραγματικούς.';

/// Τι επέλεξε στο φύλλο ορίου: αριθμός ή κανένα όριο (null).
class _HrChoice {
  const _HrChoice(this.hr);
  final int? hr;
}

/// Όριο παλμών: αριθμός 80–220 (κάτω από 100 ζητά επιβεβαίωση), ή «Χωρίς όριο».
class _HrLimitSheet extends StatefulWidget {
  const _HrLimitSheet({this.current});
  final int? current;

  @override
  State<_HrLimitSheet> createState() => _HrLimitSheetState();
}

class _HrLimitSheetState extends State<_HrLimitSheet> {
  late final _hr = TextEditingController(text: widget.current?.toString() ?? '');
  bool _lowOk = false;
  bool _more = false;

  @override
  void dispose() {
    _hr.dispose();
    super.dispose();
  }

  int? get _value => int.tryParse(_hr.text.trim());

  String? get _error {
    final v = _value;
    if (_hr.text.trim().isEmpty) return null;
    if (v == null || v < 80 || v > 220) return 'Γράψε αριθμό από 80 έως 220';
    return null;
  }

  bool get _valid {
    final v = _value;
    return v != null && v >= 80 && v <= 220 && (v >= 100 || _lowOk);
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final v = _value;
    final askLow = v != null && v >= 80 && v < 100;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Όριο παλμών από τον γιατρό', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
            const SizedBox(height: 6),
            // Έλεγχος 9/11 (V-B-05, V-B-06): όχι απόλυτη υπόσχεση· πρώτα πώς νιώθεις· μία σταθερή πρόταση για β-αναστολέα
            // (ESC 2020, Pelliccia κ.ά.). Οι λεπτομέρειες πίσω από το ⓘ, για να μη γεμίζει το φύλλο.
            Text('Αν σου δώσει αριθμό, γράψ’ τον εδώ. Όσο το ρολόι μετρά άσκηση (βάρη ή περπάτημα), δονείται όταν οι παλμοί '
                'φτάσουν ή ξεπεράσουν τον αριθμό για περίπου 5″.',
                style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary)),
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('train-hr-caution'),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(color: c.tint(c.exercise), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Η δόνηση βοηθά, δεν εγγυάται: πρώτα μετράει πώς νιώθεις. Με πόνο στο στήθος, δύσπνοια ή ζάλη σταματάς, '
                    'ό,τι κι αν δείχνει το ρολόι.',
                    style: TextStyle(fontSize: 14, height: 1.4, color: c.text)),
                const SizedBox(height: 6),
                Text(hrLimitBetaBlockerText, key: const ValueKey('train-hr-beta'), style: TextStyle(fontSize: 14, height: 1.4, color: c.text)),
              ]),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('train-hr-more'),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                onPressed: () => setState(() => _more = !_more),
                icon: Icon(_more ? Icons.expand_less_rounded : Icons.info_outline_rounded, size: 18),
                label: const Text('Πότε δεν έρχεται δόνηση'),
              ),
            ),
            if (_more)
              // Έλεγχος του #90 (M-2): χωριστά τι κάνει το ρολόι και τι το κινητό· ποτέ δόνηση όταν το ρολόι δεν μετρά.
              Text(
                hrLimitMoreText,
                key: const ValueKey('train-hr-more-text'),
                style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary),
              ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('train-hr'),
              controller: _hr,
              autofocus: widget.current == null,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
              onChanged: (_) => setState(() => _lowOk = false),
              decoration: InputDecoration(labelText: 'Όριο παλμών', suffixText: 'bpm', errorText: _error, border: const OutlineInputBorder()),
            ),
            if (askLow)
              CheckboxListTile(
                key: const ValueKey('train-hr-low'),
                contentPadding: EdgeInsets.zero,
                value: _lowOk,
                onChanged: (x) => setState(() => _lowOk = x == true),
                title: Text('Έγραψες $v. Σωστά;', style: TextStyle(fontSize: 14.5, color: c.text)),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('train-hr-save'),
              style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(50)),
              onPressed: !_valid ? null : () => Navigator.of(context).pop(_HrChoice(_value)),
              child: const Text('Αποθήκευση'),
            ),
            if (widget.current != null) ...[
              const SizedBox(height: 6),
              TextButton(
                key: const ValueKey('train-hr-clear'),
                onPressed: () => Navigator.of(context).pop(const _HrChoice(null)),
                child: const Text('Χωρίς όριο'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
