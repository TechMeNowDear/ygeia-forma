/// Ημερήσιες συνόψεις: μία εγγραφή ανά μέρα, για Τάσεις και απολογισμούς.
///
/// Υπολογίζονται από τα ίδια δεδομένα και με τους ίδιους κανόνες με τις οθόνες
/// (νύχτες, παλμοί ημέρας), ώστε τα νούμερα να συμφωνούν παντού.
library;

import 'data.dart';
import 'format.dart';
import 'heart_day.dart';
import 'sources.dart';

/// Κλειδιά συνόψεων (σταθερά: αποθηκεύονται στη βάση).
abstract final class K {
  static const sleepMin = 'sleepMin';
  static const sleepScore = 'sleepScore';
  static const deepPct = 'deepPct';
  static const remPct = 'remPct';
  static const awakeMin = 'awakeMin';
  static const bedtime = 'bedtime'; // λεπτά μετά τις 18:00
  static const wake = 'wake'; // λεπτά μετά τις 18:00
  static const sleepHr = 'sleepHr';
  static const spo2Avg = 'spo2Avg';
  static const spo2Min = 'spo2Min';
  /// Λεπτά με οξυγόνο κάτω από 90% (ενδεικτικό· μόνο όταν βγαίνει από τις αναλυτικές μετρήσεις).
  static const spo2Low = 'spo2Low';

  /// Κάλυψη του οξυγόνου του ρολογιού σε νύχτα του Oura (0–1): πόσο από τις ώρες ύπνου του Oura έχουν μετρήσεις
  /// οξυγόνου ≥ 60″ από το ρολόι. Η χαμηλότερη τιμή φαίνεται μόνο με κάλυψη ≥ [spo2MinCoverage] (απόφαση 7/11).
  static const spo2Cov = 'spo2Cov';

  /// Μέσος όρος οξυγόνου της νύχτας από το Oura (daily_spo2), αποθηκεύεται ως «o.spo2».
  static const ringSpo2 = 'ringSpo2';
  static const skinTemp = 'skinTemp';
  static const restHr = 'restHr';
  static const dayHr = 'dayHr';
  static const walkHr = 'walkHr';
  static const steps = 'steps';
  static const activeMin = 'activeMin';
  static const calories = 'calories';
  static const energy = 'energy';
  static const weight = 'weight';
  static const fatPct = 'fatPct';
  static const smm = 'smm';

  /// Έλεγχος 3, E2: σημάδι ότι οι τιμές ζύγισης της μέρας ήρθαν από την InBody (1). Ζύγιση χωρίς σημάδι = από παλιά
  /// έκδοση, ίσως από άλλη εφαρμογή (χειροκίνητο βάρος, BIA του ρολογιού): ΠΟΤΕ δεν σβήνεται· από την πρώτη ζύγιση
  /// InBody και μετά απλώς δεν φαίνεται ([SourcePlan.scaleFrom]).
  static const inbody = 'inbody';
  static const floors = 'floors';
  /// Υπνάκοι: του ρολογιού ως «napMin» (C1: βραδινό λαγοκοίμισμα, πρωινός και απογευματινός υπνάκος), του Oura ως
  /// «o.napMin». Δεν μετρούν ποτέ στη διάρκεια της νύχτας.
  static const napMin = 'napMin';

  /// Έλεγχος 3, E1.6: η απόφαση «πρωινός υπνάκος» της νύχτας, παρμένη με βήματα (λεπτά από την εποχή Unix: η αρχή του
  /// κομματιού που έγινε υπνάκος). Δεν είναι μέτρηση και δεν φαίνεται· κρατά την απόφαση ίδια όταν τα βήματα ανά λεπτό
  /// δεν υπάρχουν πια (ρολόι: «napLock», Oura: «o.napLock»).
  static const napLock = 'napLock';
  // Μόνο από το Oura (αποθηκεύονται με πρόθεμα «o.», δες sources.dart).
  static const lowHr = 'lowHr';
  static const hrv = 'hrv';
  static const breath = 'breath';
}

/// Τιμές που βγαίνουν από τον ύπνο μιας νύχτας.
const sleepKeys = {
  K.sleepMin, K.sleepScore, K.deepPct, K.remPct, K.awakeMin, K.bedtime, K.wake,
  K.sleepHr, K.spo2Avg, K.spo2Min, K.spo2Low, K.spo2Cov, K.skinTemp, K.napMin, K.napLock,
};

/// Έκδοση των κανόνων του ιστορικού. Όταν αλλάζει, οι τιμές ύπνου ξαναϋπολογίζονται από την αρχή.
/// 2 (1/11): η «εκτίμηση» στα κενά δεν μετρά στη διάρκεια· σπασμένη νύχτα χωρίς βαθμολογία·
/// διπλές εγγραφές δεν αθροίζονται.
/// 3 (4/11, έλεγχος): οξυγόνο που είχε σβηστεί από ζυγίσεις σε μέρες του Oura (A1) ξαναδιαβάζεται· μόνο ρολόι
/// για ύπνο/παλμούς/οξυγόνο/θερμοκρασία (A2)· οξυγόνο με στάθμιση διάρκειας (A4)· λαγοκοίμισμα με βήματα
/// χωριστά από τη νύχτα (A6)· διάρκεια ύπνου του ρολογιού = πραγματικός ύπνος από τις φάσεις, χωρίς τα ξυπνήματα
/// (στοιχεία της Samsung για τη νύχτα 2→3/11: «Πραγματικός ύπνος» ≠ «Χρόνος ύπνου»)· ποσοστά σταδίων επί του
/// πραγματικού ύπνου, χωρίς τα ξυπνήματα (B4). Μία αλλαγή έκδοσης καλύπτει και τα δύο (η έκδοση 2 είναι η τελευταία
/// που κυκλοφόρησε), άρα μία πλήρης επανανάγνωση.
/// 4 (4/11, τελικός έλεγχος): νύχτα με όλο τον ύπνο μετά τις 08:00 (π.χ. 08:28–12:54) δεν χάνεται πια (κύρια ομάδα
/// 1β στο [groupSleepPieces]). Μια επανανάγνωση v3 σε εξέλιξη ξεκινά από την αρχή ως v4 (τίποτα δεν σβήνεται).
const historyRulesVersion = 4;

/// Τιμές από τους παλμούς (ύπνου και μέρας): αν η ανάγνωση των παλμών απέτυχε ή κόπηκε, οι παλιές μένουν (A12).
const heartKeys = {K.sleepHr, K.restHr, K.dayHr, K.walkHr};

/// Παλμοί της μέρας (χωρίς τους παλμούς του ύπνου).
const dayHeartKeys = {K.restHr, K.dayHr, K.walkHr};

/// Έλεγχος 2, C12: οι παλμοί της μέρας [day] δεν βγαίνουν επειδή λείπει η νύχτα του Oura (της ίδιας ή της επόμενης
/// μέρας, ως [today]) που ορίζει τις ώρες ύπνου ([_heartWithPlan]).
bool dayHeartNeedsMissingWindow(SourcePlan plan, SleepWindows windows, DateTime day, DateTime today) {
  for (final n in [dayOf(day), DateTime(day.year, day.month, day.day + 1)]) {
    if (n.isAfter(today)) continue;
    if (plan.nightSource(n) == Source.oura && !windows.mains.containsKey(dateKey(n))) return true;
  }
  return false;
}

/// Οξυγόνο της νύχτας (πάντα του ρολογιού).
const spo2Keys = {K.spo2Avg, K.spo2Min, K.spo2Low, K.spo2Cov};

/// Βάζει νέες συνόψεις στο [history] και επιστρέφει τις μέρες που άλλαξαν (για αποθήκευση).
///
/// Ο ύπνος κρίνεται με βήματα ανά λεπτό (κενά ανάμεσα στα κομμάτια). Για να έχει **ένα** ορισμό
/// όλο το ιστορικό, οι τιμές ύπνου μιας μέρας γράφονται μόνο όταν υπολογίστηκαν με βήματα:
/// - [sleepFrom]: από αυτή τη μέρα και μετά οι τιμές ύπνου αντικαθίστανται.
/// - πριν από αυτήν (ή αν είναι null): γράφονται μόνο αν η μέρα δεν έχει καθόλου τιμές ύπνου.
/// - [replaceSleep] true: όλες οι τιμές ύπνου των ημερών στο [rangeFrom, rangeTo] αντικαθίστανται
///   (ξαναϋπολογισμός ιστορικού με βήματα), και όσες δεν υπάρχουν πια σβήνονται.
///
/// [plan]: τις μέρες που η «νύχτα» ΔΕΝ έρχεται από το ρολόι (Oura ή καμία πηγή), οι τιμές νύχτας του
/// ρολογιού δεν γράφονται ποτέ (και όσες υπήρχαν φεύγουν)· μένει μόνο το οξυγόνο, που είναι πάντα του ρολογιού.
/// Οι τιμές του Oura («o.*») δεν αγγίζονται εδώ (δες [mergeOura]).
/// [keepKeys]: τιμές που ΔΕΝ αλλάζουν σε αυτή την ανάγνωση (π.χ. [heartKeys] όταν οι παλμοί δεν διαβάστηκαν):
/// οι παλιές μένουν, οι νέες δεν γράφονται.
/// [ouraNights]: οι μέρες που ξέρουμε τις ώρες της νύχτας του Oura. Το οξυγόνο μιας νύχτας του Oura βγαίνει μόνο
/// μέσα σε αυτές· για μέρα χωρίς γνωστές ώρες (π.χ. το αρχείο νυχτών δεν διαβάστηκε) το αποθηκευμένο οξυγόνο
/// ΜΕΝΕΙ (δεν σβήνεται επειδή λείπουν οι ώρες). null = όλες γνωστές.
Set<String> mergeHistory(
  Map<String, Map<String, double>> history,
  Map<String, Map<String, double>> rows, {
  DateTime? sleepFrom,
  bool replaceSleep = false,
  DateTime? rangeFrom,
  DateTime? rangeTo,
  SourcePlan? plan,
  Set<String> keepKeys = const {},
  Set<String>? ouraNights,
}) {
  final changed = <String>{};
  final p = plan ?? SourcePlan.samsungOnly;
  // Τιμές που μένουν όπως είναι τη μέρα [day].
  Set<String> kept(DateTime day) {
    final foreign = p.nightSource(day) != Source.watch;
    final noWindow = foreign && ouraNights != null && !ouraNights.contains(dateKey(day));
    return noWindow ? {...keepKeys, ...spo2Keys} : keepKeys;
  }

  // Επανανάγνωση (C3): μια αποθηκευμένη διάρκεια ύπνου νύχτας του ρολογιού δεν σβήνεται ποτέ αν δεν έρθει έγκυρη νέα
  // στη θέση της (π.χ. η νύχτα ήρθε τώρα χωρίς φάσεις ή με άγνωστες φάσεις): ένας μετρημένος ύπνος δεν χάνεται.
  bool keepDuration(DateTime day, String key) =>
      replaceSleep &&
      key == K.sleepMin &&
      p.nightSource(day) == Source.watch &&
      !(rows[dateKey(day)]?.containsKey(K.sleepMin) ?? false);

  // Review M3: η απόφαση «πρωινός υπνάκος» μιας νύχτας του ρολογιού αλλάζει μόνο όταν η νύχτα ξανακριθεί (έγκυρη νέα
  // διάρκεια)· μια ανάγνωση χωρίς νύχτα δεν τη σβήνει.
  bool keepLock(DateTime day, String key) =>
      key == K.napLock && p.nightSource(day) == Source.watch && !(rows[dateKey(day)]?.containsKey(K.sleepMin) ?? false);

  if (replaceSleep && rangeFrom != null && rangeTo != null) {
    for (var day = dayOf(rangeFrom); !day.isAfter(dayOf(rangeTo)); day = DateTime(day.year, day.month, day.day + 1)) {
      final k = dateKey(day);
      final old = history[k];
      if (old == null) continue;
      // Η νύχτα του ρολογιού την πρώτη μέρα μιας εποχής Oura δεν σβήνεται ποτέ ([SourcePlan.keepsWatchNight]).
      final keep = p.keepsWatchNight(day);
      final stay = kept(day);
      bool drop(String key) =>
          sleepKeys.contains(key) &&
          !stay.contains(key) &&
          !(keep && watchNightKeys.contains(key)) &&
          !keepDuration(day, key) &&
          !keepLock(day, key);
      if (old.keys.any(drop)) {
        history[k] = {for (final e in old.entries) if (!drop(e.key)) e.key: e.value};
        changed.add(k);
      }
    }
  }
  for (final e in rows.entries) {
    final day = parseDateKey(e.key);
    final old = history[e.key] ?? const <String, double>{};
    // Μέρα που η νύχτα δεν είναι του ρολογιού: οι τιμές νύχτας του ρολογιού δεν μπαίνουν ποτέ, και το
    // οξυγόνο (το μόνο του ρολογιού εδώ, χωρίς ομαδοποίηση ύπνου) ανανεώνεται πάντα.
    final foreignNight = p.nightSource(day) != Source.watch;
    final keep = p.keepsWatchNight(day);
    final stay = kept(day);
    final row = {
      for (final v in e.value.entries)
        if (!(foreignNight && watchNightKeys.contains(v.key)) && !stay.contains(v.key)) v.key: v.value,
    };
    // Το οξυγόνο τέτοιων ημερών δεν θέλει βήματα ανά λεπτό: ανανεώνεται σε κάθε αξιόπιστη ανάγνωση
    // (όχι όταν απέτυχε κάποιο είδος του ύπνου, που τότε το [sleepFrom] είναι null).
    final trusted = replaceSleep || sleepFrom != null;
    final overwriteSleep = replaceSleep || (sleepFrom != null && !day.isBefore(dayOf(sleepFrom))) || (foreignNight && trusted);
    final keepOldSleep = !overwriteSleep && old.keys.any(sleepKeys.contains);
    final incoming = keepOldSleep
        ? {for (final v in row.entries) if (!sleepKeys.contains(v.key)) v.key: v.value}
        : row;
    final base = overwriteSleep
        ? {
            for (final v in old.entries)
              if ((keep && watchNightKeys.contains(v.key)) ||
                  keepDuration(day, v.key) ||
                  keepLock(day, v.key) ||
                  (stay.contains(v.key) && !(foreignNight && watchNightKeys.contains(v.key))) ||
                  (!sleepKeys.contains(v.key) && !(foreignNight && watchNightKeys.contains(v.key))))
                v.key: v.value,
          }
        : old;
    final next = {...base, ...incoming};
    // Review L1: ήρθε έγκυρη νύχτα του ρολογιού για μέρα σημειωμένη «από άλλη συσκευή»: το σημάδι φεύγει.
    if (incoming.containsKey(K.sleepMin)) next.remove(otherDeviceKey);
    // Μόνο ό,τι άλλαξε γράφεται ξανά στο κινητό.
    if (!_sameValues(history[e.key], next)) changed.add(e.key);
    history[e.key] = next;
  }
  return changed;
}

/// Βάζει τις τιμές του Oura ([rows], κλειδιά «o.*») για τις μέρες [from, to] και επιστρέφει όσες άλλαξαν.
/// Μια μέρα που ήρθε στην απάντηση αντικαθίσταται όλη (οι τιμές «o.*» της). Μια μέρα που ΔΕΝ ήρθε δεν σβήνεται
/// ποτέ (έλεγχος 4/11, A3): η Oura μπορεί να μη στείλει μια νύχτα (καθυστέρηση συγχρονισμού, όριο ημερομηνιών)
/// και μια μετρημένη νύχτα δεν χάνεται γι' αυτό.
/// Γράφονται μόνο οι μέρες που η «νύχτα» έρχεται από το Oura· οι άλλες αγνοούνται.
Set<String> mergeOura(
  Map<String, Map<String, double>> history,
  Map<String, Map<String, double>> rows, {
  required DateTime from,
  required DateTime to,
  required SourcePlan plan,
}) {
  final changed = <String>{};
  for (var day = dayOf(from); !day.isAfter(dayOf(to)); day = DateTime(day.year, day.month, day.day + 1)) {
    if (plan.nightSource(day) != Source.oura) continue;
    final k = dateKey(day);
    if (!rows.containsKey(k)) continue;
    final old = history[k] ?? const <String, double>{};
    final row = rows[k] ?? const <String, double>{};
    final next = {
      for (final v in old.entries) if (!ouraKeySet.contains(v.key)) v.key: v.value,
      // Το οξυγόνο του Oura έρχεται χωριστά (άδεια spo2): απάντηση χωρίς αυτό δεν σβήνει το αποθηκευμένο.
      if (!row.containsKey(ouraSpo2Key) && old[ouraSpo2Key] != null) ouraSpo2Key: old[ouraSpo2Key]!,
      for (final v in row.entries)
        if (ouraKeySet.contains(v.key) && v.value.isFinite) v.key: v.value,
    };
    if (next.isEmpty && history[k] == null) continue;
    if (!_sameValues(history[k], next)) changed.add(k);
    history[k] = next;
  }
  return changed;
}

/// Σβήνει τις τιμές νύχτας του ρολογιού από τις μέρες (από [from] και μετά) που η νύχτα έχει άλλη πηγή.
/// Εξαίρεση: η πρώτη νύχτα μιας εποχής Oura ([SourcePlan.keepsWatchNight]) — αν το ρολόι την είχε ήδη γράψει,
/// μένει (κρυφή).
Set<String> stripForeignWatchNight(Map<String, Map<String, double>> history, SourcePlan plan, {required DateTime from}) {
  final changed = <String>{};
  final fromKey = dateKey(from);
  for (final e in history.entries.toList()) {
    // Τα κλειδιά «2026-11-06» ταξινομούνται σαν ημερομηνίες: οι παλιές μέρες προσπερνιούνται χωρίς ανάλυση.
    if (e.key.compareTo(fromKey) < 0) continue;
    final day = parseDateKey(e.key);
    if (plan.nightSource(day) == Source.watch || plan.keepsWatchNight(day)) continue;
    if (!e.value.keys.any(watchNightKeys.contains)) continue;
    history[e.key] = {for (final v in e.value.entries) if (!watchNightKeys.contains(v.key)) v.key: v.value};
    changed.add(e.key);
  }
  return changed;
}

/// Έλεγχος 2, C11: μετά από αλλαγή σχεδίου πηγών εκ των υστέρων (επαναφορά αντιγράφου, ανάκτηση), στις μέρες που η
/// «νύχτα» άλλαξε από ρολόι σε άλλη πηγή ή αντίστροφα, οι τιμές με ορισμό που εξαρτάται από την πηγή της νύχτας
/// ([definitionMetrics]: οξυγόνο νύχτας, παλμοί μέρας) σβήνονται, ώστε να ξαναϋπολογιστούν (ποτέ δύο ορισμοί σε ένα
/// κομμάτι). Επιστρέφει τις μέρες που άλλαξαν.
Set<String> stripChangedDefinitions(Map<String, Map<String, double>> history, SourcePlan before, SourcePlan after) {
  final changed = <String>{};
  for (final e in history.entries.toList()) {
    final day = parseDateKey(e.key);
    final was = before.nightSource(day) == Source.watch;
    final now = after.nightSource(day) == Source.watch;
    // Και η νύχτα της επόμενης μέρας μετρά για τους παλμούς της μέρας (ο ύπνος του βραδιού).
    final next = DateTime(day.year, day.month, day.day + 1);
    final wasNext = before.nightSource(next) == Source.watch;
    final nowNext = after.nightSource(next) == Source.watch;
    if (was == now && wasNext == nowNext) continue;
    if (!e.value.keys.any(definitionMetrics.contains)) continue;
    history[e.key] = {for (final v in e.value.entries) if (!definitionMetrics.contains(v.key)) v.key: v.value};
    changed.add(e.key);
  }
  return changed;
}

/// Έλεγχος 3, E3: η διάρκεια ύπνου από ΑΛΛΗ συσκευή (κινητό, βραχιόλι), που είχαν γράψει παλιές εκδόσεις χωρίς φίλτρο
/// ρολογιού. Δεν φαίνεται πουθενά (δεν είναι ύπνος του ρολογιού) αλλά δεν σβήνεται ποτέ.
const nonWatchSleepKey = 'nw.sleepMin';

/// Έλεγχος 4: οι κρυφές τιμές ύπνου έχουν το πρόθεμα «nw.» (π.χ. «nw.bedtime»). Καμία οθόνη, Τάση ή αναφορά δεν τις
/// διαβάζει (δεν είναι κλειδιά [K]).
const archivePrefix = 'nw.';

/// Σημάδι στη μέρα: η νύχτα κρατήθηκε χωριστά ως «από άλλη συσκευή» (κομμάτι χωρίς ύπνο ρολογιού, E3). Μετριέται στο
/// «Τι φτάνει» ([otherDeviceNights]).
const otherDeviceKey = 'nw.device';

/// Έλεγχος 4 (1_data M2/M3/L1, red team M1): μια αξιόπιστη νέα ανάγνωση ύπνου ([rows]) δεν έδωσε έγκυρη διάρκεια ύπνου
/// ρολογιού για μια νύχτα του ρολογιού που είχε (νύχτα χωρίς φάσεις ή με > 5% άγνωστες, νύχτα μόνο από κινητό ή
/// βραχιόλι, ή κομμάτι «από άλλη συσκευή»). Τότε ΟΛΕΣ οι τιμές ύπνου της μέρας ([sleepKeys]: διάρκεια, ώρες, φάσεις,
/// βαθμολογία, οξυγόνο, θερμοκρασία, παλμοί ύπνου, υπνάκοι) μεταφέρονται σε κρυφά κλειδιά «nw.*»: ούτε μένουν ως ύπνος
/// του ρολογιού (θα ανακάτευαν δύο ορισμούς) ούτε σβήνονται. Ένα «nw.*» που υπάρχει ήδη δεν αλλάζει (η πρώτη, αρχική
/// τιμή μένει). Οι νέες τιμές της ανάγνωσης γράφονται μετά, κανονικά ([mergeHistory]). [otherDevice]: σημάδι
/// [otherDeviceKey]. Επιστρέφει τις μέρες που άλλαξαν.
Set<String> archiveSleep(
  Map<String, Map<String, double>> history,
  Map<String, Map<String, double>> rows, {
  required DateTime from,
  required DateTime to,
  required SourcePlan plan,
  bool otherDevice = false,
}) {
  final changed = <String>{};
  for (var day = dayOf(from); !day.isAfter(dayOf(to)); day = DateTime(day.year, day.month, day.day + 1)) {
    final k = dateKey(day);
    final old = history[k];
    if (old == null || old[K.sleepMin] == null || plan.nightSource(day) != Source.watch) continue;
    if (rows[k]?.containsKey(K.sleepMin) ?? false) continue;
    // Review M3: η απόφαση «πρωινός υπνάκος» ([K.napLock]) δεν είναι μέτρηση· μένει ορατή, ώστε η νύχτα, αν ξανάρθει,
    // να ομαδοποιηθεί όπως πριν.
    bool archived(String key) => sleepKeys.contains(key) && key != K.napLock;
    history[k] = {
      for (final e in old.entries) if (!archived(e.key)) e.key: e.value,
      for (final e in old.entries)
        if (archived(e.key) && !old.containsKey('$archivePrefix${e.key}')) '$archivePrefix${e.key}': e.value,
      if (otherDevice) otherDeviceKey: 1,
    };
    changed.add(k);
  }
  return changed;
}

/// E3 (όνομα του έλεγχου 3): κομμάτι «από άλλη συσκευή». Από τον έλεγχο 4 μεταφέρονται ΟΛΕΣ οι τιμές ύπνου της μέρας.
Set<String> archiveNonWatchSleep(
  Map<String, Map<String, double>> history,
  Map<String, Map<String, double>> rows, {
  required DateTime from,
  required DateTime to,
  required SourcePlan plan,
}) =>
    archiveSleep(history, rows, from: from, to: to, plan: plan, otherDevice: true);

/// Πόσες νύχτες κρατήθηκαν χωριστά ως «από άλλη συσκευή» ([otherDeviceKey]).
int otherDeviceNights(Map<String, Map<String, double>> history) =>
    history.values.where((r) => r.containsKey(otherDeviceKey)).length;

/// Πόσες μέρες στο [from, to] έχουν ήδη ύπνο στο ιστορικό.
int sleepDaysIn(Map<String, Map<String, double>> history, DateTime from, DateTime to) {
  var n = 0;
  for (var d = dayOf(from); !d.isAfter(dayOf(to)); d = DateTime(d.year, d.month, d.day + 1)) {
    if (history[dateKey(d)]?.containsKey(K.sleepMin) ?? false) n++;
  }
  return n;
}

/// Τιμές που έρχονται από τις ζυγίσεις.
const bodyKeys = {K.weight, K.fatPct, K.smm};

/// Όλα τα κλειδιά μιας ζύγισης στο ιστορικό: οι τιμές και το σημάδι της InBody.
const bodyRowKeys = {K.weight, K.fatPct, K.smm, K.inbody};

/// Έλεγχος 3, E2: η πρώτη μέρα με ζύγιση InBody ([K.inbody]), ΑΝ υπάρχουν και ζυγίσεις χωρίς σημάδι (παλιές εκδόσεις,
/// ίσως άλλη εφαρμογή). Από εκείνη τη μέρα και μετά φαίνονται μόνο οι ζυγίσεις της InBody, και είναι αλλαγή πηγής για
/// βάρος/λίπος/μύες. null = τίποτα να κρυφτεί (καμία ζύγιση InBody, ή όλες της InBody).
DateTime? scaleFromOf(Map<String, Map<String, double>> history) {
  String? first;
  var unmarked = false;
  for (final e in history.entries) {
    final r = e.value;
    if (r[K.inbody] != null) {
      if (first == null || e.key.compareTo(first) < 0) first = e.key;
    } else if (r.keys.any(bodyKeys.contains)) {
      unmarked = true;
    }
  }
  return first != null && unmarked ? parseDateKey(first) : null;
}

/// Μία ολόκληρη ζύγιση ανά μέρα: η τελευταία της μέρας από την InBody (ποτέ πεδία από δύο διαφορετικές
/// ζυγίσεις μαζί). Κλειδί = μέρα («2026-11-10»).
Map<String, Map<String, double>> bodyRows(List<BodyMeasurement> body) {
  final last = <String, BodyMeasurement>{};
  for (final b in body) {
    final k = dateKey(b.time);
    final o = last[k];
    if (o == null || !b.time.isBefore(o.time)) last[k] = b;
  }
  return {
    for (final e in last.entries)
      e.key: {
        if (e.value.weight != null && e.value.weight!.isFinite) K.weight: e.value.weight!,
        if (e.value.fatPct != null && e.value.fatPct!.isFinite) K.fatPct: e.value.fatPct!,
        if (e.value.smm != null && e.value.smm!.isFinite) K.smm: e.value.smm!,
        // E2: μόνο ζυγίσεις της InBody φτάνουν εδώ ([Dashboard.body]).
        K.inbody: 1,
      },
  };
}

/// Βάζει τις ζυγίσεις ([bodyRows]) στο ιστορικό ΧΩΡΙΣ να αγγίζει τίποτα άλλο της μέρας (έλεγχος 4/11, A1: μια
/// ζύγιση σε παλιά μέρα δεν περνά από το [mergeHistory], που θα έσβηνε π.χ. το οξυγόνο μιας νύχτας του Oura).
/// Οι τιμές ζύγισης της μέρας αντικαθίστανται όλες μαζί από τη μία ζύγιση. Επιστρέφει τις μέρες που άλλαξαν.
Set<String> mergeBody(Map<String, Map<String, double>> history, Map<String, Map<String, double>> rows) {
  final changed = <String>{};
  for (final e in rows.entries) {
    if (!e.value.keys.any(bodyKeys.contains)) continue;
    final old = history[e.key] ?? const <String, double>{};
    final next = {
      for (final v in old.entries) if (!bodyRowKeys.contains(v.key)) v.key: v.value,
      ...e.value,
    };
    if (!_sameValues(history[e.key], next)) changed.add(e.key);
    history[e.key] = next;
  }
  return changed;
}

/// Σβήνει τις τιμές ζύγισης από μέρες (από [from] και μετά) που δεν έχουν πια ζύγιση στη Samsung
/// (π.χ. σβήστηκε μια λάθος ζύγιση). [bodyDays]: οι μέρες με ζύγιση τώρα. Επιστρέφει τις μέρες που άλλαξαν.
Set<String> removeMissingBody(Map<String, Map<String, double>> history, Set<String> bodyDays, {required DateTime from}) {
  final changed = <String>{};
  for (final e in history.entries.toList()) {
    if (bodyDays.contains(e.key) || !e.value.keys.any(bodyKeys.contains)) continue;
    if (parseDateKey(e.key).isBefore(dayOf(from))) continue;
    history[e.key] = {for (final v in e.value.entries) if (!bodyRowKeys.contains(v.key)) v.key: v.value};
    changed.add(e.key);
  }
  return changed;
}

/// Τα είδη δεδομένων από τα οποία βγαίνουν οι τιμές ύπνου ([sleepKeys]), με τα ονόματα της γέφυρας.
/// Οι παλμοί ΔΕΝ είναι εδώ (έλεγχος 4/11, A12): αν δεν διαβαστούν (π.χ. πάρα πολλές εγγραφές), ο ύπνος
/// ενημερώνεται κανονικά και μόνο οι τιμές από τους παλμούς ([heartKeys]) μένουν ως είχαν ([heartReadFailed]).
const sleepReadKeys = ['sleep', 'stepsMin', 'spo2', 'skinTemp'];

bool _failed(Map<String, dynamic> r, String k) {
  final v = r[k];
  return v is Map && v.containsKey('error');
}

/// Αν σε μια ανάγνωση της γέφυρας κάποιο από τα [sleepReadKeys] γύρισε σφάλμα ({"error": …}).
/// Τότε οι τιμές ύπνου εκείνων των ημερών **δεν** αντικαθίστανται (θα έμεναν κενά).
bool sleepReadFailed(Map<String, dynamic> r) => sleepReadKeys.any((k) => _failed(r, k));

/// Οι παλμοί δεν διαβάστηκαν (ή κόπηκαν): οι τιμές από τους παλμούς δεν αλλάζουν σε αυτή την ανάγνωση.
bool heartReadFailed(Map<String, dynamic> r) => _failed(r, 'heart');

/// «2026-10-24»
String dateKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

DateTime parseDateKey(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// Λεπτά μετά τις 18:00, ώστε τα μεσάνυχτα να μη «σπάνε» μέσους όρους.
int minutesFromSix(DateTime t) => (t.hour * 60 + t.minute - 18 * 60 + 1440) % 1440;

/// «00:35» από λεπτά μετά τις 18:00.
String clockFromSix(double minutesFromSix) {
  final m = (minutesFromSix.round() + 18 * 60) % 1440;
  return '${two(m ~/ 60)}:${two(m % 60)}';
}

/// Η σύνοψη μιας μέρας από τα δεδομένα της Samsung (ρολόι, ζυγαριά). Ό,τι λείπει, απλώς δεν υπάρχει στον χάρτη.
///
/// [plan]: τις μέρες που η «νύχτα» δεν είναι του ρολογιού, δεν βγαίνει καμία τιμή νύχτας από το ρολόι (ύπνος,
/// παλμοί ύπνου, θερμοκρασία, βαθμολογία, Energy Score)· μόνο το οξυγόνο της νύχτας του ρολογιού, μέσα στις
/// ώρες της νύχτας του Oura ([Dashboard.watchSpo2]).
/// [windows]: οι ώρες ύπνου του Oura, μόνο ως χρονικά παράθυρα (παλμοί της μέρας, οξυγόνο της νύχτας).
Map<String, double> summarizeDay(Dashboard d, DateTime day, {SourcePlan? plan, SleepWindows windows = SleepWindows.empty}) {
  final p = plan ?? SourcePlan.samsungOnly;
  final out = <String, double>{};
  void put(String k, num? v) {
    if (v != null && v.isFinite) out[k] = v.toDouble();
  }

  final watchNight = p.nightSource(day) == Source.watch;

  // Ύπνος: η νύχτα με ημερομηνία το πρωί αυτής της μέρας.
  Night? night;
  for (final n in d.nights) {
    if (sameDay(n.date, day)) night = n;
  }
  if (!watchNight) {
    final ox = d.watchSpo2(day, windows);
    if (ox != null) {
      put(K.spo2Avg, ox.avg);
      put(K.spo2Min, ox.min);
      put(K.spo2Low, ox.below90);
      put(K.spo2Cov, ox.cov);
    }
  }
  // Υπνάκοι του ρολογιού (C1): αποθηκεύονται χωριστά, και μέρα χωρίς νύχτα· ποτέ μέσα στη διάρκεια του ύπνου.
  if (watchNight) {
    final nap = d.naps[dayOf(day)] ?? 0;
    if (nap > 0) put(K.napMin, nap);
  }
  if (watchNight && night != null) {
    final lock = night.napLock;
    if (lock != null) put(K.napLock, lock.millisecondsSinceEpoch ~/ 60000);
    // Διάρκεια μόνο από φάσεις (πραγματικός ύπνος). Νύχτα χωρίς φάσεις: η διάρκεια της Samsung έχει τα ξυπνήματα,
    // οπότε δεν μπαίνει στις Τάσεις, στην εβδομάδα και στην αναφορά (οι ώρες ύπνου/ξυπνήματος μπαίνουν κανονικά).
    if (night.fullDuration) put(K.sleepMin, night.minutes);
    put(K.sleepScore, night.score);
    // Ποσοστά επί του πραγματικού ύπνου (βαθύς + ελαφρύς + REM), όπως στο Oura· ο χρόνος ξύπνιος χωριστά σε λεπτά
    // (έλεγχος 4/11, B4: πριν, ποσοστά επί του χρόνου μαζί με τα ξυπνήματα).
    final staged = ['DEEP', 'LIGHT', 'REM', 'AWAKE'].fold<int>(0, (s, k) => s + (night!.stageMinutes[k] ?? 0));
    if (staged > 0) {
      put(K.deepPct, night.stagePct('DEEP'));
      put(K.remPct, night.stagePct('REM'));
      put(K.awakeMin, night.stageMinutes['AWAKE'] ?? 0);
    }
    put(K.bedtime, minutesFromSix(night.start));
    put(K.wake, minutesFromSix(night.end));
    put(K.sleepHr, night.sleepingHr);
    put(K.spo2Avg, night.spo2Avg);
    put(K.spo2Min, night.spo2Min);
    put(K.spo2Low, night.spo2Below90);
    put(K.skinTemp, night.skinTemp);
  }

  // Παλμοί μέσα στη μέρα (μόνο όταν υπάρχουν βήματα ανά λεπτό).
  // Ο ύπνος που εξαιρείται έρχεται από την πηγή ΚΑΘΕ νύχτας (της νύχτας που τελειώνει το πρωί και αυτής που
  // αρχίζει το βράδυ), όχι από το «αν συνδέθηκε ποτέ το Oura». Με το ρολόι και στις δύο: όπως πάντα.
  final next = DateTime(day.year, day.month, day.day + 1);
  final planned = p.nightSource(day) != Source.watch || p.nightSource(next) != Source.watch;
  final h = planned ? _heartWithPlan(d, day, p, windows) : d.heartForDay(day);
  if (h != null) {
    // Υπολογίζονται και κρατιούνται (για αργότερα), αλλά δεν φαίνονται πια: δικοί μας ορισμοί χωρίς επαλήθευση.
    put(K.restHr, h.resting.value);
    put(K.dayHr, h.awake.value);
    put(K.walkHr, h.bands[HeartBand.walk]?.value);
  }

  put(K.steps, d.valueFor(d.steps, day)?.value);
  put(K.floors, d.valueFor(d.floors, day)?.value);
  // Energy Score: της ίδιας ομάδας με τη νύχτα (μετά τη σύνδεση τη θέση του παίρνει η ετοιμότητα του Oura).
  if (watchNight) put(K.energy, d.valueFor(d.energy, day)?.value);
  for (final a in d.activityDaily) {
    if (sameDay(a.$1, day)) {
      put(K.activeMin, a.$2);
      put(K.calories, a.$3);
    }
  }

  // Ζύγιση: η τελευταία της μέρας.
  BodyMeasurement? body;
  for (final b in d.body) {
    if (sameDay(b.time, day)) body = b;
  }
  if (body != null) {
    put(K.weight, body.weight);
    put(K.fatPct, body.fatPct);
    put(K.smm, body.smm);
  }
  return out;
}

/// Παλμοί μέρας όταν υπάρχει Oura στο σχέδιο: ο ύπνος που εξαιρείται έρχεται από την πηγή κάθε νύχτας
/// (της νύχτας που τελειώνει το πρωί και αυτής που αρχίζει το βράδυ). Αν μία από τις δύο δεν είναι γνωστή,
/// δεν βγαίνει τιμή: αλλιώς ο ύπνος θα μετρούσε ως «μέρα». Οι τιμές είναι πάντα μόνο του ρολογιού.
DayHeart? _heartWithPlan(Dashboard d, DateTime day, SourcePlan p, SleepWindows windows) {
  final today = dayOf(d.readAt);
  final ranges = <(DateTime, DateTime)>[];
  var watchAdded = false;
  var ouraAdded = false;
  for (final n in [dayOf(day), DateTime(day.year, day.month, day.day + 1)]) {
    if (n.isAfter(today)) continue; // η νύχτα του απόψε δεν έχει γίνει ακόμα
    switch (p.nightSource(n)) {
      case Source.watch:
        if (!d.sleepOk) return null;
        if (!watchAdded) {
          watchAdded = true;
          // Μόνο ύπνος του ρολογιού από νύχτες που η πηγή τους είναι το ρολόι (ποτέ από νύχτες του Oura).
          DateTime nightOf(DateTime end) => end.hour >= 18 ? DateTime(end.year, end.month, end.day + 1) : dayOf(end);
          ranges.addAll([
            for (final r in d.sleepRecords)
              if (p.nightSource(nightOf(r.end)) == Source.watch) (r.start, r.end),
            for (final x in d.nights)
              if (p.nightSource(x.date) == Source.watch) ...x.estimatedGaps,
          ]);
        }
      case Source.oura:
        if (!windows.mains.containsKey(dateKey(n))) return null;
        if (!ouraAdded) {
          ouraAdded = true;
          ranges.addAll(windows.ranges);
        }
      case Source.none:
      case Source.scale:
        return null;
    }
  }
  return d.heartForDay(day, sleepRanges: ranges);
}

/// Συνόψεις για κάθε μέρα στο [from, to] (συμπεριλαμβανομένων), μόνο όσες έχουν κάτι.
Map<String, Map<String, double>> summarizeRange(Dashboard d, DateTime from, DateTime to,
    {SourcePlan? plan, SleepWindows windows = SleepWindows.empty}) {
  final out = <String, Map<String, double>>{};
  for (var day = dayOf(from); !day.isAfter(dayOf(to)); day = DateTime(day.year, day.month, day.day + 1)) {
    final s = summarizeDay(d, day, plan: plan, windows: windows);
    if (s.isNotEmpty) out[dateKey(day)] = s;
  }
  return out;
}

bool _sameValues(Map<String, double>? a, Map<String, double> b) {
  if (a == null || a.length != b.length) return false;
  for (final e in b.entries) {
    if (a[e.key] != e.value) return false;
  }
  return true;
}
