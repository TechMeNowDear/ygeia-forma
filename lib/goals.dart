/// Στόχοι διατροφής (σχέδια 12/11, εγκρίθηκαν 11/11).
///
/// Ο οδηγός ρωτά: στόχο, ρυθμό, κίνηση, αν ο γιατρός ζήτησε να πέσει η LDL. Οι αριθμοί βγαίνουν ΜΟΝΟ από τους τύπους
/// με πηγή (καμία «εκτίμηση» από AI):
/// - Ξεκούραση: Mifflin-St Jeor (Mifflin 1990, AJCN).
/// - Κίνηση: επίπεδα σωματικής δραστηριότητας 1,4 / 1,5 / 1,7 (FAO/WHO/UNU 2004).
/// - Ρυθμός: ποσοστό του βάρους την εβδομάδα × 7.700 kcal/kg ÷ 7 (Hall 2008: προσέγγιση· Helms 2014: 0,5–1% για να
///   μένουν οι μύες· αύξηση 0,25–0,5%, Iraki 2019).
/// - Κάτω όριο: 1.500 kcal άνδρες, 1.200 γυναίκες (Jensen 2013, AHA/ACC/TOS).
/// - Πρωτεΐνη 1,6 g/kg (Morton 2018, BJSM)· λίπος 25–35% (EFSA 2010)· κορεσμένα έως 6% όταν ο γιατρός ζητά μείωση LDL
///   (Eckel 2013, AHA/ACC: 5–6%), αλλιώς κάτω από 10% (ΠΟΥ)· φυτικές ίνες 30 g (Reynolds 2019)· αλάτι κάτω από 5 g (ΠΟΥ).
///
/// Οι στόχοι αποθηκεύονται ΜΕ τους αριθμούς τους (και τα στοιχεία από τα οποία βγήκαν), ώστε η οθόνη «Πώς
/// υπολογίστηκε» να λέει ακριβώς τι ίσχυε και οι στόχοι να μην αλλάζουν σιωπηλά με κάθε ζύγιση.
library;

import 'dart:math' as math;

import 'waist.dart' show isDayKey;

/// Τι θέλει ο χρήστης πρώτα.
enum GoalAim { lose, keep, gain }

/// Πόσο γρήγορα: ποσοστό του βάρους την εβδομάδα.
const loseRates = [0.0025, 0.005, 0.0075];
const gainRates = [0.0025, 0.005];

/// Κίνηση: επίπεδο σωματικής δραστηριότητας (FAO/WHO/UNU 2004).
const activityLevels = [1.4, 1.5, 1.7];

/// Ενέργεια ανά κιλό βάρους που χάνεται ή κερδίζεται (προσέγγιση, Hall 2008).
const kcalPerKg = 7700.0;

/// Κάτω όριο ασφαλείας θερμίδων χωρίς ιατρική παρακολούθηση (Jensen 2013, AHA/ACC/TOS).
const kcalFloorMale = 1500;
const kcalFloorFemale = 1200;

/// Πρωτεΐνη ανά κιλό (Morton 2018).
const proteinPerKg = 1.6;

/// Προεπιλογές της κάρτας «Χοληστερίνη» από το «ιδανικό πλάνο» (10/11).
const defaultNutsG = 30;
const defaultBranG = 40;
const defaultLegumesWeek = 4;
const defaultFishWeek = 6;

/// β-γλυκάνες της βρώμης την ημέρα για τον ισχυρισμό της EFSA για τη χοληστερίνη.
const betaGlucanTarget = 3.0;

class GoalCalc {
  const GoalCalc({
    required this.bmr,
    required this.tdee,
    required this.delta,
    required this.kcal,
    required this.floored,
    required this.protein,
    required this.fatLo,
    required this.fatHi,
    required this.satMax,
    required this.satPct,
    required this.fiber,
    required this.salt,
    required this.carbsEst,
  });

  /// Σε πλήρη ξεκούραση (Mifflin-St Jeor), kcal.
  final double bmr;

  /// Με την κίνηση (× επίπεδο), kcal.
  final double tdee;

  /// Για τον ρυθμό: αρνητικό για απώλεια, θετικό για αύξηση, kcal/ημέρα.
  final double delta;

  /// Ο στόχος, στρογγυλεμένος στα 10.
  final int kcal;

  /// Ο στόχος ανέβηκε στο κάτω όριο ασφαλείας.
  final bool floored;

  final int protein;
  final int fatLo, fatHi;
  final int satMax;

  /// 6 ή 10 (% των θερμίδων).
  final int satPct;
  final int fiber;
  final double salt;

  /// Υδατάνθρακες «ό,τι μένει» με λίπος στο 30% (μόνο για ενημέρωση, όχι στόχος).
  final int carbsEst;
}

/// Τα στοιχεία που λείπουν για τον υπολογισμό, με τη σειρά που φαίνονται (κενό = όλα εντάξει).
List<String> missingForGoals({int? age, String? sex, double? heightCm, double? kg}) => [
      if (age == null) 'ηλικία',
      if (sex != 'm' && sex != 'f') 'φύλο',
      if (heightCm == null) 'ύψος',
      if (kg == null) 'βάρος',
    ];

int _round10(double v) => (v / 10).round() * 10;
int _round5(double v) => (v / 5).round() * 5;

/// Ο υπολογισμός. [rate]: ποσοστό του βάρους την εβδομάδα (0 για «ίδιο βάρος»).
GoalCalc computeGoals({
  required bool male,
  required int age,
  required double heightCm,
  required double kg,
  required GoalAim aim,
  required double rate,
  required double activity,
  required bool doctor,
}) {
  final bmr = 10 * kg + 6.25 * heightCm - 5 * age + (male ? 5 : -161);
  final tdee = bmr * activity;
  final perDay = kg * rate * kcalPerKg / 7;
  final delta = switch (aim) { GoalAim.lose => -perDay, GoalAim.keep => 0.0, GoalAim.gain => perDay };
  final floor = male ? kcalFloorMale : kcalFloorFemale;
  var kcal = _round10(tdee + delta);
  var floored = false;
  if (kcal < floor) {
    kcal = floor;
    floored = true;
  }
  final satPct = doctor ? 6 : 10;
  final protein = _round5(proteinPerKg * kg);
  return GoalCalc(
    bmr: bmr,
    tdee: tdee,
    delta: delta,
    kcal: kcal,
    floored: floored,
    protein: protein,
    fatLo: (kcal * 0.25 / 9).round(),
    fatHi: (kcal * 0.35 / 9).round(),
    satMax: (kcal * satPct / 100 / 9).round(),
    satPct: satPct,
    fiber: 30,
    salt: 5,
    carbsEst: math.max(0, ((kcal - protein * 4 - kcal * 0.30) / 4).round()),
  );
}

/// Γραμμάρια πίτουρου για [betaGlucanTarget] β-γλυκάνες, από όσα γράφει η συσκευασία (g β-γλυκανών ανά 100 g),
/// στρογγυλεμένα στα 5 προς τα πάνω (ώστε να φτάνει). null για άκυρη τιμή.
int? branGramsFor(double betaPer100) {
  if (betaPer100 <= 0 || betaPer100 > 40) return null;
  return ((betaGlucanTarget / betaPer100 * 100) / 5).ceil() * 5;
}

/// Οι αποθηκευμένοι στόχοι.
class Goals {
  Goals({
    required this.aim,
    required this.rate,
    required this.activity,
    required this.doctor,
    required this.since,
    required this.kg,
    required this.age,
    required this.heightCm,
    required this.male,
    this.nutsG = defaultNutsG,
    this.branG = defaultBranG,
    this.betaPer100,
    this.legumesWeek = defaultLegumesWeek,
    this.fishWeek = defaultFishWeek,
    this.kcalSet,
    this.proteinSet,
    this.kcalAdapt,
    this.tdeeEst,
    this.checkIn,
  });

  final GoalAim aim;
  final double rate;
  final double activity;

  /// Ο γιατρός ζήτησε να πέσει η LDL: κορεσμένα έως 6% και κάρτα «Χοληστερίνη».
  final bool doctor;

  /// Πότε φτιάχτηκαν («2026-11-16»).
  final String since;

  /// Τα στοιχεία με τα οποία υπολογίστηκαν (για το «Πώς υπολογίστηκε»).
  final double kg;
  final int age;
  final double heightCm;
  final bool male;

  final int nutsG;
  final int branG;

  /// Β-γλυκάνες ανά 100 g του πίτουρου του χρήστη (από την ετικέτα), αν τις έδωσε.
  final double? betaPer100;
  final int legumesWeek;
  final int fishWeek;

  /// Αν ο χρήστης άλλαξε με το χέρι τις θερμίδες ή την πρωτεΐνη.
  final int? kcalSet;
  final int? proteinSet;

  /// Ο στόχος από την αυτόματη διόρθωση (12/11), όταν πάτησες «Εφάρμοσε». Νικά τον τύπο, όχι τον δικό σου ([kcalSet]).
  final int? kcalAdapt;

  /// Η τελευταία εκτίμηση πραγματικής κατανάλωσης από τα δεδομένα σου (kcal τη μέρα).
  final double? tdeeEst;

  /// Ο τελευταίος εβδομαδιαίος έλεγχος («2026-12-07»), εφαρμόστηκε ή όχι.
  final String? checkIn;

  GoalCalc get calc => computeGoals(
      male: male, age: age, heightCm: heightCm, kg: kg, aim: aim, rate: rate, activity: activity, doctor: doctor);

  /// Ο στόχος θερμίδων που ισχύει (ο δικός σου, αν τον άλλαξες).
  int get kcal => kcalSet ?? kcalAdapt ?? calc.kcal;
  int get protein => proteinSet ?? calc.protein;

  /// Τα όρια που εξαρτώνται από τις θερμίδες ακολουθούν τον στόχο που ισχύει.
  int get fatLo => (kcal * 0.25 / 9).round();
  int get fatHi => (kcal * 0.35 / 9).round();
  int get satMax => (kcal * calc.satPct / 100 / 9).round();
  int get satPct => calc.satPct;
  int get fiber => calc.fiber;
  double get salt => calc.salt;

  Goals copyWith({
    int? nutsG,
    int? branG,
    double? betaPer100,
    int? legumesWeek,
    int? fishWeek,
    int? kcalSet,
    int? proteinSet,
    int? kcalAdapt,
    double? tdeeEst,
    String? checkIn,
    bool clearKcal = false,
    bool clearProtein = false,
    bool clearBeta = false,
    bool clearAdapt = false,
  }) =>
      Goals(
        aim: aim,
        rate: rate,
        activity: activity,
        doctor: doctor,
        since: since,
        kg: kg,
        age: age,
        heightCm: heightCm,
        male: male,
        nutsG: nutsG ?? this.nutsG,
        branG: branG ?? this.branG,
        betaPer100: clearBeta ? null : (betaPer100 ?? this.betaPer100),
        legumesWeek: legumesWeek ?? this.legumesWeek,
        fishWeek: fishWeek ?? this.fishWeek,
        kcalSet: clearKcal ? null : (kcalSet ?? this.kcalSet),
        proteinSet: clearProtein ? null : (proteinSet ?? this.proteinSet),
        kcalAdapt: clearAdapt ? null : (kcalAdapt ?? this.kcalAdapt),
        tdeeEst: clearAdapt ? null : (tdeeEst ?? this.tdeeEst),
        checkIn: checkIn ?? this.checkIn,
      );

  Map<String, dynamic> toJson() => {
        'v': 1,
        'aim': aim.name,
        'rate': rate,
        'pal': activity,
        'doc': doctor,
        'since': since,
        'kg': kg,
        'age': age,
        'h': heightCm,
        'm': male,
        'nuts': nutsG,
        'bran': branG,
        if (betaPer100 != null) 'beta': betaPer100,
        'leg': legumesWeek,
        'fish': fishWeek,
        if (kcalSet != null) 'kcal': kcalSet,
        if (proteinSet != null) 'prot': proteinSet,
        if (kcalAdapt != null) 'ka': kcalAdapt,
        if (tdeeEst != null) 'te': tdeeEst,
        if (checkIn != null) 'ci': checkIn,
      };

  /// null αν λείπει ή είναι άκυρο κάτι απαραίτητο (τότε η εφαρμογή ζητά ξανά τον οδηγό, αντί να δείξει λάθος αριθμούς).
  static Goals? fromJson(Object? j) {
    if (j is! Map) return null;
    double? d(Object? v) => v is num ? v.toDouble() : null;
    int? i(Object? v) => v is num ? v.toInt() : null;
    GoalAim? aim;
    for (final a in GoalAim.values) {
      if (a.name == j['aim']) aim = a;
    }
    final rate = d(j['rate']);
    final pal = d(j['pal']);
    final kg = d(j['kg']);
    final age = i(j['age']);
    final h = d(j['h']);
    final since = j['since'];
    if (aim == null || rate == null || pal == null || kg == null || age == null || h == null || since is! String) return null;
    // Μέρα σε μορφή «2026-11-16»· αλλιώς (π.χ. χαλασμένο αντίγραφο) ξανά ο οδηγός, όχι κόκκινη οθόνη (ανασκόπηση 11/11, S6).
    if (!isDayKey(since)) return null;
    if (rate < 0 || rate > 0.01 || pal < 1.2 || pal > 2.5 || kg < 30 || kg > 300 || age < 18 || age > 110 || h < 100 || h > 250) {
      return null;
    }
    int bounded(Object? v, int def, int lo, int hi) {
      final x = i(v);
      return x == null || x < lo || x > hi ? def : x;
    }

    final kcal = i(j['kcal']);
    final prot = i(j['prot']);
    final beta = d(j['beta']);
    final ka = i(j['ka']);
    final te = d(j['te']);
    final ci = j['ci'];
    return Goals(
      aim: aim,
      rate: rate,
      activity: pal,
      doctor: j['doc'] == true,
      since: since,
      kg: kg,
      age: age,
      heightCm: h,
      male: j['m'] != false,
      nutsG: bounded(j['nuts'], defaultNutsG, 0, 100),
      branG: bounded(j['bran'], defaultBranG, 0, 150),
      betaPer100: beta != null && beta > 0 && beta <= 40 ? beta : null,
      legumesWeek: bounded(j['leg'], defaultLegumesWeek, 0, 7),
      fishWeek: bounded(j['fish'], defaultFishWeek, 0, 7),
      kcalSet: kcal != null && kcal >= 1000 && kcal <= 6000 ? kcal : null,
      proteinSet: prot != null && prot >= 30 && prot <= 300 ? prot : null,
      kcalAdapt: ka != null && ka >= 1000 && ka <= 6000 ? ka : null,
      tdeeEst: te != null && te >= 800 && te <= 8000 ? te : null,
      checkIn: ci is String && isDayKey(ci) ? ci : null,
    );
  }
}

/// «0,4 kg την εβδομάδα» για έναν ρυθμό και βάρος.
String rateKgText(double kg, double rate) {
  final v = (kg * rate * 10).round() / 10;
  return '${v.toStringAsFixed(1).replaceAll('.', ',')} kg την εβδομάδα';
}

/// «0,5%»
String ratePctText(double rate) {
  final bp = (rate * 10000).round(); // εκατοστά του τοις εκατό: 25, 50, 75
  final s = bp % 100 == 0 ? '${bp ~/ 100}' : (bp % 10 == 0 ? (bp / 100).toStringAsFixed(1) : (bp / 100).toStringAsFixed(2));
  return '${s.replaceAll('.', ',')}%';
}

/// Ονόματα για τις οθόνες.
String aimText(GoalAim a) => switch (a) {
      GoalAim.lose => 'Λιγότερο λίπος',
      GoalAim.keep => 'Ίδιο βάρος',
      GoalAim.gain => 'Περισσότεροι μύες',
    };

String activityText(double pal) => pal <= 1.45 ? 'Λίγη κίνηση' : (pal <= 1.6 ? 'Μέτρια κίνηση' : 'Πολλή κίνηση');

String rateWord(GoalAim aim, double rate) {
  if (aim == GoalAim.keep) return '';
  final list = aim == GoalAim.lose ? loseRates : gainRates;
  final i = list.indexOf(rate);
  if (aim == GoalAim.lose) return const ['ήπια', 'μέτρια', 'γρήγορα'][i < 0 ? 1 : i];
  return const ['αργά', 'πιο γρήγορα'][i < 0 ? 0 : i];
}
