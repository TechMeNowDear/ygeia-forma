import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

/// Μία από τις τρεις μεγάλες κατηγορίες (Υγεία, Διατροφή, Άσκηση): τίτλος στο χρώμα της
/// και καρτέλες από πάνω. Θυμάται σε ποια καρτέλα ήσουν (μέσω του [tab]).
class CategoryPage extends StatelessWidget {
  const CategoryPage({
    super.key,
    required this.title,
    required this.color,
    required this.solid,
    required this.tabs,
    required this.pages,
    required this.tab,
    this.now,
  }) : assert(tabs.length == pages.length);

  final String title;

  /// Χρώμα κειμένου της κατηγορίας και γεμάτο χρώμα για την επιλεγμένη καρτέλα.
  final Color color;
  final Color solid;
  final List<String> tabs;
  final List<Widget> pages;
  final ValueNotifier<int> tab;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tab,
      builder: (context, i, _) {
        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageTitle(title, eyebrow: longDate(now ?? DateTime.now()), eyebrowColor: color),
            if (tabs.length > 1) ...[
              const SizedBox(height: 14),
              // Σχέδια 9/11 (2β): πάντα μία σειρά, ποτέ δύο, ποτέ κομμένη λέξη. Αν δεν χωράνε (π.χ. 2,0× γράμματα),
              // η ίδια σειρά κυλά οριζόντια και η επιλεγμένη μένει ορατή.
              SegmentTabs(tabs: tabs, selected: i, solid: solid, onTap: (k) => tab.value = k),
            ],
          ],
        );
        return PageHeaderScope(
          header: header,
          child: LazyIndexedStack(index: i, children: pages),
        );
      },
    );
  }
}

/// Καρτέλες σε μία σειρά (σχέδια 9/11, 2β): γκρι πλαίσιο 48 dp, η επιλεγμένη γεμάτη στο χρώμα της ενότητας.
/// Κάθε καρτέλα θέλει πλάτος = κείμενο + 12 dp· αν το σύνολο χωρά, μοιράζονται όλο το πλάτος· αλλιώς η σειρά κυλά.
class SegmentTabs extends StatefulWidget {
  const SegmentTabs({super.key, required this.tabs, required this.selected, required this.solid, required this.onTap});
  final List<String> tabs;
  final int selected;
  final Color solid;
  final ValueChanged<int> onTap;

  static const pad = 6.0;

  @override
  State<SegmentTabs> createState() => _SegmentTabsState();
}

class _SegmentTabsState extends State<SegmentTabs> {
  final _scroll = ScrollController();
  List<double> _widths = const [];

  @override
  void didUpdateWidget(SegmentTabs old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _reveal();
  }

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Η επιλεγμένη καρτέλα πάντα ορατή, όταν η σειρά κυλά (μόνο η οριζόντια κύλιση· η σελίδα δεν κουνιέται).
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || widget.selected >= _widths.length) return;
      final start = _widths.take(widget.selected).fold(0.0, (a, b) => a + b);
      final view = _scroll.position.viewportDimension;
      final target = (start - (view - _widths[widget.selected]) / 2).clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.jumpTo(target);
    });
  }

  TextStyle _style(bool selected, Aigaio c) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 15,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        color: selected ? c.onSolid : c.textSecondary,
      );

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, box) {
      final widths = <double>[];
      for (final t in widget.tabs) {
        final tp = TextPainter(
            text: TextSpan(text: t, style: DefaultTextStyle.of(context).style.merge(_style(true, c))),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1)
          ..layout();
        widths.add(tp.width + 2 * SegmentTabs.pad);
        tp.dispose();
      }
      _widths = widths;
      final need = widths.fold(0.0, (a, b) => a + b) + 8;
      final fits = need <= box.maxWidth;
      Widget seg(int k) {
        final sel = k == widget.selected;
        // Round 1 (U1a-21): στόχος αφής 48 dp σε όλο το ύψος της μπάρας (πριν 40, με 4 dp «νεκρά» πάνω και κάτω)· το
        // χάπι μένει 40 dp, ίδια εμφάνιση.
        return Semantics(
          selected: sel,
          button: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('tab-${widget.tabs[k]}'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => widget.onTap(k),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: sel ? widget.solid : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: SegmentTabs.pad, vertical: 6),
                      child: Center(
                        widthFactor: 1,
                        child: Text(widget.tabs[k], maxLines: 1, softWrap: false, style: _style(sel, c)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      final row = fits
          ? Row(children: [
              for (var k = 0; k < widget.tabs.length; k++) Expanded(flex: widths[k].round(), child: seg(k)),
            ])
          : Row(mainAxisSize: MainAxisSize.min, children: [for (var k = 0; k < widget.tabs.length; k++) seg(k)]);
      return Container(
        key: const ValueKey('segment-tabs'),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: c.dark ? c.card : c.hairline, borderRadius: BorderRadius.circular(16)),
        child: fits
            ? row
            : ShaderMask(
                // Σβήσιμο στη δεξιά άκρη: φαίνεται ότι η σειρά συνεχίζει.
                shaderCallback: (r) => const LinearGradient(
                  colors: [Colors.white, Colors.white, Colors.transparent],
                  stops: [0, .88, 1],
                ).createShader(r),
                blendMode: BlendMode.dstIn,
                child: SingleChildScrollView(controller: _scroll, scrollDirection: Axis.horizontal, child: row),
              ),
      );
    });
  }
}

/// Καρτέλα-«χάπι»: γεμάτη στο χρώμα της κατηγορίας όταν είναι επιλεγμένη.
class TabChip extends StatelessWidget {
  const TabChip({super.key, required this.label, required this.selected, required this.solid, required this.onTap});
  final String label;
  final bool selected;
  final Color solid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? solid : c.card,
        shape: StadiumBorder(side: BorderSide(color: selected ? solid : c.hairline)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // Στο πλάτος του κειμένου (μέσα σε Wrap δεν απλώνεται σε όλη τη γραμμή).
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? c.onSolid : c.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
