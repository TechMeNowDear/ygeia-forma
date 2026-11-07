import 'package:flutter/material.dart';

import '../exercise/ex_data.dart';
import '../exercise/ex_player.dart';
import '../theme.dart';
import '../widgets.dart';

/// Οι μελέτες που αναφέρονται στις συμβουλές, για τη γραμμή «Πηγές».
const _studies = {
  'Kikuchi & Nakazato 2017': 'Kikuchi N, Nakazato K. J Exerc Sci Fit 2017;15(1):37–42',
  'Pedrosa 2023': 'Pedrosa GF et al. Sports (Basel) 2023;11(2):39',
  'Maeo 2023': 'Maeo S et al. Eur J Sport Sci 2023;23(7):1240–1250',
  'Escamilla 2006': 'Escamilla RF et al. Phys Ther 2006;86(5):656–671',
  'Fry 2003': 'Fry AC et al. J Strength Cond Res 2003;17(4):629–633',
};

/// Μία άσκηση: κινούμενη εικόνα, σημεία προσοχής τη σωστή στιγμή, μύες, στήσιμο, λάθη, συμβουλές.
class ExerciseDetailPage extends StatefulWidget {
  const ExerciseDetailPage({super.key, required this.ex, required this.lib});
  final Ex ex;
  final ExLibrary lib;

  static Route<void> route(Ex ex, ExLibrary lib) =>
      MaterialPageRoute<void>(builder: (_) => ExerciseDetailPage(ex: ex, lib: lib));

  @override
  State<ExerciseDetailPage> createState() => _ExerciseDetailPageState();
}

class _ExerciseDetailPageState extends State<ExerciseDetailPage> {
  final _phase = ValueNotifier<int>(0);

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.ex;
    final c = Aigaio.of(context);
    final colors = exColorsOf(context);

    final caution = ex.caution == null
        ? null
        : Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.tint(c.exercise),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_rounded, color: c.exercise),
              const SizedBox(width: 10),
              Expanded(child: Text(ex.caution!, style: TextStyle(fontSize: 14.5, height: 1.4, color: c.text))),
            ]),
          );

    final player = AppCard(padding: const EdgeInsets.all(12), child: ExPlayer(ex: ex, phase: _phase));

    final cues = AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title('Πρόσεξε τώρα'),
          const SizedBox(height: 8),
          ValueListenableBuilder<int>(
            valueListenable: _phase,
            builder: (context, ph, _) => Column(
              children: [
                for (var i = 0; i < ex.cues.length; i++)
                  _Cue(n: i + 1, text: ex.cues[i].text, on: ex.cues[i].phases.contains(ph)),
              ],
            ),
          ),
        ],
      ),
    );

    Widget muscleRow(ExMuscle m, Color col) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              margin: const EdgeInsets.only(top: 3),
              width: 16,
              height: 16,
              decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(5)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                if (m.note.isNotEmpty) Text(m.note, style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
              ]),
            ),
          ]),
        );

    final muscles = AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Title('Τι γυμνάζει'),
          const SizedBox(height: 6),
          _Small('Κύριοι'),
          for (final m in ex.primary) muscleRow(m, colors.primary),
          if (ex.secondary.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Small('Βοηθητικοί'),
            for (final m in ex.secondary) muscleRow(m, colors.secondary),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.tint(c.exercise), borderRadius: BorderRadius.circular(12)),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Πού το νιώθεις: ', style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                TextSpan(text: ex.feel),
              ]),
              style: TextStyle(fontSize: 14.5, height: 1.4, color: c.text),
            ),
          ),
        ],
      ),
    );

    Widget listCard(String title, List<String> items, {IconData? icon, Color? iconColor, bool numbered = false}) => AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Title(title),
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 26,
                      child: numbered
                          ? Text('${i + 1}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.exercise))
                          : Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(icon, size: 18, color: iconColor ?? c.textSecondary),
                            ),
                    ),
                    Expanded(child: Text(items[i], style: TextStyle(fontSize: 15, height: 1.42, color: c.text))),
                  ]),
                ),
            ],
          ),
        );

    final setup = listCard('Στήσιμο', ex.setup, numbered: true);
    final steps = listCard('Πώς γίνεται', ex.steps, numbered: true);
    final mistakes = listCard('Συχνά λάθη', ex.mistakes, icon: Icons.close_rounded, iconColor: c.bad);
    final tips = listCard('Συμβουλές', ex.tips, icon: Icons.check_rounded, iconColor: c.good);

    final alts = [for (final id in ex.alt) widget.lib.byId(id)].whereType<Ex>().toList();
    final alt = alts.isEmpty
        ? null
        : AppCard(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Title('Αντί γι’ αυτή'),
                for (final a in alts)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.of(context).pushReplacement(ExerciseDetailPage.route(a, widget.lib)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        ExThumb(ex: a, size: 48),
                        const SizedBox(width: 12),
                        Expanded(child: Text(a.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text))),
                        Icon(Icons.chevron_right_rounded, color: c.textTertiary),
                      ]),
                    ),
                  ),
              ],
            ),
          );

    final cited = [for (final e in _studies.entries) if (ex.tips.any((t) => t.contains(e.key))) e.value];
    final sources = Text(
      [
        'Η κίνηση είναι υπολογισμένη για ύψος 177 cm. Ο εξοπλισμός είναι σχηματικός· το στήσιμο του δικού σου είναι στο «Στήσιμο».',
        'Τεχνική: NSCA, Essentials of Strength Training and Conditioning, 4η έκδ.',
        if (cited.isNotEmpty) 'Μελέτες: ${cited.join('; ')}.',
      ].join('\n'),
      style: TextStyle(fontSize: 12.5, height: 1.45, color: c.textSecondary),
    );

    final leftCol = [if (caution != null) caution, player, cues];
    final rightCol = [muscles, setup, steps, mistakes, tips, if (alt != null) alt, sources];

    return Scaffold(
      appBar: AppBar(
        title: Text(ex.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${ex.groupName} · ${ex.equip}', style: TextStyle(fontSize: 14, color: c.textSecondary)),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, k) {
          const gap = SizedBox(height: 12);
          List<Widget> spaced(List<Widget> l) => [for (var i = 0; i < l.length; i++) ...[if (i > 0) gap, l[i]]];
          if (k.maxWidth < 720) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: spaced([...leftCol, ...rightCol]),
            );
          }
          // Μεγάλη οθόνη: αριστερά η κίνηση (μένει στη θέση της), δεξιά τα κείμενα.
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 11,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 8, 32),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(leftCol)),
                    ),
                  ),
                  Expanded(
                    flex: 10,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(8, 4, 20, 32),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: spaced(rightCol)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Text(text, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -0.2));
  }
}

class _Small extends StatelessWidget {
  const _Small(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary));
  }
}

class _Cue extends StatelessWidget {
  const _Cue({required this.n, required this.text, required this.on});
  final int n;
  final String text;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return AnimatedContainer(
      duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: on ? c.tint(c.exercise) : null,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: on ? c.exercise : c.hairline),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 22,
          child: Text('$n', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.exercise)),
        ),
        Expanded(child: Text(text, style: TextStyle(fontSize: 15, height: 1.4, color: c.text))),
      ]),
    );
  }
}
