import 'package:flutter/material.dart';

import '../data.dart';
import '../theme.dart';
import '../widgets.dart';

/// Ρυθμίσεις › Εμφάνιση: φωτεινότητα, θέμα για τη μέρα και θέμα για τη νύχτα.
/// Η επιλογή εφαρμόζεται αμέσως· το «Δείγμα» δείχνει το θέμα που πάτησα τελευταίο,
/// ακόμα κι αν δεν είναι αυτό που φαίνεται τώρα (π.χ. το νυχτερινό μέσα στη μέρα).
class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key, required this.store});
  final HealthStore store;

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  Aigaio? _preview;

  void _pickDay(Aigaio t) {
    final p = widget.store.prefs;
    widget.store.setAppearance(day: t.id, mode: p.themeMode == 'dark' ? 'light' : null);
    setState(() => _preview = t);
  }

  void _pickNight(Aigaio t) {
    final p = widget.store.prefs;
    widget.store.setAppearance(night: t.id, mode: p.themeMode == 'light' ? 'dark' : null);
    setState(() => _preview = t);
  }

  void _pickMode(String mode) {
    final p = widget.store.prefs;
    widget.store.setAppearance(mode: mode);
    setState(() => _preview = switch (mode) {
          'light' => Aigaio.day(p.dayTheme),
          'dark' => Aigaio.night(p.nightTheme),
          _ => null,
        });
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Εμφάνιση')),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final p = widget.store.prefs;
          final day = Aigaio.day(p.dayTheme);
          final night = Aigaio.night(p.nightTheme);
          final preview = _preview ?? c;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SectionLabel('Φωτεινότητα'),
                            const SizedBox(height: 10),
                            _ModeSwitch(value: p.themeMode, onChanged: _pickMode),
                            const SizedBox(height: 10),
                            Text(
                              switch (p.themeMode) {
                                'light' => 'Πάντα το φωτεινό θέμα που διάλεξες.',
                                'dark' => 'Πάντα το σκοτεινό θέμα που διάλεξες.',
                                _ => 'Ακολουθεί το κινητό: φωτεινό τη μέρα, σκοτεινό τη νύχτα.',
                              },
                              style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _ThemeGroup(
                        title: 'Τη μέρα',
                        hint: 'φωτεινά',
                        icon: Icons.wb_sunny_rounded,
                        themes: Aigaio.dayThemes,
                        selected: day,
                        dimmed: p.themeMode == 'dark',
                        onPick: _pickDay,
                      ),
                      const SizedBox(height: 20),
                      _ThemeGroup(
                        title: 'Τη νύχτα',
                        hint: 'σκοτεινά',
                        icon: Icons.bedtime_rounded,
                        themes: Aigaio.nightThemes,
                        selected: night,
                        dimmed: p.themeMode == 'light',
                        onPick: _pickNight,
                      ),
                      const SizedBox(height: 20),
                      _Sample(palette: preview),
                      const SizedBox(height: 16),
                      Text(
                        'Ισχύει σε αυτή τη συσκευή. Αλλάζουν μόνο τα χρώματα.',
                        textAlign: TextAlign.center,
                        // Round 1 (U4-14 δ): ίδιο μέγεθος με κάθε γκρι εξήγηση κάτω από ρύθμιση.
                        style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Αυτόματο · Φωτεινό · Σκοτεινό.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  // R7-U4-14 η: «Φωτεινό», όπως «φωτεινό θέμα»/«φωτεινά» στην ίδια οθόνη (πριν «Ανοιχτό»).
  static const _options = [('auto', 'Αυτόματο'), ('light', 'Φωτεινό'), ('dark', 'Σκοτεινό')];

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Container(
      // R7-U4-10: κάθε επιλογή 48 dp ψηλή (πριν 44)· ίδιο συνολικό ύψος (52).
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: c.background,
        // Round 1 (U4-14 θ): ίδιες γωνίες με τους άλλους επιλογείς (16 έξω, 12 μέσα).
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        children: [
          for (final (key, label) in _options)
            Expanded(
              child: Semantics(
                button: true,
                selected: key == value,
                excludeSemantics: true,
                label: label,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: key == value ? c.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: key == value ? FontWeight.w700 : FontWeight.w600,
                        color: key == value ? c.onPrimary : c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Τρία θέματα δίπλα δίπλα, με τίτλο από πάνω.
class _ThemeGroup extends StatelessWidget {
  const _ThemeGroup({
    required this.title,
    required this.hint,
    required this.icon,
    required this.themes,
    required this.selected,
    required this.dimmed,
    required this.onPick,
  });
  final String title;
  final String hint;
  final IconData icon;
  final List<Aigaio> themes;
  final Aigaio selected;

  /// Όταν η φωτεινότητα είναι κλειδωμένη στο άλλο: οι μικρές εικόνες φαίνονται πιο σβηστές, αλλά πατιούνται.
  /// Round 1 (U4-11): σβηστή ΜΟΝΟ η εικόνα· τα γράμματα (τίτλος, όνομα, χαρακτήρας) μένουν πλήρη, αλλιώς έπεφταν στο
  /// 1,9–4,2:1 και αυτό δεν επιτρέπεται για κάτι που πατιέται.
  final bool dimmed;
  final ValueChanged<Aigaio> onPick;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(icon, size: 19, color: c.text),
                const SizedBox(width: 8),
                Expanded(
                  // Round 1 (U4-14 γ): ίδιος τίτλος με το [SectionLabel].
                  child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
                ),
                Text(hint, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, t) in themes.indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                    child: _ThemeTile(palette: t, selected: identical(t, selected), dimmed: dimmed, onTap: () => onPick(t))),
              ],
            ],
          ),
        ],
    );
  }
}

/// Ένα θέμα: μικρή εικόνα της οθόνης «Σήμερα» με τα χρώματά του, όνομα και χαρακτήρας.
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.palette, required this.selected, required this.onTap, this.dimmed = false});
  final Aigaio palette;
  final bool selected;
  final VoidCallback onTap;

  /// Σβηστή μόνο η μικρή εικόνα (δες [_ThemeGroup.dimmed]).
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final x = palette;
    Widget box({required double height, required Widget child}) => Container(
          height: height,
          padding: const EdgeInsets.all(5),
          alignment: Alignment.bottomLeft,
          decoration: BoxDecoration(
            color: x.card,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: x.hairline),
          ),
          child: child,
        );
    Widget bar(Color color, double widthFactor, [double h = 5]) => FractionallySizedBox(
          widthFactor: widthFactor,
          child: Container(height: h, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        );

    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: '${x.name}, ${x.dark ? 'σκοτεινό' : 'φωτεινό'} θέμα',
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? c.primary : c.hairline, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: dimmed ? 0.45 : 1,
                      child: Container(
                      height: 136,
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: x.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: x.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            height: 38,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [x.nightTop, x.nightBottom],
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Expanded(child: box(height: 26, child: bar(x.exercise, 0.7))),
                              const SizedBox(width: 5),
                              Expanded(child: box(height: 26, child: bar(x.body, 0.55))),
                            ],
                          ),
                          const SizedBox(height: 5),
                          box(height: 22, child: bar(x.foodSolid, 1, 7)),
                          const Spacer(),
                          Container(
                            height: 16,
                            padding: const EdgeInsets.only(left: 5),
                            alignment: Alignment.centerLeft,
                            decoration: BoxDecoration(
                              color: x.nav,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: x.navBorder),
                            ),
                            child: Container(
                              width: 16,
                              height: 8,
                              decoration: BoxDecoration(color: x.todayPill, borderRadius: BorderRadius.circular(4)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ),
                    if (selected)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: c.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.card, width: 2),
                          ),
                          child: Icon(Icons.check_rounded, size: 15, color: c.onPrimary),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(x.name, maxLines: 1, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(
                        x.mood,
                        maxLines: 1,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Μικρό δείγμα με τα χρώματα ενός θέματος: κάρτα ύπνου, κάρτες και κουμπί.
class _Sample extends StatelessWidget {
  const _Sample({required this.palette});
  final Aigaio palette;

  @override
  Widget build(BuildContext context) {
    final x = palette;
    final soft = Colors.white.withValues(alpha: 0.8);
    // Round 1 (U4-3): γράμματα στο χρώμα του κειμένου πάνω στο απαλό χρώμα (το χρώμα σε δικό του απαλό φόντο έπεφτε
    // στο 4,0–4,4:1 σε Αιγαίο, Ελιά, Αυγή)· το χρώμα του θέματος φαίνεται στο «χάπι».
    Widget chip(String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: x.tint(color), borderRadius: BorderRadius.circular(999)),
          child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: x.text)),
        );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: x.background,
        borderRadius: BorderRadius.circular(AppCard.radius),
        border: Border.all(color: x.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ΔΕΙΓΜΑ',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .6, color: x.textSecondary),
                ),
              ),
              Text(
                '${x.name} · ${x.dark ? 'σκοτεινό' : 'φωτεινό'}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: x.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [x.nightTop, x.nightBottom],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.bedtime_rounded, size: 16, color: soft),
                          const SizedBox(width: 6),
                          Text('Ύπνος', style: TextStyle(color: soft, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(text: '7', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                          TextSpan(text: ' ώρες ', style: TextStyle(fontSize: 14, color: soft)),
                          const TextSpan(text: '20', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                          TextSpan(text: ' λεπτά', style: TextStyle(fontSize: 14, color: soft)),
                        ]),
                        style: const TextStyle(color: Colors.white, fontFeatures: tabular),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 46,
                  height: 46,
                  child: CircularProgressIndicator(
                    value: 0.78,
                    strokeWidth: 5,
                    strokeCap: StrokeCap.round,
                    color: x.ring,
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip('Βήματα', x.move),
              chip('Βάρος', x.body),
              chip('Πρωτεΐνη', x.sleep),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: x.foodSolid, borderRadius: BorderRadius.circular(14)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 20, color: x.onSolid),
                const SizedBox(width: 6),
                Text('Φαγητό', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: x.onSolid)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
