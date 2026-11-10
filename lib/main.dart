import 'package:flutter/material.dart';

import 'data.dart';
import 'error_report.dart';
import 'food/food_store.dart';
import 'home_widgets/widget_bridge.dart';
import 'nav.dart';
import 'pages/privacy_page.dart' show registerLicenses;
import 'pages/exercise_library.dart';
import 'pages/training/training_page.dart';
import 'heart_day.dart' show appExerciseRanges;
import 'training/training_store.dart';
import 'training/wear_link.dart';
import 'pages/body.dart';
import 'pages/category.dart';
import 'pages/food_add.dart';
import 'pages/heart.dart';
import 'pages/metric_page.dart';
import 'pages/mine.dart';
import 'pages/move.dart';
import 'pages/nutrition.dart';
import 'pages/recovery.dart';
import 'pages/settings.dart';
import 'pages/sleep.dart';
import 'pages/today.dart';
import 'pages/trends.dart';
import 'pages/widget_config_page.dart';
import 'theme.dart';
import 'widgets.dart';

export 'nav.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  installErrorReporting();
  registerLicenses();
  // Η οθόνη ρύθμισης widget (WidgetConfigActivity): μόνη της, χωρίς φόρτωση δεδομένων.
  if (binding.platformDispatcher.defaultRouteName.startsWith('/widget')) {
    runApp(const WidgetConfigApp());
    return;
  }
  final store = HealthStore();
  final food = FoodStore();
  // Πρώτα οι ρυθμίσεις (λίγα ms), ώστε η πρώτη οθόνη να έχει ήδη το θέμα που διάλεξα.
  await store.loadPrefs();
  runApp(YgeiaFormaApp(store: store, food: food));
  store.start();
  food.start();
  WidgetPublisher(store, food).start();
  // Ρολόι (8/11): μόλις φορτωθεί η προπόνηση, πρόγραμμα προς το ρολόι και ό,τι έγινε εκεί προς το κινητό.
  TrainingStore.main.load().then((_) => WearLink.main.start(TrainingStore.main));
  // Έλεγχος 9/11 (DP-07): οι προπονήσεις της εφαρμογής δεν μετρούν στους παλμούς της μέρας και στην ηρεμία.
  appExerciseRanges = () => [
        for (final s in [...TrainingStore.main.sessions, if (TrainingStore.main.current case final c?) c])
          (s.start, (s.end ?? DateTime.now()).add(const Duration(minutes: 5))),
      ];
}

class YgeiaFormaApp extends StatefulWidget {
  const YgeiaFormaApp({super.key, required this.store, required this.food});
  final HealthStore store;
  final FoodStore food;

  @override
  State<YgeiaFormaApp> createState() => _YgeiaFormaAppState();
}

class _YgeiaFormaAppState extends State<YgeiaFormaApp> {
  // Ίδιο αντικείμενο σε κάθε αλλαγή θέματος: αλλάζουν μόνο τα χρώματα, όχι η κατάσταση.
  late final Widget _home = Shell(store: widget.store, food: widget.food);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final p = widget.store.prefs;
        return MaterialApp(
          title: 'Υγεία & Φόρμα',
          debugShowCheckedModeBanner: false,
          // «Αυτόματο»: ανοιχτό ή σκοτεινό όπως το κινητό, με το θέμα που διάλεξα για τη μέρα και τη νύχτα.
          themeMode: switch (p.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          theme: buildTheme(Brightness.light, Aigaio.day(p.dayTheme)),
          darkTheme: buildTheme(Brightness.dark, Aigaio.night(p.nightTheme)),
          themeAnimationDuration: const Duration(milliseconds: 220),
          navigatorObservers: [errors.observer],
          home: _home,
          // Έλεγχος 9/11 (E3-08, Sentry YGEIA-FORMA-3): μια άγνωστη διαδρομή (π.χ. URI από άλλη εφαρμογή) δεν ρίχνει
          // ποτέ την εφαρμογή· μένει στην αρχική. Μαζί με το flutter_deeplinking_enabled=false στο manifest.
          onUnknownRoute: unknownRoute,
        );
      },
    );
  }
}

/// Άγνωστη διαδρομή → τίποτα καινούργιο: μια σελίδα που κλείνει αμέσως και αφήνει την οθόνη όπως ήταν.
Route<void> unknownRoute(RouteSettings settings) => PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'άγνωστη διαδρομή'),
      opaque: false,
      pageBuilder: (context, _, __) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).maybePop();
        });
        return const SizedBox.shrink();
      },
    );

class _Dest {
  const _Dest(this.icon, this.selectedIcon, this.label, this.cat);
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Η κατηγορία ([Cat]): δίνει το χρώμα του «χαπιού» όταν είναι επιλεγμένο.
  final int cat;

  /// Χρώμα και εικονίδιο του «χαπιού» στο θέμα [c].
  (Color, Color) pill(Aigaio c) => switch (cat) {
        Cat.health => (c.healthSolid, c.onSolid),
        Cat.food => (c.foodSolid, c.onSolid),
        Cat.exercise => (c.exerciseSolid, c.onSolid),
        _ => (c.todayPill, c.todayPillInk),
      };
}

const _destinations = [
  _Dest(Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, 'Σήμερα', Cat.today),
  _Dest(Icons.favorite_outline_rounded, Icons.favorite_rounded, 'Υγεία', Cat.health),
  _Dest(Icons.restaurant_outlined, Icons.restaurant_rounded, 'Διατροφή', Cat.food),
  _Dest(Icons.fitness_center_outlined, Icons.fitness_center_rounded, 'Άσκηση', Cat.exercise),
];

/// Κέλυφος: σταθερή κάτω μπάρα στο κινητό (κλειστό Fold), κάθετη μπάρα σε ανοιχτό Fold, tablet, PC.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.store, this.food, this.initialIndex = 0, this.initialTab = 0, this.now});
  final HealthStore store;

  /// Αν λείπει (δοκιμές), φτιάχνεται άδειο.
  final FoodStore? food;

  /// Κατηγορία ([Cat]) και καρτέλα μέσα της, για το πρώτο άνοιγμα (και τα στιγμιότυπα).
  final int initialIndex;
  final int initialTab;

  /// Μόνο για τα στιγμιότυπα δοκιμών.
  final DateTime? now;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late int _index = widget.initialIndex;
  late final FoodStore _food = widget.food ?? FoodStore.preloaded(foods: const []);
  late final _healthTab = ValueNotifier(widget.initialIndex == Cat.health ? widget.initialTab : 0);
  late final _foodTab = ValueNotifier(widget.initialIndex == Cat.food ? widget.initialTab : 0);
  late final _exerciseTab = ValueNotifier(widget.initialIndex == Cat.exercise ? widget.initialTab : 0);

  // Για την αναφορά σφαλμάτων: σε ποια κατηγορία και καρτέλα είμαι.
  static const _catNames = ['Σήμερα', 'Υγεία', 'Διατροφή', 'Άσκηση'];
  static const _healthTabs = ['Ύπνος', 'Ανάκαμψη', 'Καρδιά', 'Σώμα', 'Τάσεις'];
  static const _foodTabs = ['Ημερολόγιο', 'Τα δικά μου'];
  static const _exerciseTabs = ['Προπόνηση', 'Κίνηση', 'Ασκήσεις'];

  /// Πάτημα σε widget της αρχικής οθόνης: «w:<είδος>:<πάτημα>:<κεντρική τιμή>» (HomeWidgets.kt).
  void _fromWidget() {
    final req = widgetOpenRequest.value;
    if (req == null) return;
    widgetOpenRequest.value = null;
    final p = req.split(':');
    if (p.length < 3 || p[0] != 'w') return;
    final kind = p[1], tap = p[2], hero = p.length > 3 ? p[3] : '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      void section() => switch (kind) {
            'sleep' => _open(Cat.health, HealthTab.sleep),
            'body' => _open(Cat.health, HealthTab.body),
            'food' => _open(Cat.food, FoodTab.diary),
            _ => _open(Cat.exercise, ExerciseTab.move),
          };
      switch (tap) {
        case 'today':
          _open(Cat.today);
        case 'add':
          _open(Cat.food, FoodTab.diary);
          openAddFood(context, _food);
        case 'metric' when metricSpecs.containsKey(hero):
          section();
          Navigator.of(context).push(MetricPage.route(widget.store, hero));
        default:
          section();
      }
    });
  }

  void _track() {
    final (tabs, t) = switch (_index) {
      Cat.health => (_healthTabs, _healthTab.value),
      Cat.food => (_foodTabs, _foodTab.value),
      Cat.exercise => (_exerciseTabs, _exerciseTab.value),
      _ => (const <String>[], 0),
    };
    errors.setBase([_catNames[_index], if (t < tabs.length) tabs[t]].join(' › '));
  }

  @override
  void initState() {
    super.initState();
    _track();
    _healthTab.addListener(_track);
    _foodTab.addListener(_track);
    _exerciseTab.addListener(_track);
    widgetOpenRequest.addListener(_fromWidget);
    _fromWidget();
  }

  @override
  void dispose() {
    widgetOpenRequest.removeListener(_fromWidget);
    _healthTab.dispose();
    _foodTab.dispose();
    _exerciseTab.dispose();
    super.dispose();
  }

  void _go(int i) {
    setState(() => _index = i);
    _track();
  }

  /// Από μια κάρτα του «Σήμερα» κατευθείαν στη σωστή κατηγορία και καρτέλα.
  void _open(int category, [int? tab]) {
    if (tab != null) {
      if (category == Cat.health) _healthTab.value = tab;
      if (category == Cat.food) _foodTab.value = tab;
      if (category == Cat.exercise) _exerciseTab.value = tab;
    }
    _go(category);
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(settings: const RouteSettings(name: 'Ρυθμίσεις'), builder: (_) => SettingsPage(store: widget.store, food: _food)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final store = widget.store;
    final pages = <Widget>[
      TodayPage(store: store, food: _food, open: _open, openSettings: _openSettings, now: widget.now),
      CategoryPage(
        title: 'Υγεία',
        color: c.health,
        solid: c.healthSolid,
        tab: _healthTab,
        now: widget.now,
        tabs: _healthTabs,
        pages: [
          SleepPage(store: store, now: widget.now),
          RecoveryPage(store: store, now: widget.now),
          HeartPage(store: store, now: widget.now, onOpenSleep: () => _healthTab.value = HealthTab.recovery),
          BodyPage(store: store),
          TrendsPage(store: store, now: widget.now),
        ],
      ),
      CategoryPage(
        title: 'Διατροφή',
        color: c.food,
        solid: c.foodSolid,
        tab: _foodTab,
        now: widget.now,
        tabs: const ['Ημερολόγιο', 'Τα δικά μου'],
        pages: [
          // Οθόνες φαγητού: κουμπιά στο χρώμα της Διατροφής, σε κάθε θέμα.
          FoodTheme(child: NutritionPage(food: _food, now: widget.now)),
          FoodTheme(child: MinePage(food: _food, store: store)),
        ],
      ),
      CategoryPage(
        title: 'Άσκηση',
        color: c.exercise,
        solid: c.exerciseSolid,
        tab: _exerciseTab,
        now: widget.now,
        tabs: _exerciseTabs,
        pages: [
          TrainingPage(training: TrainingStore.main, health: store, onOpenTrends: () => _open(Cat.health, HealthTab.trends)),
          ExercisePage(store: store),
          const ExerciseLibraryPage(),
        ],
      ),
    ];

    // «+ Φαγητό» μόνο στο ημερολόγιο της Διατροφής, πάντα στην ίδια θέση.
    final fab = ValueListenableBuilder<int>(
      valueListenable: _foodTab,
      builder: (context, t, _) => _index == Cat.food && t == FoodTab.diary
          ? FloatingActionButton.extended(
              onPressed: () => openAddFood(context, _food),
              icon: const Icon(Icons.add_rounded, size: 22),
              label: const Text('Φαγητό', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              backgroundColor: c.foodSolid,
              foregroundColor: c.onSolid,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            )
          : const SizedBox.shrink(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        final content = LazyIndexedStack(index: _index, children: pages);

        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  right: false,
                  child: _SideBar(index: _index, onTap: _go, onSettings: _openSettings),
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
          bottomNavigationBar: _BottomBar(index: _index, onTap: _go),
        );
      },
    );
  }
}

/// Ένας προορισμός: εικονίδιο μέσα σε «χάπι» και όνομα από κάτω.
class _NavItem extends StatelessWidget {
  const _NavItem({super.key, required this.dest, required this.selected, required this.onTap, this.pillHeight = 30});
  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;
  final double pillHeight;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final (pill, ink) = dest.pill(c);
    final iconColor = selected ? ink : c.navIdle;
    return Semantics(
      selected: selected,
      button: true,
      label: dest.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 56,
                height: pillHeight,
                decoration: BoxDecoration(
                  color: selected ? pill : pill.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(selected ? dest.selectedIcon : dest.icon, size: 21, color: iconColor),
              ),
              const SizedBox(height: 4),
              Text(
                dest.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? c.navLabel : c.navIdle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Η σταθερή κάτω μπάρα (κινητό, κλειστό Fold).
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: c.nav,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.navBorder),
          boxShadow: [BoxShadow(color: c.navShadow, blurRadius: 30, offset: const Offset(0, 10))],
        ),
        child: Row(
          children: [
            for (var i = 0; i < _destinations.length; i++)
              Expanded(
                child: _NavItem(
                  key: ValueKey('nav-${_destinations[i].label}'),
                  dest: _destinations[i],
                  selected: i == index,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Κάθετη μπάρα για ανοιχτό Fold, tablet και PC, με τις Ρυθμίσεις κάτω.
class _SideBar extends StatelessWidget {
  const _SideBar({required this.index, required this.onTap, required this.onSettings});
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Container(
      width: 84,
      margin: const EdgeInsets.fromLTRB(14, 14, 0, 14),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: c.nav,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: c.navBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _destinations.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _NavItem(
              key: ValueKey('nav-${_destinations[i].label}'),
              dest: _destinations[i],
              selected: i == index,
              onTap: () => onTap(i),
              pillHeight: 34,
            ),
          ],
          const Spacer(),
          IconButton(
            tooltip: 'Ρυθμίσεις',
            onPressed: onSettings,
            style: IconButton.styleFrom(
              backgroundColor: c.navIdle.withValues(alpha: 0.14),
              foregroundColor: c.navLabel,
              fixedSize: const Size(48, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.tune_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
