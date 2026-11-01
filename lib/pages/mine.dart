import 'package:flutter/material.dart';

import '../data.dart';
import '../food/food_store.dart';
import '../food/kitchen.dart';
import '../theme.dart';
import '../widgets.dart';
import 'kitchen.dart';
import 'my_foods.dart';

/// Διατροφή › «Τα δικά μου»: τα προϊόντα που έχω περάσει και η κουζίνα μου.
class MinePage extends StatelessWidget {
  const MinePage({super.key, required this.food, required this.store});
  final FoodStore food;
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([food, store]),
      builder: (context, _) {
        final c = Aigaio.of(context);
        final n = food.mine.length;
        final k = Kitchen.fromJson(store.prefs.kitchen);

        final products = _EntryCard(
          key: const ValueKey('mine-products'),
          icon: Icons.inventory_2_outlined,
          color: c.food,
          title: 'Τα προϊόντα μου',
          text: n == 0
              ? 'Πέρασε ό,τι αγοράζεις, με barcode ή χειροκίνητα, χωρίς να το φας.'
              : '${n == 1 ? '1 προϊόν' : '$n προϊόντα'} · πρόσθεσε κι άλλα με barcode ή χειροκίνητα',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(settings: const RouteSettings(name: 'Τα προϊόντα μου'), builder: (_) => MyFoodsScreen(food: food))),
        );
        final kitchen = _EntryCard(
          key: const ValueKey('mine-kitchen'),
          icon: Icons.soup_kitchen_outlined,
          color: c.food,
          title: 'Η κουζίνα μου',
          text: '${k.devices.length} συσκευές · ${k.cookware.length} σκεύη',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(settings: const RouteSettings(name: 'Η κουζίνα μου'), builder: (_) => KitchenScreen(store: store))),
        );

        return PageFrame(
          title: 'Τα δικά μου',
          onRefresh: () async {},
          single: [products, kitchen],
          left: [products],
          right: [kitchen],
        );
      },
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          IconBadge(icon, color, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
                const SizedBox(height: 3),
                Text(text, style: TextStyle(fontSize: 14, height: 1.35, color: c.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.textTertiary),
        ],
      ),
    );
  }
}
