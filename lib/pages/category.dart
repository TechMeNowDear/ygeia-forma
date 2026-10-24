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
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(
                  children: [
                    for (var k = 0; k < tabs.length; k++) ...[
                      if (k > 0) const SizedBox(width: 8),
                      TabChip(
                        key: ValueKey('tab-${tabs[k]}'),
                        label: tabs[k],
                        selected: k == i,
                        solid: solid,
                        onTap: () => tab.value = k,
                      ),
                    ],
                  ],
                ),
              ),
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
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? Colors.white : c.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
