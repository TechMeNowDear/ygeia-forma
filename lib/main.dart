import 'package:flutter/material.dart';

import 'data.dart';
import 'food/food_store.dart';
import 'pages/body.dart';
import 'pages/food_add.dart';
import 'pages/heart.dart';
import 'pages/nutrition.dart';
import 'pages/settings.dart';
import 'pages/sleep.dart';
import 'pages/today.dart';
import 'pages/trends.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = HealthStore();
  final food = FoodStore();
  runApp(YgeiaFormaApp(store: store, food: food));
  store.start();
  food.start();
}

class YgeiaFormaApp extends StatelessWidget {
  const YgeiaFormaApp({super.key, required this.store, required this.food});
  final HealthStore store;
  final FoodStore food;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Υγεία & Φόρμα',
      debugShowCheckedModeBanner: false,
      // Ανοιχτό ή σκοτεινό, όπως είναι ρυθμισμένο το κινητό.
      themeMode: ThemeMode.system,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: Shell(store: store, food: food),
    );
  }
}

class _Dest {
  const _Dest(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _destinations = [
  _Dest(Icons.wb_sunny_outlined, Icons.wb_sunny, 'Σήμερα'),
  _Dest(Icons.restaurant_outlined, Icons.restaurant, 'Διατροφή'),
  _Dest(Icons.bedtime_outlined, Icons.bedtime, 'Ύπνος'),
  _Dest(Icons.favorite_outline, Icons.favorite, 'Καρδιά'),
  _Dest(Icons.accessibility_new_outlined, Icons.accessibility_new, 'Σώμα'),
];

/// Κέλυφος: κάτω μπάρα στο κινητό (κλειστό Fold), πλευρική σε ανοιχτό Fold και tablet.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.store, this.food, this.initialIndex = 0, this.now});
  final HealthStore store;

  /// Αν λείπει (δοκιμές), φτιάχνεται άδειο.
  final FoodStore? food;
  final int initialIndex;

  /// Μόνο για τα στιγμιότυπα δοκιμών.
  final DateTime? now;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late int _index = widget.initialIndex;
  late final FoodStore _food = widget.food ?? FoodStore.preloaded(foods: const []);

  void _go(int i) => setState(() => _index = i);

  void _openTrends() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: Aigaio.of(context).background,
          appBar: AppBar(
            backgroundColor: Aigaio.of(context).background,
            surfaceTintColor: Colors.transparent,
          ),
          body: TrendsPage(store: widget.store, now: widget.now),
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SettingsPage(store: widget.store)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final store = widget.store;
    final pages = <Widget>[
      TodayPage(store: store, openTab: _go, openSettings: _openSettings, openTrends: _openTrends, now: widget.now),
      NutritionPage(food: _food, now: widget.now),
      SleepPage(store: store),
      HeartPage(store: store),
      BodyPage(store: store),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        final content = IndexedStack(index: _index, children: pages);
        // Ένα κουμπί «+» πάντα στην ίδια θέση (έγγραφο › Καταχώριση), στη Διατροφή.
        final fab = _index == 1
            ? FloatingActionButton.extended(
                onPressed: () => openAddFood(context, _food),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Φαγητό'),
                backgroundColor: c.primary,
                foregroundColor: c.onPrimary,
              )
            : null;

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  right: false,
                  child: NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _go,
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: c.background,
                    indicatorColor: c.primary.withValues(alpha: 0.18),
                    minWidth: 88,
                    groupAlignment: -0.8,
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon, color: c.primary),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                ),
                Expanded(child: content),
              ],
            ),
            floatingActionButton: fab,
          );
        }

        return Scaffold(
          extendBody: true,
          body: content,
          floatingActionButton: fab,
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: NavigationBarTheme(
                data: NavigationBarThemeData(
                  backgroundColor: c.nav,
                  indicatorColor: c.primary,
                  height: 68,
                  labelTextStyle: WidgetStateProperty.resolveWith(
                    (states) => TextStyle(
                      color: states.contains(WidgetState.selected) ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  iconTheme: WidgetStateProperty.resolveWith(
                    (states) => IconThemeData(
                      color: states.contains(WidgetState.selected) ? c.onPrimary : Colors.white70,
                    ),
                  ),
                ),
                child: MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: _go,
                    destinations: [
                      for (final d in _destinations)
                        NavigationDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: d.label,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
