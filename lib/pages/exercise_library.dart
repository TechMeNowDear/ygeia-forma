import 'package:flutter/material.dart';

import '../exercise/ex_data.dart';
import '../exercise/ex_player.dart';
import '../food/food_search.dart' show plain, phonetic;
import '../theme.dart';
import '../widgets.dart';
import 'category.dart' show TabChip;
import 'exercise_detail.dart';

/// Άσκηση › Ασκήσεις: όλες οι ασκήσεις με τον εξοπλισμό του μπαλκονιού, με αναζήτηση και ομάδες.
class ExerciseLibraryPage extends StatefulWidget {
  const ExerciseLibraryPage({super.key});

  @override
  State<ExerciseLibraryPage> createState() => _ExerciseLibraryPageState();
}

class _ExerciseLibraryPageState extends State<ExerciseLibraryPage> {
  final _query = TextEditingController();
  String? _group;
  late final Future<ExLibrary> _lib = ExLibrary.load();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _matches(Ex e, String q) {
    if (q.isEmpty) return true;
    final hay = [e.name, e.en, e.equip, e.groupName, for (final m in [...e.primary, ...e.secondary]) m.name].join(' ');
    final p = plain(q.trim());
    if (plain(hay).contains(p)) return true;
    return phonetic(hay).contains(phonetic(q.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ExLibrary.loaded;
    if (loaded != null) return _page(context, loaded);
    return FutureBuilder<ExLibrary>(
      future: _lib,
      builder: (context, snap) {
        if (snap.hasData) return _page(context, snap.data!);
        return PageFrame(
          title: 'Ασκήσεις',
          onRefresh: () async {},
          left: [
            if (snap.hasError)
              EmptyCard(icon: Icons.error_outline_rounded, color: Aigaio.of(context).bad, title: 'Δεν φόρτωσαν οι ασκήσεις', text: 'Κλείσε και άνοιξε ξανά την εφαρμογή.')
            else
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          ],
        );
      },
    );
  }

  Widget _page(BuildContext context, ExLibrary lib) {
    final c = Aigaio.of(context);
    final q = _query.text;
    final shown = [for (final e in lib.list) if ((_group == null || e.group == _group) && _matches(e, q)) e];
    final sections = <Widget>[];
    for (final g in exGroups.keys) {
      final list = [for (final e in shown) if (e.group == g) e];
      if (list.isEmpty) continue;
      sections.add(_Section(title: '${exGroups[g]} · ${list.length}', list: list, lib: lib));
    }
    final search = TextField(
      key: const ValueKey('ex-search'),
      controller: _query,
      onChanged: (_) => setState(() {}),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Αναζήτηση: π.χ. στήθος, αλτήρες, κοιλιακοί',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: q.isEmpty
            ? null
            : IconButton(
                tooltip: 'Καθάρισμα',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(_query.clear),
              ),
        filled: true,
        fillColor: c.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.hairline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.hairline)),
      ),
    );
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(children: [
        TabChip(label: 'Όλες', selected: _group == null, solid: c.exerciseSolid, onTap: () => setState(() => _group = null)),
        for (final g in exGroups.entries) ...[
          const SizedBox(width: 8),
          TabChip(
            key: ValueKey('ex-group-${g.key}'),
            label: g.value,
            selected: _group == g.key,
            solid: c.exerciseSolid,
            onTap: () => setState(() => _group = _group == g.key ? null : g.key),
          ),
        ],
      ]),
    );
    final note = Text(
      'Κάθε άσκηση με τον εξοπλισμό σου, σε κίνηση. Τα κιλά και το πρόγραμμα είναι στην «Προπόνηση».',
      style: TextStyle(fontSize: 13.5, color: c.textSecondary, height: 1.35),
    );
    final empty = EmptyCard(
      icon: Icons.search_off_rounded,
      color: c.exercise,
      title: 'Καμία άσκηση',
      text: 'Δοκίμασε άλλη λέξη, π.χ. «πλάτη» ή «λάστιχο».',
    );
    final half = (sections.length / 2).ceil();
    return PageFrame(
      title: 'Ασκήσεις',
      onRefresh: () async {},
      top: [search, chips],
      single: [search, chips, note, if (sections.isEmpty) empty, ...sections],
      left: [note, if (sections.isEmpty) empty, ...sections.take(half)],
      right: sections.length > 1 ? sections.skip(half).toList() : const [],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.list, required this.lib});
  final String title;
  final List<Ex> list;
  final ExLibrary lib;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title),
        const SizedBox(height: 8),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 88, color: c.hairline),
                _Row(ex: list[i], lib: lib),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.ex, required this.lib});
  final Ex ex;
  final ExLibrary lib;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return InkWell(
      key: ValueKey('ex-row-${ex.id}'),
      onTap: () => Navigator.of(context).push(ExerciseDetailPage.route(ex, lib)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            ExThumb(ex: ex),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ex.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text, height: 1.25)),
                  const SizedBox(height: 2),
                  Text(
                    '${ex.equip} · ${ex.primary.map((m) => m.name.toLowerCase()).join(', ')}',
                    style: TextStyle(fontSize: 13.5, color: c.textSecondary, height: 1.3),
                  ),
                  if (ex.caution != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: c.exercise),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text('Σταδιακά, χωρίς πόνο', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.exercise)),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}
