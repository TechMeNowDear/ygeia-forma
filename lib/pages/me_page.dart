import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data.dart';
import '../food/food_store.dart';
import '../food/kitchen.dart';
import '../format.dart';
import '../adaptive_check.dart' show quitHoldDays, smokeQuitHoldDays;
import '../history.dart' show dateKey;
import '../profile.dart';
import '../theme.dart';
import '../widgets.dart';
import 'devices_page.dart';
import 'dishes.dart';
import 'recipes.dart' show FoodLikesScreen;
import 'day_close.dart' show openReminderSheet, reminderRowText;
import '../vitals.dart' show VitalsStore;
import 'vitals_page.dart' show VitalsPage;
import 'week.dart' show WeekPlanScreen;
import 'goals_page.dart';
import 'sources_page.dart';
import 'kitchen.dart';
import 'my_foods.dart';

/// «Τα στοιχεία μου» (7/11): γέννηση, φύλο, ύψος για τα εύρη αναφοράς· οι μέρες ζυγίσματος και της μέσης (11/11)·
/// οι στόχοι διατροφής (12/11).
/// Σχέδια 9/11 (10β): εδώ ζουν και «Τα προϊόντα μου» (όλη η λίστα) και «Η κουζίνα μου».
class MePage extends StatefulWidget {
  const MePage({super.key, required this.store, this.food, this.now});
  final HealthStore store;

  /// Round 1 (S12-09 γ, αίτημα f8): το «τώρα» της σελίδας (ηλικία, έτη γέννησης· για στιγμιότυπα). Χωρίς αυτό: το ρολόι.
  final DateTime? now;

  /// Χωρίς αυτό: η αποθήκη φαγητού της εφαρμογής ([FoodStore.shared]).
  final FoodStore? food;

  static Route<void> route(HealthStore store) =>
      MaterialPageRoute<void>(settings: const RouteSettings(name: 'Τα στοιχεία μου'), builder: (_) => MePage(store: store));

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  late final TextEditingController _height;

  @override
  void initState() {
    super.initState();
    final h = widget.store.profile.heightCm;
    _height = TextEditingController(text: h == null ? '' : _cm(h));
  }

  /// «180» ή «174,5» (πριν «180,0»: έλεγχος 13/11, U3a-16).
  static String _cm(double h) => dec(h, h % 1 == 0 ? 0 : 1);

  /// Ύψος από 100 ως 250 cm, ή null.
  static double? _heightOf(String v) {
    final h = double.tryParse(v.replaceAll(',', '.').trim());
    return h != null && h >= 100 && h <= 250 ? h : null;
  }

  @override
  void dispose() {
    _height.dispose();
    super.dispose();
  }

  /// Ύψος από την τελευταία ζύγιση (βάρος και δείκτης της InBody), ως πρόταση.
  double? _scaleHeight() {
    final b = widget.store.data?.latestBody;
    if (b?.weight == null || b?.bmi == null || b!.bmi! <= 0) return null;
    final cm = math.sqrt(b.weight! / b.bmi!) * 100;
    return (cm * 2).round() / 2;
  }

  void _save(Profile p) => widget.store.setProfile(p);

  String _goalsText() {
    final g = widget.store.goals;
    // Έλεγχος round1 (U3a-6): αδιάσπαστο κενό ανάμεσα στον αριθμό και στη λέξη του (πριν έσπαγε σε «· 2» / «λεπτά»).
    if (g == null) return 'Θερμίδες, πρωτεΐνη, χοληστερίνη ·\u00A02\u00A0λεπτά';
    return '${thousands(g.kcal)}\u00A0kcal ·\u00A0${g.protein}\u00A0g πρωτεΐνη${g.doctor ? ' ·\u00A0χοληστερίνη' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final now = widget.now ?? DateTime.now();
    final food = widget.food ?? FoodStore.shared;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.store, if (food != null) food]),
      builder: (context, _) {
        final p = widget.store.profile;
        final suggested = _scaleHeight();
        final label = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text);
        final hint = TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4);
        return Scaffold(
          appBar: AppBar(title: const Text('Τα στοιχεία μου')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    Text('Χρειάζονται για τα εύρη που δείχνει η εφαρμογή. Μένουν μόνο στο κινητό σου.', style: hint),
                    const SizedBox(height: 12),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Γέννηση', style: label),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  key: const ValueKey('me-month'),
                                  isExpanded: true,
                                  initialValue: p.birthMonth,
                                  // Έλεγχος 13/11 (U3a-16): πεδία με περίγραμμα, όπως στις φόρμες φαγητού (πριν έμοιαζαν με
                                  // σκέτες λέξεις πάνω σε γραμμή, και η γραμμή τους κολλούσε στη διαχωριστική από κάτω).
                                  decoration: const InputDecoration(labelText: 'Μήνας', border: _outline),
                                  items: [
                                    for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(monthNames[m - 1], overflow: TextOverflow.ellipsis)),
                                  ],
                                  onChanged: (v) => _save(p.copyWith(birthMonth: v)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  key: const ValueKey('me-year'),
                                  isExpanded: true,
                                  initialValue: p.birthYear,
                                  decoration: const InputDecoration(labelText: 'Έτος', border: _outline),
                                  items: [
                                    for (var y = now.year - 18; y >= 1930; y--) DropdownMenuItem(value: y, child: Text('$y')),
                                  ],
                                  onChanged: (v) => _save(p.copyWith(birthYear: v)),
                                ),
                              ),
                            ],
                          ),
                          if (p.ageOn(now) != null) ...[
                            const SizedBox(height: 6),
                            Text('Ηλικία ${p.ageOn(now)}', style: hint),
                          ],
                          const Hairline(vertical: 14),
                          Text('Φύλο', style: label),
                          const SizedBox(height: 8),
                          SegmentedButton<String>(
                            key: const ValueKey('me-sex'),
                            emptySelectionAllowed: true,
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: 'm', label: Text('Άνδρας', style: TextStyle(fontFamily: 'Inter'))),
                              ButtonSegment(value: 'f', label: Text('Γυναίκα', style: TextStyle(fontFamily: 'Inter'))),
                            ],
                            selected: {if (p.sex != null) p.sex!},
                            onSelectionChanged: (s) {
                              if (s.isNotEmpty) _save(p.copyWith(sex: s.first));
                            },
                          ),
                          const SizedBox(height: 6),
                          Text('Οι επιστημονικές πηγές δίνουν τα εύρη χωριστά για άνδρες και γυναίκες.', style: hint),
                          const Hairline(vertical: 14),
                          TextField(
                            key: const ValueKey('me-height'),
                            controller: _height,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            // U3a-16: ύψος που δεν γίνεται δεκτό (π.χ. «1,80» ή «300») το λέει το πεδίο· πριν κρατούσε το
                            // κείμενο και δεν αποθήκευε τίποτα, χωρίς λέξη.
                            decoration: InputDecoration(
                              labelText: 'Ύψος',
                              suffixText: 'cm',
                              border: _outline,
                              errorText: _height.text.trim().isNotEmpty && _heightOf(_height.text) == null
                                  ? 'Γράψε το ύψος σε εκατοστά, από 100 ως 250, π.χ. 180'
                                  : null,
                            ),
                            onChanged: (v) {
                              final h = _heightOf(v);
                              if (h != null) {
                                _save(p.copyWith(heightCm: h));
                              } else {
                                setState(() {});
                              }
                            },
                          ),
                          if (suggested != null && p.heightCm == null) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () {
                                  _height.text = _cm(suggested);
                                  _save(p.copyWith(heightCm: suggested));
                                },
                                child: Text('Από τη ζυγαριά: ${_cm(suggested)} cm'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _smoking(context, p, now, label, hint),
                    const SizedBox(height: 12),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Μέρες ζυγίσματος', style: label),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              for (var d = 1; d <= 7; d++) ...[
                                if (d > 1) const SizedBox(width: 6),
                                Expanded(
                                  child: _DayChip(
                                    key: ValueKey('me-weigh-$d'),
                                    label: weekdayChips[d - 1],
                                    semantics: weekdayNames[d - 1],
                                    selected: p.weighDays.contains(d),
                                    onTap: () {
                                      final days = {...p.weighDays};
                                      // Τουλάχιστον μία μέρα: η τελευταία δεν βγαίνει.
                                      if (days.contains(d)) {
                                        if (days.length > 1) days.remove(d);
                                      } else {
                                        days.add(d);
                                      }
                                      _save(p.copyWith(weighDays: days));
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Πρωί, μετά την τουαλέτα, πριν φας ή πιεις, με τα ίδια ρούχα. Με 3 ζυγίσεις την εβδομάδα η τάση του '
                            'βάρους βγαίνει πιο σίγουρη.',
                            style: hint,
                          ),
                          const Hairline(vertical: 14),
                          Text('Μέση με μεζούρα', style: label),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              for (var d = 1; d <= 7; d++) ...[
                                if (d > 1) const SizedBox(width: 6),
                                Expanded(
                                  child: _DayChip(
                                    key: ValueKey('me-waist-$d'),
                                    label: weekdayChips[d - 1],
                                    semantics: 'Μέση ${weekdayNames[d - 1]}',
                                    selected: p.waistDay == d,
                                    onTap: () => _save(p.copyWith(waistDay: d)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Μία φορά την εβδομάδα, μετά τη ζύγιση. Η Σήμερα σου το θυμίζει.', style: hint),
                        ],
                      ),
                    ),
                    const GroupLabel('Στόχοι'),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: NavRow(
                        key: const ValueKey('me-goals'),
                        icon: Icons.flag_rounded,
                        color: c.food,
                        title: 'Στόχοι διατροφής',
                        text: _goalsText(),
                        onTap: () => openGoals(context, widget.store),
                      ),
                    ),
                    if (food != null) ...[
                      const GroupLabel('Διατροφή'),
                      _nutrition(context, food),
                    ],
                    // Πίεση, σάκχαρο, καρδιογραφήματα με το χέρι (16/11).
                    const GroupLabel('Μετρήσεις με το χέρι'),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: ListenableBuilder(
                        listenable: VitalsStore.main,
                        builder: (context, _) {
                          final n = VitalsStore.main.all.length;
                          return NavRow(
                            key: const ValueKey('me-vitals'),
                            icon: Icons.monitor_heart_outlined,
                            color: c.health,
                            title: 'Πίεση, σάκχαρο, καρδιογράφημα',
                            text: n == 0 ? 'Γράψε τις μετρήσεις σου' : (n == 1 ? '1 μέτρηση' : '$n μετρήσεις'),
                            onTap: () => Navigator.of(context).push(VitalsPage.route(VitalsStore.main)),
                          );
                        },
                      ),
                    ),
                    // Έλεγχος premium (S6): όχι σταθερό κείμενο («Oura / Ρολόι / InBody») που θα έλεγε ψέματα χωρίς Oura·
                    // οι πηγές όπως ισχύουν τώρα είναι στη σελίδα «Πηγές».
                    const GroupLabel('Από πού έρχεται κάθε μέτρηση'),
                    // Round 2 (R2-U1-7 = U3a-3): μία κάρτα με δύο γραμμές και μία διαχωριστική, όπως η «Διατροφή» (πριν:
                    // δύο κάρτες κολλημένες, με τη γραμμή της πρώτης στο κάτω της άκρο).
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        NavRow(
                          key: const ValueKey('me-sources'),
                          icon: Icons.hub_outlined,
                          color: c.health,
                          title: 'Πηγές',
                          text: 'Ποια συσκευή δίνει κάθε μέτρηση, από πότε',
                          line: true,
                          onTap: () => Navigator.of(context).push(SourcesPage.route(widget.store)),
                        ),
                        NavRow(
                          key: const ValueKey('me-devices'),
                          icon: Icons.layers_rounded,
                          color: c.health,
                          title: 'Τι μετράει κάθε συσκευή',
                          text: 'Μέτρηση, εκτίμηση, ενδεικτικό',
                          onTap: () => Navigator.of(context).push(DevicesPage.route()),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// «Τα προϊόντα μου» και «Η κουζίνα μου» (πριν: υπο-καρτέλα «Τα δικά μου» της Διατροφής).
  /// Κάπνισμα (απόφαση χρήστη 17/11): για τον κίνδυνο της καρδιάς στις εξετάσεις και τον εβδομαδιαίο έλεγχο θερμίδων.
  Widget _smoking(BuildContext context, Profile p, DateTime now, TextStyle label, TextStyle hint) {
    final today = DateTime(now.year, now.month, now.day);
    final s = p.smoke;
    int? num(String v, int lo, int hi) {
      final n = int.tryParse(v.trim());
      return n != null && n >= lo && n <= hi ? n : null;
    }

    final pack = p.packYears(today);
    final quit = p.quitDate;
    final hold = quitHoldDays(quit, today);
    return AppCard(
      key: const ValueKey('me-smoking'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Κάπνισμα', style: label),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            key: const ValueKey('me-smoke'),
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'no', label: Text('Όχι', style: TextStyle(fontFamily: 'Inter'))),
              ButtonSegment(value: 'now', label: Text('Καπνίζω', style: TextStyle(fontFamily: 'Inter'))),
              ButtonSegment(value: 'ex', label: Text('Το έκοψα', style: TextStyle(fontFamily: 'Inter'))),
            ],
            selected: {if (s != null) s},
            onSelectionChanged: (v) {
              if (v.isEmpty) return;
              final n = v.first;
              // «Το έκοψα»: η μέρα είναι σήμερα, εκτός αν είχε ήδη γραφτεί.
              _save(p.withSmoking(
                  smoke: n, cigs: p.cigs, smokeFrom: p.smokeFrom, quit: n == 'ex' ? (p.quit ?? dateKey(today)) : null));
            },
          ),
          if (s == 'now' || s == 'ex') ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('me-cigs'),
                    initialValue: p.cigs?.toString() ?? '',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: s == 'ex' ? 'Τσιγάρα τη μέρα (τότε)' : 'Τσιγάρα τη μέρα', border: _outline),
                    onChanged: (v) {
                      final n = num(v, 1, 80);
                      if (n != null) _save(p.withSmoking(smoke: s, cigs: n, smokeFrom: p.smokeFrom, quit: p.quit));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('me-smoke-from'),
                    initialValue: p.smokeFrom?.toString() ?? '',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Από ηλικία', border: _outline),
                    onChanged: (v) {
                      final n = num(v, 8, 80);
                      if (n != null) _save(p.withSmoking(smoke: s, cigs: p.cigs, smokeFrom: n, quit: p.quit));
                    },
                  ),
                ),
              ],
            ),
          ],
          if (s == 'ex') ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('me-quit'),
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text('Το έκοψα στις ${quit == null ? '—' : dayMonthYear(quit)}'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: quit ?? today,
                    firstDate: DateTime(1950),
                    lastDate: today,
                  );
                  if (d == null || !mounted) return;
                  _save(p.withSmoking(smoke: 'ex', cigs: p.cigs, smokeFrom: p.smokeFrom, quit: dateKey(d)));
                },
              ),
            ),
          ],
          const SizedBox(height: 6),
          if (pack != null)
            Text('Πακέτα-έτη: ${dec(pack, pack < 10 ? 1 : 0)} (τσιγάρα τη μέρα ÷ 20 × χρόνια). Το ρωτά συχνά ο γιατρός.',
                key: const ValueKey('me-pack-years'), style: hint),
          if (s == 'now')
            Text('Αν το κόψεις, πάτα «Το έκοψα»: η εφαρμογή κρατά τη μέρα.', style: hint)
          else if (hold != null)
            Text(
                'Για ${smokeQuitHoldDays ~/ 7} εβδομάδες από τη μέρα που το έκοψες, ο εβδομαδιαίος έλεγχος δεν κατεβάζει τις '
                'θερμίδες σου: λίγα κιλά στην αρχή είναι συνηθισμένα, και μετράει να μην ξαναρχίσεις.',
                key: const ValueKey('me-quit-hold'),
                style: hint)
          else if (s == null)
            Text('Χρειάζεται για τον κίνδυνο της καρδιάς στις εξετάσεις.', style: hint),
        ],
      ),
    );
  }

  Widget _nutrition(BuildContext context, FoodStore food) {
    final c = Aigaio.of(context);
    final n = food.mine.length;
    final k = Kitchen.fromJson(widget.store.prefs.kitchen);
    final dn = food.dishes.length;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        // «Τα φαγητά μου» (15/11).
        NavRow(
          key: const ValueKey('mine-dishes'),
          icon: Icons.restaurant_menu_rounded,
          color: c.food,
          title: 'Τα φαγητά μου',
          text: dn == 0
              ? 'Φαγητά από τα δικά σου υλικά, για να τα γράφεις με ένα πάτημα.'
              : '${countText(dn, 'φαγητό', 'φαγητά')} ·\u00A0αλλαγή, διαγραφή',
          line: true,
          onTap: () => Navigator.of(context).push(DishesScreen.route(food)),
        ),
        // Πρόγραμμα εβδομάδας (15/11).
        NavRow(
          key: const ValueKey('mine-week'),
          icon: Icons.event_note_rounded,
          color: c.food,
          title: 'Πρόγραμμα εβδομάδας',
          text: food.week == null
              ? 'Τι θα φας κάθε μέρα, από τη βιβλιοθήκη των φαγητών σου.'
              : 'Από ${shortDayDate(food.week!.start)} ως ${shortDayDate(food.week!.end)}',
          line: true,
          onTap: () => Navigator.of(context).push(WeekPlanScreen.route(food)),
        ),
        // Βραδινή υπενθύμιση (16/11).
        NavRow(
          key: const ValueKey('mine-remind'),
          icon: Icons.notifications_none_rounded,
          color: c.food,
          title: 'Βραδινή υπενθύμιση',
          text: reminderRowText(food.remindAt),
          line: true,
          onTap: () => openReminderSheet(context, food),
        ),
        // «Τι μου αρέσει» (15/11): για τις συνταγές από AI.
        NavRow(
          key: const ValueKey('mine-likes'),
          icon: Icons.favorite_border_rounded,
          color: c.food,
          title: 'Τι μου αρέσει',
          text: food.likes.isEmpty
              ? 'Για τις συνταγές: τι σου αρέσει και τι όχι.'
              : '${countText(food.likes.like.length, 'τρόφιμο', 'τρόφιμα')} ·\u00A0δε μου αρέσουν ${food.likes.dislike.length}',
          line: true,
          onTap: () => Navigator.of(context).push(FoodLikesScreen.route(food)),
        ),
        NavRow(
          key: const ValueKey('mine-products'),
          icon: Icons.inventory_2_outlined,
          color: c.food,
          title: 'Τα προϊόντα μου',
          text: n == 0
              // Έλεγχος round1 (U3a-18): όπως στο «Τα προϊόντα μου» (πριν «…χωρίς να το φας.»).
              ? 'Πέρασε ό,τι αγοράζεις, με «Σάρωση» ή από την ετικέτα, χωρίς να το καταγράψεις ως φαγητό.'
              : '${n == 1 ? '1 προϊόν' : '$n προϊόντα'} ·\u00A0αλλαγή, αντιγραφή, διαγραφή',
          line: true,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'Τα προϊόντα μου'), builder: (_) => MyFoodsScreen(food: food))),
        ),
        NavRow(
          key: const ValueKey('mine-kitchen'),
          icon: Icons.soup_kitchen_outlined,
          color: c.food,
          title: 'Η κουζίνα μου',
          text: '${countText(k.devices.length, 'συσκευή', 'συσκευές')} ·\u00A0${countText(k.cookware.length, 'σκεύος', 'σκεύη')} ·\u00A0για τις συνταγές, όταν έρθουν',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'Η κουζίνα μου'), builder: (_) => KitchenScreen(store: widget.store))),
        ),
      ]),
    );
  }
}

/// Περίγραμμα των πεδίων της σελίδας (U3a-16).
const _outline = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)));

class _DayChip extends StatelessWidget {
  const _DayChip({super.key, required this.label, required this.semantics, required this.selected, required this.onTap});
  final String label;
  final String semantics;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: semantics,
      child: Material(
        color: selected ? c.body : c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? c.body : c.hairline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          // Έλεγχος 13/11 (U3a-17): ύψος αφής 48, όπως παντού (πριν 44 με το περίγραμμα· 42 στην οθόνη).
          child: SizedBox(
            height: 48,
            child: Center(
              // Μεγάλα γράμματα: η συντομογραφία μικραίνει για να χωρά, ποτέ κομμένη (σχέδια 9/11).
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    maxLines: 1,
                    // U3a-2: στο σκούρο «Αιγαίο» το λευκό πάνω στο ανοιχτό πράσινο είχε αντίθεση 2,2:1· τώρα λευκό ή σκούρο,
                    // όποιο φαίνεται καλύτερα πάνω στο χρώμα της επιλογής.
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: selected ? Aigaio.inkOn(c.body) : c.text)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
