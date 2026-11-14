/// Στόχοι διατροφής (σχέδια 12/11, εγκρίθηκαν 11/11).
///
/// Ο οδηγός ρωτά: στόχο, ρυθμό, κίνηση, αν ο γιατρός ζήτησε να πέσει η LDL. Οι αριθμοί βγαίνουν ΜΟΝΟ από τους τύπους
/// με πηγή (καμία «εκτίμηση» από AI):
/// - Ξεκούραση: Mifflin-St Jeor (Mifflin 1990, AJCN).
/// - Κίνηση: επίπεδα σωματικής δραστηριότητας 1,53 / 1,65 / 1,76 (FAO/WHO/UNU 2004, κεφ. 5· [activityLevels]).
/// - Ρυθμός: ποσοστό του βάρους την εβδομάδα × 7.700 kcal/kg ÷ 7 (Hall 2008: προσέγγιση· Helms 2014: 0,5–1% για να
///   μένουν οι μύες· αύξηση 0,25–0,5%, Iraki 2019).
/// - Κάτω όριο: 1.500 kcal άνδρες, 1.200 γυναίκες: το λιγότερο που προτείνουν οι οδηγίες (Jensen 2013, AHA/ACC/TOS).
/// - Πρωτεΐνη 1,6 g/kg (Morton 2018, BJSM)· λίπος 25–35% (δική μας επιλογή μέσα στο εύρος 20–35% της EFSA 2010: έλεγχος
///   13/11, S1-12)· κορεσμένα έως 6% όταν ο γιατρός ζητά μείωση LDL (Eckel 2013, AHA/ACC: 5–6%), αλλιώς κάτω από 10%
///   (ΠΟΥ)· φυτικές ίνες 30 g (Reynolds 2019)· αλάτι κάτω από 5 g (ΠΟΥ).
///
/// Οι στόχοι αποθηκεύονται ΜΕ τους αριθμούς τους (και τα στοιχεία από τα οποία βγήκαν), ώστε η οθόνη «Πώς
/// υπολογίστηκε» να λέει ακριβώς τι ίσχυε και οι στόχοι να μην αλλάζουν σιωπηλά με κάθε ζύγιση.
library;

import 'dart:math' as math;

import 'format.dart' show dec, two;
import 'waist.dart' show isDayKey;

/// Τι θέλει ο χρήστης πρώτα.
enum GoalAim { lose, keep, gain }

/// Πόσο γρήγορα: ποσοστό του βάρους την εβδομάδα.
const loseRates = [0.0025, 0.005, 0.0075];
const gainRates = [0.0025, 0.005];

/// Κίνηση: επίπεδο σωματικής δραστηριότητας (PAL) για «Λίγο», «Μέτρια», «Πολύ». Round 9 (R9-A1-3, απόφαση της
/// 14/11/2026), από FAO/WHO/UNU 2004, Human energy requirements, κεφ. 5:
/// - «Λίγο» (γραφείο, λίγο περπάτημα, χωρίς προπόνηση) 1,53: το παράδειγμα «καθιστική ή ελαφριά δραστηριότητα» του
///   Πίνακα 5.1 (8 ώρες καθιστή δουλειά γραφείου, δουλειές του σπιτιού, ελαφριά αναψυχή).
/// - «Μέτρια» (γραφείο και 3–4 προπονήσεις ή περπατήματα την εβδομάδα) 1,65: η πηγή δεν δίνει παράδειγμα· παρεμβολή από
///   την §5.3.2: μία ώρα μέτρια ή έντονη άσκηση ΚΑΘΕ μέρα ανεβάζει το PAL από 1,55 σε 1,75, άρα 3–4 φορές την εβδομάδα
///   περίπου τα μισά (1,55 + 0,10 ≈ 1,65).
/// - «Πολύ» (δουλειά στο πόδι, ή άσκηση σχεδόν κάθε μέρα) 1,76: το παράδειγμα «δραστήρια ή μέτρια δραστήρια» του
///   Πίνακα 5.1 (8 ώρες όρθια δουλειά, περπάτημα και μία ώρα αερόβια άσκηση)· ίδιο με το 1,75 της §5.3.2.
/// Πριν: 1,4 / 1,5 / 1,7, πιο χαμηλά από τα παραδείγματα της ίδιας πηγής για τις ίδιες περιγραφές (το «Μέτρια» κάτω από
/// τον υπάλληλο γραφείου που δεν γυμνάζεται: στόχος ~170–260 kcal χαμηλά). Αποθηκευμένοι στόχοι κρατούν το επίπεδό τους
/// (οι αριθμοί δεν αλλάζουν σιωπηλά)· με «Ξανά ο οδηγός» η ίδια απάντηση παίρνει το νέο ([activityAnswer]).
const activityLevels = [1.53, 1.65, 1.76];

/// Round 9 (R9-A1-3): τα επίπεδα ως τις 14/11/2026, με την ίδια σειρά απαντήσεων («Λίγο», «Μέτρια», «Πολύ»).
const legacyActivityLevels = [1.4, 1.5, 1.7];

/// Round 9 (R9-A1-3): η απάντηση (0 «Λίγο», 1 «Μέτρια», 2 «Πολύ») ενός αποθηκευμένου επιπέδου, και με τα παλιά
/// ([legacyActivityLevels]). null: επίπεδο που δεν βγήκε από τον οδηγό.
int? activityAnswer(double pal) {
  final i = activityLevels.indexOf(pal);
  if (i >= 0) return i;
  final j = legacyActivityLevels.indexOf(pal);
  return j >= 0 ? j : null;
}

/// Round 9 (R9-A1-3): το επίπεδο της ίδιας απάντησης με τα τωρινά [activityLevels] (1,5 → 1,65)· άλλο επίπεδο μένει ίδιο.
double currentActivityLevel(double pal) {
  final i = activityAnswer(pal);
  return i == null ? pal : activityLevels[i];
}

/// «1,65», «1,5»: το επίπεδο όπως γράφεται στις οθόνες, με όσα δεκαδικά έχει (ως 2).
String palText(double pal) {
  final s = dec(pal, 2);
  return s.endsWith('0') ? dec(pal, 1) : s;
}

/// Ενέργεια ανά κιλό βάρους που χάνεται ή κερδίζεται (προσέγγιση, Hall 2008).
const kcalPerKg = 7700.0;

/// Κάτω όριο θερμίδων της εφαρμογής: το λιγότερο που προτείνουν οι οδηγίες AHA/ACC/TOS 2013 (Jensen 2013, σύσταση 3a:
/// 1.500–1.800 kcal τη μέρα για άνδρες, 1.200–1.500 για γυναίκες). Round 7 (R7-A1-4): δεν είναι όριο για την ασφάλεια·
/// η ίδια οδηγία ζητά ιατρική παρακολούθηση μόνο κάτω από 800 kcal τη μέρα (σύσταση 4e).
const kcalFloorMale = 1500;
const kcalFloorFemale = 1200;

/// Το κάτω όριο με τα λόγια της οδηγίας, για τις οθόνες (R7-A1-4): «το λιγότερο που προτείνουν οι οδηγίες για άνδρες».
String floorWhy(bool male) => 'το λιγότερο που προτείνουν οι οδηγίες για ${male ? 'άνδρες' : 'γυναίκες'}';

/// Πρωτεΐνη ανά κιλό (Morton 2018).
const proteinPerKg = 1.6;

/// Μέρα με «πλήρη καταγραφή»: τουλάχιστον αυτό το μέρος του στόχου θερμίδων. Λιγότερο σημαίνει σχεδόν πάντα ότι κάτι δεν
/// γράφτηκε. Ένας κανόνας παντού: διόρθωση θερμίδων και κάρτα «Χοληστερίνη» (τελικός έλεγχος, Συμβούλιο 2, Α4· πριν η
/// κάρτα είχε σταθερές 1.200 kcal, και με στόχο 1.200 μια μέρα με 1.150 kcal δεν μετρούσε ποτέ).
const fullDayShare = 0.6;

/// Προεπιλογές της κάρτας «Χοληστερίνη» από το «ιδανικό πλάνο» (10/11).
const defaultNutsG = 30;
const defaultBranG = 40;
const defaultLegumesWeek = 4;
const defaultFishWeek = 6;

/// β-γλυκάνες της βρώμης την ημέρα για τον ισχυρισμό της EFSA για τη χοληστερίνη.
const betaGlucanTarget = 3.0;

class GoalCalc {
  const GoalCalc({
    required this.kg,
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

  /// Το βάρος με το οποίο υπολογίστηκε (round 9, R9-A1-1: για το [keptKcalAdapt]).
  final double kg;

  /// Σε πλήρη ξεκούραση (Mifflin-St Jeor), kcal.
  final double bmr;

  /// Με την κίνηση (× επίπεδο), kcal.
  final double tdee;

  /// Για τον ρυθμό: αρνητικό για απώλεια, θετικό για αύξηση, kcal/ημέρα.
  final double delta;

  /// Ο στόχος, στρογγυλεμένος στα 10.
  final int kcal;

  /// Ο στόχος ανέβηκε στο κάτω όριο ([kcalFloorMale] / [kcalFloorFemale]).
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
    kg: kg,
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
    this.fastAt,
    this.foreignSeen,
    this.log = const [],
    this.docTargets = const DoctorTargets(),
    this.hist = const [],
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

  /// Πότε απάντησες τελευταία στην «γρήγορη απώλεια» (μία φορά την εβδομάδα).
  final String? fastAt;

  /// Η μέρα της τελευταίας «ξένης» ζύγισης που είδες στην κάρτα ελέγχου (έλεγχος 13/11, S11-2): η κάρτα δεν την ξαναγράφει.
  final String? foreignSeen;

  /// Οι εβδομαδιαίοι έλεγχοι με εκτίμηση και τα βήματα «γρήγορης απώλειας» που εφάρμοσες ([AdaptLog.fast]), παλιότερος
  /// πρώτος (για τη σελίδα «Στόχοι»). Το πολύ [adaptLogMax].
  final List<AdaptLog> log;

  /// Οι αριθμοί-στόχοι που έδωσε ο γιατρός (π.χ. LDL < 115), αν τους έγραψες. Μένουν στη διατροφή (απόφαση 12/11).
  final DoctorTargets docTargets;

  /// Round 9 (R9-A1-2): κάθε αλλαγή του στόχου θερμίδων που ισχύει ([kcal]), παλιότερη πρώτη, μία γραμμή ανά μέρα, το
  /// πολύ [targetHistMax]: από κάρτα («Εφάρμοσε»), «Θερμίδες τη μέρα» (δικός σου ή «από τον υπολογισμό»), «Ξανά ο οδηγός»
  /// και «Υπολόγισε ξανά» ([recordChangeFrom]). Από εδώ το [targetOn] ξέρει ποιος στόχος ίσχυε κάθε μέρα. Χωριστά από το
  /// [log]: ένας δικός σου στόχος δεν είναι «αλλαγή από κάρτα» (δεν κρατά πίσω τον εβδομαδιαίο έλεγχο για 4 μέρες), και
  /// το [log] κρατά μόνο τους [adaptLogMax] τελευταίους ελέγχους.
  final List<TargetChange> hist;

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

  /// Υδατάνθρακες «ό,τι μένει» με λίπος στο 30%, για τον στόχο θερμίδων που ισχύει (μόνο για ενημέρωση, όχι στόχος).
  int get carbsEst => math.max(0, ((kcal - protein * 4 - kcal * 0.30) / 4).round());

  /// Οι ίδιοι στόχοι με διορθωμένα στοιχεία από «Τα στοιχεία μου» (έλεγχος 13/11, S11-12): αλλάζουν μόνο το φύλο, η
  /// ηλικία και το ύψος του τύπου. Βάρος, ρυθμός, αρχή, ιστορικό και ο στόχος από τα δεδομένα σου μένουν· ένας στόχος
  /// (δικός σου ή από τα δεδομένα) που πέφτει κάτω από το κάτω όριο του νέου φύλου δεν ισχύει πια.
  Goals withProfile({required bool male, required int age, required double heightCm}) {
    final floor = male ? kcalFloorMale : kcalFloorFemale;
    final own = kcalSet, adapt = kcalAdapt;
    return Goals(
      aim: aim,
      rate: rate,
      activity: activity,
      doctor: doctor,
      since: since,
      kg: kg,
      age: age,
      heightCm: heightCm,
      male: male,
      nutsG: nutsG,
      branG: branG,
      betaPer100: betaPer100,
      legumesWeek: legumesWeek,
      fishWeek: fishWeek,
      kcalSet: own != null && own >= floor ? own : null,
      proteinSet: proteinSet,
      kcalAdapt: adapt != null && adapt >= floor ? adapt : null,
      tdeeEst: tdeeEst,
      checkIn: checkIn,
      fastAt: fastAt,
      foreignSeen: foreignSeen,
      log: log,
      docTargets: docTargets,
      hist: hist,
    );
  }

  /// Round 9 (R9-A1-2): οι ίδιοι στόχοι, με την αλλαγή του στόχου θερμίδων από τους [old] γραμμένη στο [hist] με μέρα
  /// [today] ([addTargetChange]). Το ιστορικό είναι πάντα των [old]. Χωρίς [old] (πρώτοι στόχοι) ή αν ο στόχος δεν
  /// άλλαξε, τίποτα νέο. Κάθε αλλαγή του στόχου που ισχύει περνά από εδώ πριν αποθηκευτεί.
  Goals recordChangeFrom(Goals? old, DateTime today) {
    final o = old;
    if (o == null) return this;
    final before = o.kcal, after = kcal;
    final day = '${today.year}-${two(today.month)}-${two(today.day)}';
    return copyWith(
        hist: before == after
            ? o.hist
            : addTargetChange(o.hist, o.log, TargetChange(day: day, before: before, after: after)));
  }

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
    String? fastAt,
    String? foreignSeen,
    AdaptLog? addLog,
    DoctorTargets? docTargets,
    List<TargetChange>? hist,
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
        fastAt: fastAt ?? this.fastAt,
        foreignSeen: foreignSeen ?? this.foreignSeen,
        log: addLog == null
            ? log
            : [
                for (final l in log)
                  if (l.day != addLog.day) l,
                addLog,
              ].reversed.take(adaptLogMax).toList().reversed.toList(),
        docTargets: docTargets ?? this.docTargets,
        hist: hist ?? this.hist,
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
        if (fastAt != null) 'fa': fastAt,
        if (foreignSeen != null) 'fw': foreignSeen,
        if (log.isNotEmpty) 'log': [for (final l in log) l.toJson()],
        ...docTargets.toJson(),
        // R9-A1-2: προσθετικό κλειδί· μια παλιότερη έκδοση το αγνοεί.
        if (hist.isNotEmpty) 'th': [for (final h in hist) h.toJson()],
      };

  /// null αν λείπει ή είναι άκυρο κάτι απαραίτητο (τότε η εφαρμογή ζητά ξανά τον οδηγό, αντί να δείξει λάθος αριθμούς).
  static Goals? fromJson(Object? j) {
    if (j is! Map) return null;
    // Έλεγχος 13/11 (S1-7): «1e999» σε πειραγμένο ή χαλασμένο αντίγραφο γίνεται «άπειρο» και το toInt() πετά σφάλμα· οι
    // στόχοι διαβάζονται σε κάθε οθόνη. Ό,τι δεν είναι πεπερασμένος αριθμός διαβάζεται σαν να λείπει (ίδιος κανόνας με το
    // Profile.fromJson).
    double? d(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
    int? i(Object? v) => v is num && v.isFinite ? v.toInt() : null;
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
    // Τελικός έλεγχος (Συμβούλιο 2, μ2): και το φύλο είναι απαραίτητο. Πριν, αν έλειπε ή ήταν χαλασμένο (π.χ. αντίγραφο
    // πειραγμένο με το χέρι), διαβαζόταν σιωπηλά «άνδρας»: +166 kcal στον τύπο και κάτω όριο 1.500 αντί για 1.200 για
    // μια γυναίκα. Τώρα, όπως για κάθε άλλο απαραίτητο στοιχείο, η εφαρμογή ζητά ξανά τον οδηγό.
    final male = j['m'];
    if (male is! bool) return null;
    // Τελικός έλεγχος (Συμβούλιο 2, μ6): αποθηκευμένος στόχος θερμίδων κάτω από το κάτω όριο δεν ισχύει ποτέ. Η εφαρμογή
    // δεν γράφει τέτοιον (η οθόνη «Θερμίδες τη μέρα» και ο εβδομαδιαίος έλεγχος σταματούν στο όριο)· μόνο ένα αντίγραφο
    // πειραγμένο με το χέρι μπορεί. Τότε ισχύει ο υπολογισμός, που είναι πάντα στο όριο ή πάνω από αυτό.
    final kcalFloor = male ? kcalFloorMale : kcalFloorFemale;
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
    final fa = j['fa'];
    final fw = j['fw'];
    final rawLog = j['log'];
    final rawHist = j['th'];
    // R9-A1-2: χωρίς το κλειδί (στόχοι από παλιότερη έκδοση), άδειο. Άκυρες γραμμές δεν διαβάζονται· από μεγαλύτερη λίστα
    // (μόνο πειραγμένο αντίγραφο) μένουν οι πιο πρόσφατες.
    final hist = rawHist is List ? rawHist.map(TargetChange.fromJson).whereType<TargetChange>().toList() : <TargetChange>[];
    return Goals(
      aim: aim,
      rate: rate,
      activity: pal,
      doctor: j['doc'] == true,
      since: since,
      kg: kg,
      age: age,
      heightCm: h,
      male: male,
      nutsG: bounded(j['nuts'], defaultNutsG, 0, 100),
      branG: bounded(j['bran'], defaultBranG, 0, 150),
      betaPer100: beta != null && beta > 0 && beta <= 40 ? beta : null,
      legumesWeek: bounded(j['leg'], defaultLegumesWeek, 0, 7),
      fishWeek: bounded(j['fish'], defaultFishWeek, 0, 7),
      kcalSet: kcal != null && kcal >= kcalFloor && kcal <= 6000 ? kcal : null,
      proteinSet: prot != null && prot >= 30 && prot <= 300 ? prot : null,
      kcalAdapt: ka != null && ka >= kcalFloor && ka <= 6000 ? ka : null,
      tdeeEst: te != null && te >= 800 && te <= 8000 ? te : null,
      checkIn: ci is String && isDayKey(ci) ? ci : null,
      fastAt: fa is String && isDayKey(fa) ? fa : null,
      foreignSeen: fw is String && isDayKey(fw) ? fw : null,
      log: rawLog is List ? rawLog.map(AdaptLog.fromJson).whereType<AdaptLog>().take(adaptLogMax).toList() : const [],
      docTargets: DoctorTargets.fromJson(j),
      hist: hist.length > targetHistMax ? hist.sublist(hist.length - targetHistMax) : hist,
    );
  }
}

const adaptLogMax = 26;

/// Round 9 (R9-A1-2): το πολύ τόσες γραμμές στο [Goals.hist]. Μία ανά μέρα ([addTargetChange]): με μία αλλαγή την
/// εβδομάδα φτάνουν για περίπου 7½ χρόνια (περίπου 40 bytes η καθεμία).
const targetHistMax = 400;

/// Round 9 (R9-A1-2): μια αλλαγή του στόχου θερμίδων που ισχύει: μέρα, στόχος πριν και μετά.
class TargetChange {
  const TargetChange({required this.day, required this.before, required this.after});
  final String day;
  final int before, after;

  Map<String, dynamic> toJson() => {'d': day, 'k0': before, 'k1': after};

  static TargetChange? fromJson(Object? j) {
    if (j is! Map) return null;
    final d = j['d'], k0 = j['k0'], k1 = j['k1'];
    if (d is! String || !isDayKey(d) || k0 is! num || k1 is! num) return null;
    // Ευρύτερα όρια από το [AdaptLog]: και ο στόχος από τον τύπο ενός πολύ βαρύ ανθρώπου με πολλή κίνηση γράφεται.
    if (k0 < 500 || k0 > 20000 || k1 < 500 || k1 > 20000) return null;
    return TargetChange(day: d, before: k0.toInt(), after: k1.toInt());
  }
}

/// Round 9 (R9-A1-2): το [hist] με την αλλαγή [c] στο τέλος.
/// - Άδειο [hist] (στόχοι από παλιότερη έκδοση): ξεκινά με τις αλλαγές από κάρτα του [log] («Εφάρμοσε»), τις ίδιες που
///   διάβαζε ως τότε το [targetOn], ώστε το ιστορικό να είναι πλήρες από εκεί και πέρα.
/// - Δεύτερη αλλαγή την ίδια μέρα: μία γραμμή (ο στόχος στην αρχή της μέρας → ο τελευταίος). Μένει και όταν ο στόχος
///   γύρισε εκεί που ήταν (π.χ. 2.250 → 2.250): λέει σωστά τον στόχο εκείνης της μέρας, και το ιστορικό δεν ξαναγίνεται
///   άδειο (αλλιώς θα διαβαζόταν ξανά σαν στόχοι παλιότερης έκδοσης, από το [log]).
/// - Το πολύ [targetHistMax] γραμμές: φεύγουν οι παλιότερες.
List<TargetChange> addTargetChange(List<TargetChange> hist, List<AdaptLog> log, TargetChange c) {
  final out = hist.isNotEmpty
      ? [...hist]
      : [
          for (final l in log)
            if (l.applied) TargetChange(day: l.day, before: l.before, after: l.after),
        ];
  if (out.isNotEmpty && out.last.day == c.day) {
    final first = out.removeLast();
    out.add(TargetChange(day: c.day, before: first.before, after: c.after));
  } else {
    out.add(c);
  }
  return out.length > targetHistMax ? out.sublist(out.length - targetHistMax) : out;
}

/// Στόχοι του γιατρού για τα λιπίδια (mg/dL), όπως τους έγραψε στο χαρτί του. null = δεν έδωσε.
class DoctorTargets {
  const DoctorTargets({this.ldlMax, this.hdlMin, this.tgMax});
  final int? ldlMax, hdlMin, tgMax;

  bool get isEmpty => ldlMax == null && hdlMin == null && tgMax == null;

  /// Όρια για ό,τι γράφεται (mg/dL): έξω από αυτά σχεδόν σίγουρα είναι λάθος πληκτρολόγησης ή άλλη μονάδα.
  static const ldlRange = (30, 250), hdlRange = (20, 120), tgRange = (50, 500);

  /// «LDL < 115 · HDL > 50 · Τριγλυκερίδια < 150»
  String get text => [
        if (ldlMax != null) 'LDL < $ldlMax',
        if (hdlMin != null) 'HDL > $hdlMin',
        if (tgMax != null) 'Τριγλυκερίδια < $tgMax',
      ].join(' ·\u00A0');

  Map<String, dynamic> toJson() => {
        if (ldlMax != null) 'ldl': ldlMax,
        if (hdlMin != null) 'hdl': hdlMin,
        if (tgMax != null) 'tg': tgMax,
      };

  static DoctorTargets fromJson(Map j) {
    int? v(Object? x, (int, int) r) => x is num && x >= r.$1 && x <= r.$2 ? x.toInt() : null;
    return DoctorTargets(ldlMax: v(j['ldl'], ldlRange), hdlMin: v(j['hdl'], hdlRange), tgMax: v(j['tg'], tgRange));
  }
}

/// Ένας εβδομαδιαίος έλεγχος με εκτίμηση: μέρα, πόσο καις, στόχος πριν και μετά, αν τον εφάρμοσες.
/// Με [fast]: βήμα της κάρτας «γρήγορη απώλεια» που εφάρμοσες (έλεγχος 13/11, S1-3 / S1-6). Τότε δεν υπάρχει εκτίμηση
/// εκείνης της μέρας: το [tdee] είναι το πάνω όριο που ίσχυε (η τελευταία εκτίμηση, αλλιώς ο τύπος) και δεν δείχνεται ως
/// «πόσο καις»· γράφεται για να διαβάζει τη γραμμή και μια παλιότερη έκδοση της εφαρμογής.
/// Με [lowLog] (round 7, R7-A1-1): εβδομαδιαίος έλεγχος όπου η εκτίμηση βγήκε πολύ χαμηλή (λείπει φαγητό από το
/// ημερολόγιο) και ο στόχος κατέβηκε (ή προτάθηκε να κατέβει) από τη ζυγαριά. Ούτε τότε υπάρχει εκτίμηση: το [tdee]
/// γράφεται όπως στο [fast] και δεν δείχνεται. Κλειδί «lo», μόνο όταν ισχύει (μια παλιότερη έκδοση το αγνοεί).
class AdaptLog {
  const AdaptLog({
    required this.day,
    required this.tdee,
    required this.before,
    required this.after,
    required this.applied,
    this.fast = false,
    this.lowLog = false,
  });
  final String day;
  final double tdee;
  final int before, after;
  final bool applied;
  final bool fast;
  final bool lowLog;

  Map<String, dynamic> toJson() =>
      {'d': day, 'te': tdee, 'k0': before, 'k1': after, if (applied) 'ap': true, if (fast) 'f': true, if (lowLog) 'lo': true};

  static AdaptLog? fromJson(Object? j) {
    if (j is! Map) return null;
    final d = j['d'], te = j['te'], k0 = j['k0'], k1 = j['k1'];
    if (d is! String || !isDayKey(d) || te is! num || k0 is! num || k1 is! num) return null;
    if (te < 800 || te > 8000 || k0 < 1000 || k0 > 6000 || k1 < 1000 || k1 > 6000) return null;
    return AdaptLog(
        day: d,
        tdee: te.toDouble(),
        before: k0.toInt(),
        after: k1.toInt(),
        applied: j['ap'] == true,
        fast: j['f'] == true,
        lowLog: j['lo'] == true);
  }
}

/// «0,45 kg την εβδομάδα» για έναν ρυθμό και βάρος. Με δύο δεκαδικά (έλεγχος 13/11, S1-8 / U3b-1): με ένα, τα 0,45 kg
/// γράφονταν «0,5 kg» δίπλα σε θερμίδες που βγαίνουν από 0,45, και οι τρεις ρυθμοί έμοιαζαν άνισοι (0,2 · 0,5 · 0,7).
String rateKgText(double kg, double rate) => '${dec(kg * rate, 2)} kg την εβδομάδα';

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

/// Round 9 (R9-A1-3): η απάντηση του οδηγού ([activityAnswer]: και τα παλιά 1,4 / 1,5 / 1,7 λέγονται όπως τα είχες
/// διαλέξει)· άλλο επίπεδο, με τα μέσα ανάμεσα στα τωρινά (1,59 και 1,705).
String activityText(double pal) {
  final i = activityAnswer(pal) ?? (pal < 1.59 ? 0 : (pal < 1.705 ? 1 : 2));
  return const ['Λίγη κίνηση', 'Μέτρια κίνηση', 'Πολλή κίνηση'][i];
}

String rateWord(GoalAim aim, double rate) {
  if (aim == GoalAim.keep) return '';
  final list = aim == GoalAim.lose ? loseRates : gainRates;
  final i = list.indexOf(rate);
  if (aim == GoalAim.lose) return const ['ήπια', 'μέτρια', 'γρήγορα'][i < 0 ? 1 : i];
  return const ['αργά', 'πιο γρήγορα'][i < 0 ? 0 : i];
}
