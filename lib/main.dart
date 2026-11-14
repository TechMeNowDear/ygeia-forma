import 'package:flutter/material.dart';

import 'data.dart';
import 'error_report.dart';
import 'food/food_store.dart';
import 'home_widgets/widget_bridge.dart';
import 'nav.dart';
import 'pages/privacy_page.dart' show WipeStatus, WipeUnfinishedApp, WipedPage, markWipeSeen, readWipeStatus, registerLicenses, startsApp;
import 'pages/exercise_library.dart';
import 'pages/training/training_page.dart';
import 'heart_day.dart' show appExerciseRanges;
import 'training/training_store.dart';
import 'training/wear_link.dart';
import 'training/zone.dart';
import 'pages/body.dart';
import 'pages/category.dart';
import 'pages/food_add.dart';
import 'pages/heart.dart';
import 'pages/metric_page.dart';
import 'pages/move.dart';
import 'pages/nutrition.dart';
import 'pages/settings.dart';
import 'pages/sleep.dart';
import 'pages/today.dart';
import 'pages/trends.dart';
import 'pages/widget_config_page.dart';
import 'plan_file.dart' show PlanState;
import 'system_texts.dart';
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
  // Έλεγχος 9/11 (DP-07), πριν από την πρώτη ανάγνωση: οι προπονήσεις της εφαρμογής δεν μετρούν στους παλμούς της μέρας και στην ηρεμία.
  appExerciseRanges = () => [
        for (final s in [...TrainingStore.main.sessions, if (TrainingStore.main.current case final c?) c])
          (s.start, (s.end ?? DateTime.now()).add(const Duration(minutes: 5))),
      ];
  // «Διαγραφή όλων» (έλεγχος του fix-accuracy, M4): μετά τη νέα εκκίνηση, «Όλα διαγράφηκαν» αντί για την αρχική.
  // N2: αν το σβήσιμο δεν τελείωσε, ΤΙΠΟΤΑ δεν ξεκινά (ούτε ρολόι ούτε αναγνώσεις): ό,τι γραφόταν τώρα θα σβηνόταν.
  final wiped = await readWipeStatus();
  if (!startsApp(wiped)) {
    runApp(WipeUnfinishedApp(status: wiped!));
    return;
  }
  final store = HealthStore();
  HealthStore.shared = store;
  final food = FoodStore();
  // Round 7 (R7-A9-1): μετά από βλάβη της βάσης ξαναμπαίνουν και το φαγητό και τα προϊόντα, όχι μόνο το ιστορικό.
  store.onDatabaseReset = food.recoverAfterDbReset;
  // Πρώτα οι ρυθμίσεις (λίγα ms), ώστε η πρώτη οθόνη να έχει ήδη το θέμα που διάλεξα.
  await store.loadPrefs();
  void startStores() {
    store.start();
    food.start();
    WidgetPublisher(store, food, training: TrainingStore.main).start();
    // Ρολόι (8/11): μόλις φορτωθεί η προπόνηση, πρόγραμμα προς το ρολόι και ό,τι έγινε εκεί προς το κινητό.
    TrainingStore.main.load().then((_) => WearLink.main.start(TrainingStore.main));
  }

  // Έλεγχος 13/11 (U4-6): όσο φαίνεται το «Όλα διαγράφηκαν», τίποτα δεν διαβάζεται και τίποτα δεν πάει στα widgets. Πριν,
  // οι αναγνώσεις ξεκινούσαν πίσω από εκείνη την οθόνη (οι άδειες του Samsung Health μένουν μετά τη διαγραφή), και ύπνος,
  // βήματα και ζυγίσεις ήταν ξανά στο κινητό ενώ η οθόνη έλεγε «όπως την πρώτη μέρα». Ξεκινούν όταν ο χρήστης πατήσει
  // «Ξεκίνα από την αρχή» ή «Επαναφορά από αντίγραφο» (το ίδιο και η ανανέωση στο παρασκήνιο: DataWipe.kt, «wipeSeen»).
  final showWiped = wiped?.show == true;
  runApp(YgeiaFormaApp(store: store, food: food, wiped: showWiped ? wiped : null, onLeaveWiped: showWiped ? startStores : null));
  if (!showWiped) startStores();
}

class YgeiaFormaApp extends StatefulWidget {
  const YgeiaFormaApp({super.key, required this.store, required this.food, this.wiped, this.onLeaveWiped});
  final HealthStore store;
  final FoodStore food;

  /// Μόλις έγινε «Διαγραφή όλων»: πρώτα η οθόνη «Όλα διαγράφηκαν».
  final WipeStatus? wiped;

  /// Καλείται μία φορά, όταν ο χρήστης φύγει από το «Όλα διαγράφηκαν»: τότε ξεκινούν οι αναγνώσεις (U4-6).
  final VoidCallback? onLeaveWiped;

  @override
  State<YgeiaFormaApp> createState() => _YgeiaFormaAppState();
}

class _YgeiaFormaAppState extends State<YgeiaFormaApp> {
  // Ίδιο αντικείμενο σε κάθε αλλαγή θέματος: αλλάζουν μόνο τα χρώματα, όχι η κατάσταση.
  late final Widget _home = Shell(store: widget.store, food: widget.food);
  late WipeStatus? _wiped = widget.wiped;
  final _nav = GlobalKey<NavigatorState>();

  void _leaveWiped({bool restore = false}) {
    markWipeSeen();
    // Μία φορά: η οθόνη «Όλα διαγράφηκαν» δεν ξαναφαίνεται μετά από αυτό (το _wiped γίνεται null).
    if (_wiped != null) widget.onLeaveWiped?.call();
    setState(() => _wiped = null);
    if (!restore) return;
    // «Επαναφορά από αντίγραφο»: οι Ρυθμίσεις, όπου είναι η επαναφορά (ΤΑ ΔΕΔΟΜΕΝΑ ΜΟΥ).
    WidgetsBinding.instance.addPostFrameCallback((_) => _nav.currentState?.push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'Ρυθμίσεις'), builder: (_) => SettingsPage(store: widget.store, food: widget.food))));
  }

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
          navigatorKey: _nav,
          // Round 7 (R7-U4-7): «Αντιγραφή/Επικόλληση», «Πίσω», «Άδειες λογισμικού» κ.λπ. στα ελληνικά (system_texts.dart).
          localizationsDelegates: greekSystemTexts,
          home: _wiped == null
              ? _home
              : WipedPage(status: _wiped!, onStart: _leaveWiped, onRestore: () => _leaveWiped(restore: true)),
          // Έλεγχος 9/11 (E3-08, Sentry YGEIA-FORMA-3): μια άγνωστη διαδρομή (π.χ. URI από άλλη εφαρμογή) δεν ρίχνει
          // ποτέ την εφαρμογή· μένει στην αρχική. Μαζί με το flutter_deeplinking_enabled=false στο manifest.
          onUnknownRoute: unknownRoute,
        );
      },
    );
  }
}

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
  late final FoodStore _food = FoodStore.shared = widget.food ?? FoodStore.preloaded(foods: const []);
  late final _healthTab = ValueNotifier(widget.initialIndex == Cat.health && widget.initialTab < _healthTabs.length ? widget.initialTab : 0);
  late final _foodTab = ValueNotifier(0);
  late final _exerciseTab = ValueNotifier(widget.initialIndex == Cat.exercise ? widget.initialTab : 0);

  /// Έλεγχος 13/11 (S10-4): οι τέσσερις κύριες σελίδες μπαίνουν σε άλλη θέση του δέντρου στη στενή διάταξη (σώμα του
  /// Scaffold) και στη φαρδιά (μέσα σε Row, δίπλα στην πλαϊνή μπάρα). Χωρίς κλειδί, το άνοιγμα ή το κλείσιμο του Fold τις
  /// έχτιζε από την αρχή: χανόταν η θέση κύλισης, η περίοδος των Τάσεων, η αναζήτηση ασκήσεων. Με GlobalKey μετακινούνται.
  final _stackKey = GlobalKey();

  // Για την αναφορά σφαλμάτων: σε ποια κατηγορία και καρτέλα είμαι.
  static const _catNames = ['Σήμερα', 'Υγεία', 'Διατροφή', 'Άσκηση'];
  static const _healthTabs = ['Ύπνος', 'Καρδιά', 'Σώμα', 'Τάσεις'];

  /// Σχέδια 9/11 (10β): η Διατροφή είναι μία σελίδα, χωρίς υπο-καρτέλες. «Τα προϊόντα μου» φαίνονται στο «+ Φαγητό»
  /// (Δικά μου) και, μαζί με την κουζίνα, στο «Τα στοιχεία μου».
  static const _foodTabs = ['Ημερολόγιο'];
  static const _exerciseTabs = ['Προπόνηση', 'Κίνηση', 'Ασκήσεις'];

  /// Πάτημα σε widget της αρχικής οθόνης: «w:<είδος>:<πάτημα>:<κεντρική τιμή>» (HomeWidgets.kt).
  void _fromWidget() {
    final req = widgetOpenRequest.value;
    if (req == null) return;
    widgetOpenRequest.value = null;
    final p = req.split(':');
    if (p.length < 3 || p[0] != 'w') return;
    final kind = p[1], tap = p[2], hero = p.length > 3 ? p[3] : '';
    // Round 1 (integ1): το πάτημα φτάνει από την Kotlin χωρίς να αλλάξει τίποτα στην οθόνη, άρα κανένα καρέ δεν ζητιέται
    // και η μετάβαση περίμενε το επόμενο τυχαίο καρέ (ένα άγγιγμα, μια ανανέωση). Ζητάμε ένα καρέ, για να γίνει αμέσως.
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      void section() => switch (kind) {
            'sleep' => _open(Cat.health, HealthTab.sleep),
            'body' => _open(Cat.health, HealthTab.body),
            'food' => _open(Cat.food, FoodTab.diary),
            // 13/11: το widget «Προπόνηση σήμερα» ανοίγει την Άσκηση › Προπόνηση (εκεί είναι το «Ξεκίνα»).
            'workout' => _open(Cat.exercise, ExerciseTab.train),
            _ => _open(Cat.exercise, ExerciseTab.move),
          };
      switch (tap) {
        case 'today':
          _open(Cat.today);
        // Έλεγχος round1 (S2-8 / S11-1): από την αρχική οθόνη το φαγητό γράφεται ΠΑΝΤΑ στη σημερινή μέρα. Το ημερολόγιο
        // γυρίζει πρώτα στο «Σήμερα» (πριν, αν είχε μείνει π.χ. στο «Χθες», το φαγητό πήγαινε σιωπηλά εκεί).
        case 'add':
          _open(Cat.food, FoodTab.diary);
          _food.setDay(widget.now ?? DateTime.now());
          openAddFood(context, _food);
        // 13/11: το «Barcode» του widget «Γρήγορο φαγητό»: η ίδια οθόνη, με τον σαρωτή ανοιχτό αμέσως.
        case 'scan':
          _open(Cat.food, FoodTab.diary);
          _food.setDay(widget.now ?? DateTime.now());
          openAddFood(context, _food, scan: true);
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
    widget.store.addListener(_zoneSync);
    TrainingStore.main.addListener(_zoneSync);
    _zoneSync();
  }

  /// Ζώνη περπατήματος (12/11): η εφαρμογή την υπολογίζει (ηλικία, παλμοί ύπνου) και τη δίνει στις προπονήσεις, που τη
  /// στέλνουν στο ρολόι. Μόνο με διαβασμένες ρυθμίσεις, ιστορικό, σχέδιο πηγών και προπονήσεις: αλλιώς μια προσωρινή ζώνη
  /// (π.χ. χωρίς παλμούς ύπνου ακόμα) θα έσβηνε την αποθηκευμένη και θα πήγαινε στο ρολόι (ανασκόπηση 11/11, M1). Αν το
  /// ιστορικό δεν διαβαστεί, μένει η αποθηκευμένη. Δεν γράφει τίποτα αν δεν άλλαξε.
  void _zoneSync() {
    final t = TrainingStore.main;
    final h = widget.store;
    if (!h.prefsReady || !h.historyReady || h.planState == PlanState.loading || !t.ready || t.readError) return;
    final z = widget.store.zoneOn(widget.now ?? DateTime.now());
    final s = widget.store.zoneSettings;
    t.setZone(z == null ? null : WalkZone(z.lo, z.hi, up: s.alertHigh, down: s.alertLow));
  }

  @override
  void dispose() {
    widget.store.removeListener(_zoneSync);
    TrainingStore.main.removeListener(_zoneSync);
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
      if (category == Cat.food) _foodTab.value = FoodTab.diary;
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
          HeartPage(store: store, now: widget.now, onOpenSleep: () => _healthTab.value = HealthTab.sleep),
          BodyPage(store: store, now: widget.now),
          TrendsPage(store: store, now: widget.now),
        ],
      ),
      // Έλεγχος round1 (U3a-1): η κεφαλίδα γράφει τη μέρα που δείχνει το ημερολόγιο, όταν δεν είναι η σημερινή (πριν
      // έγραφε πάντα τη σημερινή ημερομηνία, ενώ από κάτω φαινόταν άλλη μέρα).
      ListenableBuilder(
        listenable: _food,
        builder: (context, _) => CategoryPage(
          title: 'Διατροφή',
          color: c.food,
          solid: c.foodSolid,
          tab: _foodTab,
          now: _food.otherDayShown(widget.now ?? DateTime.now()) ?? widget.now,
          tabs: _foodTabs,
          pages: [
            // Οθόνες φαγητού: κουμπιά στο χρώμα της Διατροφής, σε κάθε θέμα.
            FoodTheme(child: NutritionPage(food: _food, health: widget.store, now: widget.now)),
          ],
        ),
      ),
      CategoryPage(
        title: 'Άσκηση',
        color: c.exercise,
        solid: c.exerciseSolid,
        tab: _exerciseTab,
        now: widget.now,
        tabs: _exerciseTabs,
        pages: [
          // Round 1 (f9 · U5-30): κουμπιά, διακόπτες και επιλογές στο χρώμα της Άσκησης (όπως η Διατροφή), όχι μπλε.
          ExerciseTheme(
              child: TrainingPage(
                  training: TrainingStore.main, health: store, onOpenTrends: () => _open(Cat.health, HealthTab.trends))),
          ExerciseTheme(child: ExercisePage(store: store, now: widget.now)),
          const ExerciseTheme(child: ExerciseLibraryPage()),
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
        final content = LazyIndexedStack(key: _stackKey, index: _index, children: pages);

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
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  dest.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? c.navLabel : c.navIdle,
                  ),
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
      // Μεγάλα γράμματα (σχέδια 9/11): η μπάρα ψηλώνει όσο χρειάζεται (πριν: σταθερά 68 dp, ξεχείλιζε στο 1,3×)· τα
      // ονόματα μεγαλώνουν ως 1,5×, για να χωρούν και τα τέσσερα σε μία γραμμή.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.5,
        child: Container(
        constraints: const BoxConstraints(minHeight: 68),
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
      )
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
