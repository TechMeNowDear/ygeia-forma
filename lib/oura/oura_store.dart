/// Το Oura μέσα στην κατάσταση της εφαρμογής (HealthStore): σύνδεση, ανάγνωση, αποσύνδεση, κατάσταση.
///
/// - Διαβάζει ΜΟΝΟ όταν ανοίγει η εφαρμογή ή επιστρέφω σε αυτήν (μαζί με τη Samsung), το πολύ κάθε 30 λεπτά:
///   τις τελευταίες 3 μέρες, ό,τι δεν είχε διαβαστεί, και τις νύχτες του Oura των 30 ημερών που λείπουν ακόμα.
///   Καμία δουλειά στο παρασκήνιο, καμία συνεχής ανανέωση.
/// - Γράφει στο ιστορικό ΜΟΝΟ τις μέρες που η «νύχτα» έρχεται από το Oura (δες sources.dart), με τα κλειδιά του.
/// - Κρατά τις λεπτομέρειες των τελευταίων νυχτών (ώρες, φάσεις, υπνάκοι) για τις οθόνες.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../error_report.dart';
import '../format.dart';
import '../history.dart';
import '../sources.dart';
import 'config.dart';
import 'oura_api.dart';
import 'oura_model.dart';
import 'oura_view.dart';

/// Η αποθήκευση στο κινητό (Android Keystore) μέσω της γέφυρας «ygeia/oura».
class ChannelVault implements OuraVault {
  const ChannelVault();
  static const channel = MethodChannel('ygeia/oura');

  @override
  Future<String?> load(String name) async {
    final String? raw;
    try {
      raw = await channel.invokeMethod<String>('vaultLoad', {'name': name});
    } on MissingPluginException {
      return null; // χωρίς Android (δοκιμές)
    } catch (_) {
      throw const VaultUnavailable();
    }
    if (raw == null) throw const VaultUnavailable();
    final Object? j;
    try {
      j = jsonDecode(raw);
    } catch (_) {
      throw const VaultUnavailable();
    }
    if (j is! Map || j.containsKey('error')) throw const VaultUnavailable();
    final v = j['v'];
    return v is String ? v : null;
  }

  @override
  Future<bool> save(String name, String value) async {
    try {
      return await channel.invokeMethod<bool>('vaultSave', {'name': name, 'value': value}) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> delete(String name) async {
    try {
      await channel.invokeMethod<bool>('vaultDelete', {'name': name});
    } catch (_) {}
  }
}

/// Η κατάσταση του Oura για τις οθόνες.
enum OuraStatus {
  /// Δεν έχει συνδεθεί ποτέ (ή αποσυνδέθηκε πριν αρχίσει): η εφαρμογή δουλεύει όπως πάντα.
  off,

  /// Συνδέθηκε σήμερα· ο ύπνος έρχεται από το Oura από απόψε (η χθεσινή νύχτα μένει του ρολογιού).
  starting,

  /// Συνδέθηκε σήμερα με πρώτη νύχτα τη σημερινή (00:00–03:59, ή «Ναι» στην ερώτηση): η νύχτα μετρά από το
  /// δαχτυλίδι· δεν έχει έρθει ακόμα.
  startingNow,

  /// Μια σύνδεση έμεινε μισή (π.χ. έκλεισε η εφαρμογή στη μέση): καθαρίστηκε· «δοκίμασε ξανά».
  incomplete,

  /// Συνδεδεμένο, όλα εντάξει.
  ok,

  /// Η χθεσινή νύχτα δεν έχει φτάσει ακόμα (πρωί, πριν από τις 12:00).
  waiting,

  /// Η χθεσινή νύχτα δεν ήρθε (μετά τις 12:00, ή πολλές μέρες).
  missing,

  /// Χρειάζεται νέα σύνδεση.
  reconnect,

  /// 403: συνδρομή ή άδεια.
  subscription,

  /// Δίκτυο / διακομιστής / 429: ξανά αργότερα (τα παλιά μένουν).
  retry,

  /// Αποσυνδέθηκε και ο ύπνος δεν έχει πηγή (κενές νύχτες).
  disconnected,
}

/// Πόσο περιμένουμε μετά από κάθε αποτέλεσμα (εκτός από τη χειροκίνητη «Ενημέρωση τώρα», που επιτρέπεται
/// το πολύ μία φορά το λεπτό).
Duration ouraBackoffFor(OuraErrorKind? k, {Duration? retryAfter}) => switch (k) {
      null => ouraMinInterval,
      OuraErrorKind.reconnect || OuraErrorKind.noRefresh || OuraErrorKind.scopeMissing => const Duration(hours: 6),
      OuraErrorKind.subscription ||
      OuraErrorKind.format ||
      OuraErrorKind.proxyNotConfigured ||
      OuraErrorKind.proxyRejected =>
        const Duration(hours: 1),
      // Όσο ζητά η Oura (Retry-After), τουλάχιστον 1 λεπτό και το πολύ 6 ώρες· χωρίς Retry-After 15 λεπτά.
      OuraErrorKind.rateLimited => retryAfter == null
          ? const Duration(minutes: 15)
          : retryAfter < const Duration(minutes: 1)
              ? const Duration(minutes: 1)
              : retryAfter > ouraMaxBackoff
                  ? ouraMaxBackoff
                  : retryAfter,
      _ => ouraMinInterval,
    };

/// Ποτέ δεν περιμένουμε περισσότερο από αυτό (και ένα παλιό «περίμενε ως» πιο μακριά θεωρείται λάθος ρολογιού).
const ouraMaxBackoff = Duration(hours: 6);

/// Πώς αποφασίζεται η πρώτη νύχτα του Oura, από την ώρα που πατιέται «Σύνδεση με Oura» (απόφαση 3/11, 3ος
/// έλεγχος). Αποφασίζεται ΠΡΙΝ ανοίξει ο browser και κρατιέται με το state της σύνδεσης.
enum FirstNightChoice {
  /// 00:00–03:59: η νύχτα που κοιμάσαι τώρα μετρά από το δαχτυλίδι (σήμερα).
  today,

  /// 04:00–11:59: μία ερώτηση «Φορούσες το δαχτυλίδι την τελευταία νύχτα;» (προεπιλογή «Όχι, από απόψε»).
  ask,

  /// 12:00–23:59: από απόψε (αύριο).
  tomorrow,
}

FirstNightChoice firstNightChoice(DateTime now) => now.hour < 4
    ? FirstNightChoice.today
    : now.hour < 12
        ? FirstNightChoice.ask
        : FirstNightChoice.tomorrow;

/// Η πρώτη νύχτα του Oura (η ημερομηνία της είναι το πρωί που τελειώνει). [woreRing]: η απάντηση στην ερώτηση
/// (04:00–11:59)· χωρίς απάντηση, από απόψε.
DateTime firstOuraNight(DateTime now, {bool woreRing = false}) {
  final today = dayOf(now);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  return switch (firstNightChoice(now)) {
    FirstNightChoice.today => today,
    FirstNightChoice.ask => woreRing ? today : tomorrow,
    FirstNightChoice.tomorrow => tomorrow,
  };
}

/// Οι γραμμές του ιστορικού σε άλλο νήμα όταν είναι πολλές (πρώτη ανάγνωση). Αν το νήμα δεν ξεκινήσει,
/// γίνεται εδώ και αναφέρεται μία φορά: η ανάγνωση δεν σταματά ποτέ γι' αυτό.
Future<Map<String, Map<String, double>>> ouraRowsOffMain(List<OuraNight> nights) async {
  if (nights.length <= 20) return ouraRows(nights);
  try {
    return await Isolate.run(() => _rowsOf(nights));
  } catch (_, st) {
    errors.report(const OuraError(OuraErrorKind.isolate), st, extra: {'where': 'oura-isolate'});
    return ouraRows(nights);
  }
}

Map<String, Map<String, double>> _rowsOf(List<OuraNight> nights) => ouraRows(nights);

mixin OuraStore on ChangeNotifier {
  // Από το HealthStore.
  Map<String, Map<String, double>> get history;
  SourcePlan get plan;
  bool get historyReady;
  bool get prefsReady;
  bool get planReady;
  bool get canChangePlan;
  bool get planUnknown;
  Future<bool> saveDaysNow(Set<String> keys);

  /// Έλεγχος 3, E1.5: τα βήματα ανά λεπτό του ΡΟΛΟΓΙΟΥ στο [from, to) (null = άγνωστα), μόνο για το πρωινό κενό του
  /// κοινού κανόνα της νύχτας (ποτέ ως τιμή του Oura).
  int? watchStepsBetween(DateTime from, DateTime to);

  /// Οι αποθηκευμένες αποφάσεις «πρωινός υπνάκος» των νυχτών του Oura («o.napLock»), E1.6.
  Map<String, int> get _ouraNapLocks {
    final key = ouraKeys[K.napLock]!;
    return {
      for (final e in history.entries)
        if (e.value[key] case final v? when v.isFinite) e.key: v.round(),
    };
  }

  Future<bool> savePrefsNow();
  Future<bool> setPlan(SourcePlan p);

  // Οι ρυθμίσεις για το πότε διαβάστηκε / δοκιμάστηκε το Oura (στο Prefs).
  int? get ouraSyncedMs;
  set ouraSyncedMs(int? v);
  String? get ouraSyncedTo;
  set ouraSyncedTo(String? v);

  /// Έλεγχος 2, C9: μετά από καινούργια βάση (χαλασμένη), ως ποια μέρα (μαζί) μένει να ξαναδιαβαστεί το Oura πιο πίσω
  /// από τις [ouraMaxBackDays] μέρες, ανά [ouraMaxBackDays] μέρες τη φορά, ως την αρχή της πρώτης εποχής του Oura.
  /// null = τίποτα.
  String? get ouraRefetchTo;
  set ouraRefetchTo(String? v);
  int? get ouraTriedMs;
  set ouraTriedMs(int? v);
  int? get ouraBackoffMs;
  set ouraBackoffMs(int? v);

  /// Το τελευταίο σφάλμα, όπως αποθηκεύεται (όνομα), ώστε μετά από επανεκκίνηση να λέμε τον σωστό λόγο.
  String? get ouraErrorStored;
  set ouraErrorStored(String? v);

  /// Πότε ολοκληρώθηκε η σύνδεση (ms), για την κάρτα «η νύχτα που κοιμάσαι τώρα».
  int? get ouraConnectedMs;
  set ouraConnectedMs(int? v);

  /// Η σύνδεση (αντικαθίσταται στους ελέγχους).
  OuraLink ouraLink = OuraLink(vault: const ChannelVault());

  /// Πού κρατιούνται οι λεπτομέρειες των νυχτών (αντικαθίσταται στους ελέγχους).
  OuraNightsFile ouraNightsFile = const ChannelNightsFile();

  /// Για τους ελέγχους: «τώρα».
  DateTime Function() ouraClock = DateTime.now;

  /// Πόσο περιμένει η αποσύνδεση την τελευταία ανάγνωση (A3). Αλλάζει μόνο στους ελέγχους.
  Duration ouraFinalSyncTimeout = const Duration(seconds: 20);

  /// Οι τελευταίες νύχτες του Oura με τις λεπτομέρειές τους, παλιότερη πρώτη.
  List<OuraNight> ouraNights = const [];

  /// Έλεγχος 3, E4: το αρχείο νυχτών υπάρχει αλλά δεν διαβάστηκε (σφάλμα, όχι «δεν υπάρχει»). Όσο ισχύει: το αρχείο
  /// δεν ξαναγράφεται (θα έμεναν μόνο οι λίγες νύχτες της νέας ανάγνωσης στη θέση των 45) και οι παλμοί μέρας δεν
  /// σβήνονται επειδή «λείπει» νύχτα ([ouraWindowsComplete]). Ξαναδοκιμάζεται σε κάθε ανάγνωση της Oura.
  bool ouraNightsReadFailed = false;

  /// Οι ώρες ύπνου του Oura είναι πλήρεις (το αρχείο νυχτών διαβάστηκε): μόνο τότε μια νύχτα που λείπει σημαίνει «δεν
  /// υπάρχει» (C12).
  bool get ouraWindowsComplete => !ouraNightsReadFailed;

  Future<void> _readNightsFile() async {
    try {
      final r = await ouraNightsFile.read();
      if (r.failed) {
        ouraNightsReadFailed = true;
        return;
      }
      final fresh = decodeOuraNights(r.json);
      // Νύχτες που ήρθαν στο μεταξύ (στη μνήμη) μένουν· του αρχείου συμπληρώνουν τις υπόλοιπες μέρες.
      final byDay = {for (final n in fresh) dateKey(n.day): n, for (final n in ouraNights) dateKey(n.day): n};
      ouraNights = byDay.values.toList()..sort((a, b) => a.day.compareTo(b.day));
      ouraNightsReadFailed = false;
    } catch (_) {
      ouraNightsReadFailed = true;
    }
  }

  /// Οι ώρες ύπνου του Oura, ΜΟΝΟ από νύχτες που η πηγή τους είναι το Oura (για τους παλμούς της μέρας).
  SleepWindows get ouraWindows =>
      ouraSleepWindows([for (final n in ouraNights) if (plan.nightSource(n.day) == Source.oura) n]);

  bool ouraHasTokens = false;
  bool ouraSyncing = false;
  bool ouraConnecting = false;

  /// Το τελευταίο σφάλμα (για την κατάσταση· ποτέ με προσωπικά στοιχεία). Αποθηκεύεται στις ρυθμίσεις.
  OuraErrorKind? get ouraError {
    final n = ouraErrorStored;
    if (n == null) return null;
    for (final k in OuraErrorKind.values) {
      if (k.name == n) return k;
    }
    return null;
  }

  set ouraError(OuraErrorKind? k) => ouraErrorStored = k?.name;

  bool _ouraStarted = false;

  /// Αυξάνει σε κάθε αποσύνδεση: ό,τι ανάγνωση ξεκίνησε πριν πετά τα αποτελέσματά της.
  int _ouraEpoch = 0;

  /// Η σύνδεση με την Oura είναι διαθέσιμη (έχει μπει Client ID).
  bool get ouraConfigured => ouraLink.configured;

  /// Το Oura είναι η πηγή του ύπνου σήμερα.
  bool get ouraActive => plan.nightSource(dayOf(ouraClock())) == Source.oura;

  /// Συνδέθηκε και ο ύπνος του Oura αρχίζει από απόψε.
  bool get ouraStartsTonight {
    final today = dayOf(ouraClock());
    final f = plan.ouraFrom;
    return f != null && f.isAfter(today) && plan.nightSource(f) == Source.oura;
  }

  /// Ο ύπνος σήμερα δεν έχει πηγή (αποσυνδέθηκε το Oura).
  bool get sleepUnsourced => plan.nightSource(dayOf(ouraClock())) == Source.none;

  DateTime? get ouraLastSync => ouraSyncedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(ouraSyncedMs!);

  Future<void> startOura() async {
    if (_ouraStarted) return;
    _ouraStarted = true;
    // Προσωρινά αρχεία από εγγραφή που διακόπηκε (μόνο τα δικά μας, στο Android). Δεν περιμένουμε.
    unawaited(ChannelVault.channel.invokeMethod<int>('cleanTmp').then((_) {}, onError: (_) {}));
    _tokensKnown = false;
    try {
      ouraHasTokens = await ouraLink.hasTokens;
      _tokensKnown = true;
    } on OuraError {
      // Η αποθήκευση δεν απάντησε τώρα: τα tokens δεν θεωρούνται χαμένα (ξανά στην επόμενη ανάγνωση).
      ouraHasTokens = plan.ouraFrom != null;
    } catch (_) {}
    await _readNightsFile();
    await _cleanHalfConnection();
    // Αν η εφαρμογή άνοιξε από την επιστροφή της Oura (πριν ήταν έτοιμη η Flutter).
    try {
      ChannelVault.channel.setMethodCallHandler((call) async {
        if (call.method == 'callback' && call.arguments is String) await completeOuraLogin(call.arguments as String);
        return null;
      });
      final pending = await ChannelVault.channel.invokeMethod<String>('takeCallback');
      if (pending != null) await completeOuraLogin(pending);
    } catch (_) {}
    notifyListeners();
  }

  void disposeOura() {
    try {
      ChannelVault.channel.setMethodCallHandler(null);
    } catch (_) {}
  }

  /// Η κατάσταση για τις κάρτες της Σήμερα και τη σελίδα «Oura».
  OuraStatus get ouraStatus {
    if (ouraIncomplete && !ouraHasTokens) return OuraStatus.incomplete;
    final today = dayOf(ouraClock());
    final src = plan.nightSource(today);
    if (src == Source.none) return OuraStatus.disconnected;
    if (src != Source.oura) return ouraStartsTonight && ouraHasTokens ? OuraStatus.starting : OuraStatus.off;
    // Αποσυνδέθηκε σήμερα (η σημερινή νύχτα μένει του Oura, από απόψε χωρίς πηγή): όχι «νέα σύνδεση».
    if (!ouraHasTokens && plan.nightSource(DateTime(today.year, today.month, today.day + 1)) == Source.none) {
      return OuraStatus.disconnected;
    }
    if (!ouraHasTokens ||
        ouraError == OuraErrorKind.reconnect ||
        ouraError == OuraErrorKind.noRefresh ||
        ouraError == OuraErrorKind.scopeMissing) {
      return OuraStatus.reconnect;
    }
    if (ouraError == OuraErrorKind.subscription) return OuraStatus.subscription;
    if (ouraError != null) return OuraStatus.retry;
    if (ouraNightFor(today)?.main != null) return OuraStatus.ok;
    final morning = ouraClock().hour < 12;
    final c = ouraConnectedMs;
    if (morning && sameDay(plan.ouraFrom ?? DateTime(2000), today) && c != null &&
        sameDay(DateTime.fromMillisecondsSinceEpoch(c), today)) {
      return OuraStatus.startingNow;
    }
    return morning ? OuraStatus.waiting : OuraStatus.missing;
  }

  /// Γιατί η νύχτα [day] είναι κενή (null = δεν είναι κενή ή δεν είναι νύχτα του Oura).
  EmptyNight? ouraNightReason(DateTime day, DateTime now) => emptyNightReason(
        plan: plan,
        day: day,
        now: now,
        night: ouraNightFor(day),
        hasTokens: ouraHasTokens,
        error: ouraError?.name,
        synced: ouraLastSync,
        planUnknown: planUnknown,
      );

  /// Η νύχτα του Oura για τη μέρα [day] — ΜΟΝΟ αν η πηγή εκείνης της νύχτας είναι το Oura.
  OuraNight? ouraNightFor(DateTime day) {
    if (plan.nightSource(day) != Source.oura) return null;
    for (final n in ouraNights) {
      if (sameDay(n.day, day)) return n;
    }
    return null;
  }

  /// Πόσες νύχτες στη σειρά (ως χθες βράδυ) λείπουν από το δαχτυλίδι, από τη σύνδεση και μετά.
  int get ouraMissingNights {
    final f = plan.ouraFrom;
    if (f == null) return 0;
    var n = 0;
    for (var d = dayOf(ouraClock()); !d.isBefore(f); d = DateTime(d.year, d.month, d.day - 1)) {
      if (plan.nightSource(d) != Source.oura || ouraNightFor(d)?.main != null) break;
      n++;
    }
    return n;
  }

  /// Η τελευταία νύχτα που ήρθε από το δαχτυλίδι (μόνο νύχτες με πηγή το Oura).
  OuraNight? get lastOuraNight {
    for (final n in ouraNights.reversed) {
      if (n.main != null && plan.nightSource(n.day) == Source.oura) return n;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Σύνδεση
  // ---------------------------------------------------------------------------

  /// Ανοίγει τη σελίδα της Oura στον browser. Επιστρέφει σφάλμα για την οθόνη, ή null αν άνοιξε.
  /// [from]: η πρώτη νύχτα του Oura ([firstOuraNight]), αποφασισμένη πριν ανοίξει ο browser.
  Future<OuraErrorKind?> beginOuraLogin({required DateTime from}) async {
    if (!ouraConfigured) return OuraErrorKind.notConfigured;
    if (!canChangePlan) return OuraErrorKind.cancelled;
    ouraIncomplete = false;
    try {
      final url = await ouraLink.begin(from: from);
      final ok = await ChannelVault.channel.invokeMethod<bool>('open', {'url': url.toString()}) ?? false;
      return ok ? null : OuraErrorKind.noBrowser;
    } on OuraError catch (e) {
      return e.kind;
    } catch (_) {
      return OuraErrorKind.noBrowser;
    }
  }

  /// Το αποτέλεσμα της τελευταίας σύνδεσης, για να το δείξει η οθόνη (μία φορά), και ο κωδικός OAuth του.
  OuraErrorKind? ouraLoginError;
  String? ouraLoginCode;
  bool ouraJustConnected = false;

  /// Η επιστροφή από την Oura. Σειρά: ανταλλαγή του κωδικού → ΠΡΩΤΑ το σχέδιο πηγών (αρχείο) → ΜΕΤΑ τα tokens.
  /// Αν δεν γραφτεί το σχέδιο, τα tokens δεν κρατιούνται (ανακαλούνται)· αν δεν γραφτούν τα tokens, το σχέδιο
  /// επιστρέφει όπως ήταν. Η πρώτη νύχτα ήρθε μαζί με το state ([beginOuraLogin]).
  Future<void> completeOuraLogin(String uri) async {
    final cb = parseCallback(uri);
    if (cb == null) return;
    // Χωρίς γνωστό σχέδιο πηγών δεν συνδέεται (δεν θα μπορούσε να αλλάξει η πηγή): ο κωδικός δεν χρησιμοποιείται.
    if (!canChangePlan) {
      ouraLoginError = OuraErrorKind.cancelled;
      notifyListeners();
      return;
    }
    ouraConnecting = true;
    ouraLoginError = null;
    ouraLoginCode = null;
    notifyListeners();
    final epoch = _ouraEpoch;
    final done = Completer<void>();
    _connectDone = done.future;
    try {
      final ex = await ouraLink.exchange(uri);
      if (ex == null) {
        // Επιστροφή χωρίς εκκρεμή σύνδεση (παλιά καρτέλα, δεύτερο πάτημα στη σελίδα επιστροφής): ασφαλές, αλλά το
        // λέμε (A13). Όχι αμέσως μετά από επιτυχημένη σύνδεση (η ίδια επιστροφή φτάνει μερικές φορές δύο φορές).
        final c = ouraConnectedMs;
        final justConnected = ouraHasTokens && c != null && ouraClock().millisecondsSinceEpoch - c < 5 * 60 * 1000;
        if ((cb.code != null || cb.error != null) && !justConnected && !await ouraLink.hasPending()) {
          ouraLoginError = OuraErrorKind.stale;
        }
        return;
      }
      if (epoch != _ouraEpoch) {
        await ouraLink.discard(ex.tokens);
        return;
      }
      // Έλεγχος πρόσβασης ΠΡΙΝ από οποιαδήποτε αλλαγή (A13): αν η Oura δεν δίνει δεδομένα ύπνου με αυτή τη σύνδεση
      // (άδεια, συνδρομή, άχρηστο token), τα tokens ανακαλούνται και το σχέδιο πηγών μένει όπως ήταν.
      DateTime? server;
      try {
        server = await ouraLink.verifyAccess(ex.tokens);
      } on OuraError {
        await ouraLink.discard(ex.tokens);
        rethrow;
      }
      if (epoch != _ouraEpoch) {
        await ouraLink.discard(ex.tokens);
        return;
      }
      // Έλεγχος 2, C12: ρολόι κινητού πολύ μπροστά (πάνω από μία μέρα από την ώρα της Oura): η πρώτη νύχτα μετριέται
      // με την ώρα της Oura, ώστε η εποχή να μην αρχίσει στο μέλλον (και το Oura να «ξεκινά» για μήνες).
      final phone = ouraClock();
      final now = clampToServer(phone, server);
      final today = dayOf(now);
      // Χωρίς αποθηκευμένη απόφαση (παλιά εκκρεμής σύνδεση): από απόψε. Ποτέ πριν από σήμερα.
      var from = ex.from ?? DateTime(today.year, today.month, today.day + 1);
      if (from.isBefore(today)) from = today;
      final before = plan;
      final next = plan.withEra(Source.oura, from);
      final changed = next != plan;
      // Σημάδι «συνδέεται» ΠΡΙΝ από το σχέδιο: αν κλείσει η εφαρμογή στη μέση, η εκκίνηση ξέρει τι να αναιρέσει.
      final marker = jsonEncode({'from': dateKey(from), 'at': now.millisecondsSinceEpoch, 'before': before.toJson()});
      if (!await ouraLink.markConnecting(marker)) {
        await ouraLink.discard(ex.tokens);
        ouraLoginError = OuraErrorKind.cancelled;
        return;
      }
      if (epoch != _ouraEpoch) {
        // «Αποσύνδεση» στο μεταξύ: τίποτα δεν αλλάζει.
        await ouraLink.discard(ex.tokens);
        await ouraLink.clearConnecting();
        ouraLoginError = OuraErrorKind.cancelled;
        return;
      }
      if (changed && !await setPlan(next)) {
        // Η πηγή δεν άλλαξε: τα tokens δεν κρατιούνται.
        await ouraLink.discard(ex.tokens);
        await ouraLink.clearConnecting();
        ouraLoginError = OuraErrorKind.cancelled;
        return;
      }
      if (epoch != _ouraEpoch || !await ouraLink.adopt(ex.tokens, ex.gen)) {
        // Τα tokens δεν γράφτηκαν (ή αποσυνδέθηκε στο μεταξύ): το σχέδιο επιστρέφει, τίποτα μισό. Η αποσύνδεση
        // περιμένει να τελειώσει αυτό ([_connectDone]) πριν αλλάξει το σχέδιο, άρα το σχέδιο είναι ακόμα το [next].
        // Έλεγχος 2, C12: το σημάδι «συνδέεται» σβήνεται ΜΟΝΟ αν το σχέδιο επέστρεψε· αλλιώς μένει, και η επόμενη
        // εκκίνηση το διορθώνει ([_finishMarker]), αντί να μείνει «Oura χωρίς σύνδεση».
        final reverted = !(changed && plan == next) || await setPlan(before);
        await ouraLink.discard(ex.tokens);
        if (reverted) await ouraLink.clearConnecting();
        ouraLoginError = OuraErrorKind.cancelled;
        return;
      }
      ouraHasTokens = true;
      ouraIncomplete = false;
      ouraError = null;
      ouraTriedMs = null;
      ouraBackoffMs = null;
      ouraConnectedMs = now.millisecondsSinceEpoch;
      ouraJustConnected = true;
      await savePrefsNow();
      await ouraLink.clearConnecting();
      // Αν η πρώτη νύχτα είναι η σημερινή, διαβάζεται αμέσως (μπορεί να έχει ήδη έρθει).
      if (!from.isAfter(today)) unawaited(syncOura(force: true));
    } on OuraError catch (e) {
      ouraLoginError = e.kind;
      ouraLoginCode = e.code;
      // Στο Sentry μόνο το είδος, ο κωδικός HTTP και ο κωδικός OAuth (π.χ. invalid_client): ποτέ tokens.
      errors.report(e, StackTrace.current, extra: {'where': 'oura-login', if (e.code != null) 'oauth': e.code!});
    } catch (e, st) {
      ouraLoginError = OuraErrorKind.format;
      errors.report(e, st, extra: {'where': 'oura-login'});
    } finally {
      ouraConnecting = false;
      done.complete();
      notifyListeners();
    }
  }

  /// Η σύνδεση που τρέχει (για να την περιμένει η αποσύνδεση).
  Future<void> _connectDone = Future.value();

  /// Αν τα tokens διαβάστηκαν στην εκκίνηση (false = η αποθήκευση δεν απάντησε· το [ouraHasTokens] είναι εκτίμηση).
  bool _tokensKnown = false;

  /// Μια σύνδεση έμεινε μισή και καθαρίστηκε στην εκκίνηση ([_cleanHalfConnection]).
  bool ouraIncomplete = false;

  /// Μισή σύνδεση στην εκκίνηση. Ποτέ «άγνωστο σχέδιο» γι' αυτό.
  /// - Σημάδι «συνδέεται» ([vaultConnecting]) χωρίς tokens: το σχέδιο επιστρέφει ακριβώς όπως ήταν πριν από αυτή
  ///   τη σύνδεση (και για όποιον είχε συνδεθεί παλιότερα), ανεξάρτητα από ημερομηνία ή άλλες ενδείξεις.
  ///   «Η σύνδεση δεν ολοκληρώθηκε· δοκίμασε ξανά».
  /// - Σημάδι με tokens: η σύνδεση ολοκληρώθηκε (έκλεισε πριν σβηστεί το σημάδι)· σβήνεται.
  /// - Tokens χωρίς καμία εποχή Oura και χωρίς τίποτα από το Oura (νύχτες, ανάγνωση, «o.*»): σβήνονται.
  /// Tokens που χάθηκαν (π.χ. επαναφορά κινητού) ΔΕΝ είναι μισή σύνδεση: «Χρειάζεται νέα σύνδεση με το Oura».
  Future<void> _cleanHalfConnection() async {
    if (!historyReady || !canChangePlan) return;
    final String? raw;
    try {
      raw = await ouraLink.connectingMarker();
    } catch (_) {
      return; // η αποθήκευση δεν απαντά: τίποτα δεν πειράζεται
    }
    if (raw != null) {
      await _finishMarker(raw);
      return;
    }
    // Χωρίς tokens και χωρίς σημάδι δεν υπάρχει τίποτα να καθαριστεί (κανένα ψάξιμο στο ιστορικό).
    if (!ouraHasTokens || plan.hasOura) return;
    if (ouraNights.isNotEmpty || ouraNightsReadFailed || ouraSyncedTo != null) return;
    if (history.values.any((r) => r.keys.any(ouraKeySet.contains))) return;
    _ouraEpoch++;
    await ouraLink.disconnect();
    ouraHasTokens = false;
    ouraIncomplete = true;
    ouraLoginError = OuraErrorKind.incomplete;
  }

  Future<void> _finishMarker(String raw) async {
    Map? j;
    try {
      final d = jsonDecode(raw);
      if (d is Map) j = d;
    } catch (_) {}
    // Τα tokens δεν διαβάστηκαν: τίποτα δεν κρίνεται τώρα (ούτε «ολοκληρώθηκε» ούτε «μισή»), ξανά σε επόμενη εκκίνηση.
    if (!_tokensKnown) return;
    // Έλεγχος 2, C12: αποσύνδεση που διακόπηκε (η εφαρμογή έκλεισε στη μέση): ολοκληρώνεται, ποτέ «Oura χωρίς σύνδεση».
    if (j?['disconnecting'] == true) {
      if (ouraHasTokens) {
        await ouraLink.disconnect(marker: raw);
        ouraHasTokens = false;
      }
      if (await _disconnectPlan()) await ouraLink.clearConnecting();
      await savePrefsNow();
      return;
    }
    if (ouraHasTokens) {
      // Ολοκληρώθηκε· αν έκλεισε πριν αποθηκευτεί η ώρα σύνδεσης, παίρνεται από το σημάδι.
      if (ouraConnectedMs == null && j?['at'] is num) {
        ouraConnectedMs = (j!['at'] as num).toInt();
        await savePrefsNow();
      }
      await ouraLink.clearConnecting();
      return;
    }
    final before = j?['before'] is List ? SourcePlan.fromJson(j!['before']) : null;
    DateTime? from;
    try {
      from = j?['from'] is String ? parseDateKey(j!['from'] as String) : null;
    } catch (_) {}
    // Παλιό σημάδι από σύνδεση που χρησιμοποιήθηκε (ανάγνωση ή τιμές Oura μετά από αυτό): μόνο σβήνεται. Μια
    // πραγματικά μισή σύνδεση δεν έχει ποτέ τέτοια (η ανάγνωση θέλει tokens).
    final at = j?['at'] is num ? (j!['at'] as num).toInt() : null;
    final f = from;
    final used = (at != null && (ouraSyncedMs ?? 0) >= at) ||
        (f != null && ouraNights.any((n) => !n.day.isBefore(f))) ||
        (f != null &&
            history.entries.any((e) => e.key.compareTo(dateKey(f)) >= 0 && e.value.keys.any(ouraKeySet.contains)));
    if (used) {
      await ouraLink.clearConnecting();
      return;
    }
    var ok = true;
    if (before != null && from != null && plan == before.withEra(Source.oura, from)) {
      ok = await setPlan(before);
    } else if (from != null && plan.eras.isNotEmpty && plan.eras.last.source == Source.oura && sameDay(plan.eras.last.from, from)) {
      ok = await setPlan(SourcePlan(plan.eras.sublist(0, plan.eras.length - 1)));
    }
    if (!ok) return; // ξανά στην επόμενη εκκίνηση
    await ouraLink.clearConnecting();
    ouraIncomplete = true;
    ouraLoginError = OuraErrorKind.incomplete;
    ouraConnectedMs = null;
    await savePrefsNow();
  }

  /// Πριν από τις 04:00: «η νύχτα που κοιμάσαι τώρα»· μετά: «η νύχτα που μόλις τελείωσε» (ακόμα κι αν η σύνδεση
  /// έγινε μέσα στη νύχτα: το πρωί έχει ήδη τελειώσει).
  String get ouraFirstNightText {
    final asleep = ouraClock().hour < 4;
    return asleep ? 'Η νύχτα που κοιμάσαι τώρα μετρά από το δαχτυλίδι' : 'Η νύχτα που μόλις τελείωσε μετρά από το δαχτυλίδι';
  }

  /// Το κουμπί της αναίρεσης: πριν από τις 04:00 η νύχτα δεν έχει τελειώσει ακόμα.
  String get watchLastNightLabel =>
      ouraClock().hour < 4 ? 'Η νύχτα που κοιμάσαι τώρα από το ρολόι' : 'Η τελευταία νύχτα από το ρολόι';

  /// Τη μέρα της σύνδεσης, αν η πρώτη νύχτα του Oura είναι η σημερινή: «Η τελευταία νύχτα από το ρολόι».
  bool get canWatchLastNight {
    final c = ouraConnectedMs;
    final last = plan.eras.isEmpty ? null : plan.eras.last;
    final today = dayOf(ouraClock());
    return ouraHasTokens &&
        c != null &&
        sameDay(DateTime.fromMillisecondsSinceEpoch(c), today) &&
        last != null &&
        last.source == Source.oura &&
        sameDay(last.from, today);
  }

  /// «Η τελευταία νύχτα από το ρολόι»: η πρώτη νύχτα του Oura γίνεται η αυριανή. Η νύχτα του ρολογιού δεν είχε
  /// σβηστεί ποτέ ([SourcePlan.keepsWatchNight]) και ξαναφαίνεται· οι τιμές του Oura γι' αυτή τη μέρα φεύγουν.
  Future<bool> watchLastNight() async {
    if (!canWatchLastNight) return false;
    final today = dayOf(ouraClock());
    final p = SourcePlan(plan.eras.sublist(0, plan.eras.length - 1))
        .withEra(Source.watch, today)
        .withEra(Source.oura, DateTime(today.year, today.month, today.day + 1));
    if (!await setPlan(p)) return false;
    final k = dateKey(today);
    final row = history[k];
    if (row != null && row.keys.any(ouraKeySet.contains)) {
      history[k] = {for (final e in row.entries) if (!ouraKeySet.contains(e.key)) e.key: e.value};
      await saveDaysNow({k});
    }
    notifyListeners();
    return true;
  }

  /// Αν μια εποχή Oura έχει ήδη αρχίσει (για το «Αναίρεση» της αποσύνδεσης: χωρίς αυτήν δεν υπάρχει τι να αναιρεθεί).
  bool get ouraEraStarted {
    final today = dayOf(ouraClock());
    return plan.eras.any((e) => e.source == Source.oura && !e.from.isAfter(today));
  }

  /// Αποσύνδεση: ανάκληση, σβήσιμο tokens, τα δεδομένα μένουν. Κερδίζει κάθε ανάγνωση που τρέχει.
  /// - Φεύγουν ΜΟΝΟ οι μελλοντικές εποχές Oura (π.χ. σύνδεση σήμερα με αρχή απόψε)· μια ρητή επιλογή
  ///   «ξανά από το ρολόι» μένει.
  /// - Αν και αύριο η πηγή θα ήταν το Oura: από απόψε χωρίς πηγή (κενές νύχτες), ώσπου να συνδεθεί ξανά ή να
  ///   διαλέξει ρητά το ρολόι ([sleepFromWatchAgain]). Η χθεσινή νύχτα του Oura μένει.
  Future<void> disconnectOura() async {
    // Μία τελευταία ανάγνωση πριν από την ανάκληση (έλεγχος 4/11, A3): νύχτες που δεν είχαν διαβαστεί ακόμα (π.χ. η
    // χθεσινή, πριν από το όριο των 30 λεπτών) δεν χάνονται. Με μικρό χρονικό όριο· αν δεν προλάβει, η αποσύνδεση
    // κερδίζει (ό,τι έρθει μετά πετιέται).
    if (ouraHasTokens) {
      try {
        await (_sync ?? (_sync = _syncOnce(false, last: true).whenComplete(() => _sync = null)))
            .timeout(ouraFinalSyncTimeout);
      } catch (_) {}
    }
    _ouraEpoch++;
    // Σύνδεση στη μέση: σταματά (νέα γενιά) και επαναφέρει μόνη της το σχέδιο· μετά αλλάζει το σχέδιο η αποσύνδεση.
    try {
      await _connectDone;
    } catch (_) {}
    // Έλεγχος 2, C12: σημάδι «αποσυνδέεται» ΠΡΙΝ από την ανάκληση: αν η εφαρμογή κλείσει ανάμεσα στο σβήσιμο των
    // tokens και στην αλλαγή του σχεδίου, η επόμενη εκκίνηση ολοκληρώνει την αποσύνδεση ([_finishMarker]).
    await ouraLink.disconnect(marker: jsonEncode({'disconnecting': true, 'at': ouraClock().millisecondsSinceEpoch}));
    ouraHasTokens = false;
    ouraError = null;
    ouraTriedMs = null;
    ouraBackoffMs = null;
    ouraConnectedMs = null;
    ouraIncomplete = false;
    if (await _disconnectPlan()) await ouraLink.clearConnecting();
    await savePrefsNow();
    notifyListeners();
  }

  /// Το σχέδιο μετά την αποσύνδεση: φεύγουν οι μελλοντικές εποχές Oura και από απόψε χωρίς πηγή. `false` αν δεν
  /// γράφτηκε.
  Future<bool> _disconnectPlan() async {
    final today = dayOf(ouraClock());
    final from = DateTime(today.year, today.month, today.day + 1);
    var ok = true;
    if (plan.eras.any((e) => e.source == Source.oura && e.from.isAfter(today))) {
      ok = await setPlan(SourcePlan([for (final e in plan.eras) if (!(e.source == Source.oura && e.from.isAfter(today))) e]));
    }
    if (ok && plan.nightSource(from) == Source.oura) ok = await setPlan(plan.withEra(Source.none, from));
    return ok;
  }

  /// Αναίρεση της αποσύνδεσης αμέσως μετά (το πλήκτρο «Αναίρεση»): μόνο το σχέδιο πηγών επιστρέφει.
  /// Η σύνδεση χρειάζεται ξανά «Σύνδεση με Oura» (τα tokens έχουν ανακληθεί).
  Future<void> restorePlan(SourcePlan previous) => setPlan(previous);

  /// Ρητή επιλογή: ο ύπνος ξανά από το ρολόι, από απόψε (νέα αλλαγή πηγής).
  Future<void> sleepFromWatchAgain() async {
    final today = dayOf(ouraClock());
    await setPlan(plan.withEra(Source.watch, DateTime(today.year, today.month, today.day + 1)));
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Ανάγνωση
  // ---------------------------------------------------------------------------

  Future<void>? _sync;

  /// Διαβάζει το Oura αν είναι η πηγή του ύπνου και πέρασε αρκετή ώρα (ή [force], το πολύ μία φορά το λεπτό).
  /// Μία ανάγνωση τη φορά.
  Future<void> syncOura({bool force = false}) => _sync ??= _syncOnce(force).whenComplete(() => _sync = null);

  /// Πόσο μένει ώσπου να επιτρέπεται πάλι «Ενημέρωση τώρα» (μία φορά το λεπτό). Μηδέν = τώρα.
  /// Μια δοκιμή «στο μέλλον» (το ρολόι πήγε πίσω) δεν μπλοκάρει.
  Duration get ouraSyncNowIn {
    final t = ouraTriedMs;
    final ms = ouraClock().millisecondsSinceEpoch;
    if (t == null || t > ms) return Duration.zero;
    final left = const Duration(minutes: 1).inMilliseconds - (ms - t);
    return left <= 0 ? Duration.zero : Duration(milliseconds: left);
  }

  bool get ouraCanSyncNow => ouraSyncNowIn == Duration.zero;

  /// Οι μέρες που πρέπει να διαβαστούν από το Oura σήμερα (έλεγχος 4/11, A3), σε ΟΛΕΣ τις εποχές του Oura (όχι μόνο
  /// την τελευταία), μόνο νύχτες με πηγή το Oura, ως [ouraMaxBackDays] πίσω:
  /// - οι τελευταίες [ouraRecentDays], όσο το Oura είναι η πηγή σήμερα (η Oura μπορεί να διορθώσει την προηγούμενη),
  /// - ό,τι δεν είχε διαβαστεί (η εφαρμογή έμεινε κλειστή πάνω από 2 μέρες· ή ποτέ: από την αρχή),
  /// - κάθε νύχτα του Oura των τελευταίων [ouraMissingDays] ημερών που λείπει ακόμα από το ιστορικό.
  /// null = τίποτα να διαβαστεί.
  /// C9: το επόμενο παλιότερο κομμάτι για ξαναδιάβασμα μετά από καινούργια βάση: από [ouraRefetchTo] προς τα πίσω, ως
  /// [ouraMaxBackDays] μέρες, όχι πριν από την αρχή της πρώτης εποχής του Oura. [next]: πού συνεχίζει (null = τέλος).
  ({DateTime from, DateTime to, DateTime? next})? ouraOlderRange() {
    final r = ouraRefetchTo;
    if (r == null) return null;
    DateTime? first;
    for (final e in plan.eras) {
      if (e.source == Source.oura && (first == null || e.from.isBefore(first))) first = e.from;
    }
    final to = parseDateKey(r);
    if (first == null || to.isBefore(first)) {
      ouraRefetchTo = null;
      return null;
    }
    var from = DateTime(to.year, to.month, to.day - (ouraMaxBackDays - 1));
    if (from.isBefore(first)) from = first;
    final next = DateTime(from.year, from.month, from.day - 1);
    return (from: from, to: to, next: next.isBefore(first) ? null : next);
  }

  ({DateTime from, DateTime to})? ouraSyncRange(DateTime today) {
    final floor = DateTime(today.year, today.month, today.day - ouraMaxBackDays);
    bool oura(DateTime d) => !d.isBefore(floor) && !d.isAfter(today) && plan.nightSource(d) == Source.oura;
    DateTime? lo;
    DateTime? hi;
    void need(DateTime d) {
      if (!oura(d)) return;
      if (lo == null || d.isBefore(lo!)) lo = d;
      if (hi == null || d.isAfter(hi!)) hi = d;
    }

    void needRange(DateTime a, DateTime b) {
      for (var d = a; !d.isAfter(b); d = DateTime(d.year, d.month, d.day + 1)) {
        need(d);
      }
    }

    final recent = DateTime(today.year, today.month, today.day - (ouraRecentDays - 1));
    if (plan.nightSource(today) == Source.oura) needRange(recent, today);
    final syncedTo = ouraSyncedTo == null ? null : parseDateKey(ouraSyncedTo!);
    if (syncedTo == null) {
      needRange(floor, today);
    } else if (syncedTo.isBefore(recent)) {
      needRange(DateTime(syncedTo.year, syncedTo.month, syncedTo.day - 1), today);
    }
    for (var i = 0; i < ouraMissingDays; i++) {
      final d = DateTime(today.year, today.month, today.day - i);
      if (oura(d) && !(history[dateKey(d)]?.containsKey(ouraKeys[K.sleepMin]) ?? false)) need(d);
    }
    final a = lo;
    final b = hi;
    return a == null || b == null ? null : (from: a, to: b);
  }

  Future<void> _syncOnce(bool force, {bool last = false}) async {
    if (!historyReady || !prefsReady || !planReady) return;
    final now = ouraClock();
    final today = dayOf(now);
    // Μόνο όταν το Oura είναι πηγή κάποιας νύχτας ως σήμερα: χωρίς σύνδεση δεν γίνεται καμία κλήση.
    if (!ouraHasTokens) return;
    final range = ouraSyncRange(today);
    if (range == null) return;
    final ms = now.millisecondsSinceEpoch;
    var tried = ouraTriedMs;
    var backoff = ouraBackoffMs;
    // Χρόνοι από ρολόι που είχε πάει μπροστά: ληγμένοι (αλλιώς η ανάγνωση θα έμενε μπλοκαρισμένη).
    if (tried != null && tried > ms) tried = null;
    if (backoff != null && backoff > ms + ouraMaxBackoff.inMilliseconds) backoff = null;
    if (last) {
      // Η τελευταία ανάγνωση πριν από την αποσύνδεση: χωρίς το όριο των 30 λεπτών, αλλά όχι αν η Oura ζήτησε αναμονή.
      if (ouraError == OuraErrorKind.rateLimited && backoff != null && ms < backoff) return;
    } else if (force) {
      if (!ouraCanSyncNow) return;
    } else {
      if (backoff != null && ms < backoff) return;
      if (tried != null && ms - tried < ouraMinInterval.inMilliseconds) return;
    }
    final from = range.from;
    final to = range.to;

    final epoch = _ouraEpoch;
    ouraTriedMs = ms;
    ouraSyncing = true;
    notifyListeners();
    try {
      final batch = await ouraLink.fetchNights(from, to, stepsBetween: watchStepsBetween, napLocks: _ouraNapLocks);
      if (epoch != _ouraEpoch) return; // αποσυνδέθηκε στο μεταξύ: τίποτα δεν κρατιέται
      final rows = await ouraRowsOffMain(batch.nights);
      if (epoch != _ouraEpoch) return;
      final changed = mergeOura(history, rows, from: from, to: to, plan: plan);
      final saved = await saveDaysNow(changed);
      if (epoch != _ouraEpoch) return;
      // E4: αν το αρχείο νυχτών δεν είχε διαβαστεί, πρώτα ξανά· αλλιώς οι νέες νύχτες μόνο στη μνήμη (ποτέ πάνω στις 45).
      if (ouraNightsReadFailed) await _readNightsFile();
      ouraNights = mergeOuraNights(ouraNights, batch.nights, from: from, to: to, today: today, keepDays: ouraDetailDays);
      if (!ouraNightsReadFailed) await _writeNights(encodeOuraNights(ouraNights));
      ouraError = null;
      // C9: ένα παλιότερο κομμάτι (ως 90 μέρες) μετά από καινούργια βάση, ώσπου να φτάσει στην αρχή του Oura.
      final older = saved ? ouraOlderRange() : null;
      var olderSaved = true;
      if (older != null) {
        final b2 = await ouraLink.fetchNights(older.from, older.to,
            stepsBetween: watchStepsBetween, napLocks: _ouraNapLocks);
        if (epoch != _ouraEpoch) return;
        final rows2 = await ouraRowsOffMain(b2.nights);
        if (epoch != _ouraEpoch) return;
        olderSaved = await saveDaysNow(mergeOura(history, rows2, from: older.from, to: older.to, plan: plan));
        if (olderSaved) ouraRefetchTo = older.next == null ? null : dateKey(older.next!);
      }
      if (saved && olderSaved) {
        ouraSyncedMs = ms;
        ouraSyncedTo = dateKey(today);
        ouraBackoffMs = null;
      } else {
        // Δεν γράφτηκε το ιστορικό: ξανά σε λίγο (όχι σε κάθε επιστροφή στην εφαρμογή).
        ouraBackoffMs = ms + ouraMinInterval.inMilliseconds;
      }
      if (batch.skipped > 0) {
        // Να το μάθουμε (μόνο πόσες, ποτέ ποιες τιμές).
        errors.report(StateError('Oura: ${batch.skipped} εγγραφές χωρίς απαραίτητα πεδία'), StackTrace.current,
            extra: {'where': 'oura-parse'});
      }
    } on OuraError catch (e) {
      if (epoch != _ouraEpoch) return;
      ouraError = e.kind;
      ouraBackoffMs = ms + ouraBackoffFor(e.kind, retryAfter: e.retryAfter).inMilliseconds;
      // Στο Sentry μόνο ό,τι δεν είναι φυσιολογικό (όχι δίκτυο, όχι 429)· μόνο το είδος.
      if (e.kind == OuraErrorKind.format ||
          e.kind == OuraErrorKind.noRefresh ||
          e.kind == OuraErrorKind.scopeMissing ||
          e.kind == OuraErrorKind.proxyNotConfigured ||
          e.kind == OuraErrorKind.proxyRejected) {
        errors.report(e, StackTrace.current, extra: {'where': 'oura-sync'});
      }
    } catch (e, st) {
      if (epoch != _ouraEpoch) return;
      ouraError = OuraErrorKind.format;
      ouraBackoffMs = ms + ouraBackoffFor(OuraErrorKind.format).inMilliseconds;
      errors.report(e, st, extra: {'where': 'oura-sync'});
    } finally {
      ouraSyncing = false;
      if (epoch == _ouraEpoch) await savePrefsNow();
      notifyListeners();
    }
  }

  /// «Ενημέρωση τώρα» από τη σελίδα Oura (το πολύ μία φορά το λεπτό).
  Future<void> syncOuraNow() => syncOura(force: true);

  /// Οι εγγραφές του αρχείου νυχτών μία-μία (μια παλιότερη δεν γράφει πάνω σε νεότερη).
  Future<void> _nightsWrites = Future.value();
  Future<void> _writeNights(String json) =>
      _nightsWrites = _nightsWrites.catchError((_) {}).then((_) => ouraNightsFile.write(json));

  @visibleForTesting
  void resetOuraForTest() {
    _ouraStarted = false;
  }
}

/// Η ανάγνωση του αρχείου νυχτών (έλεγχος 3, E4): [json] null = δεν υπάρχει αρχείο· [failed] = υπάρχει αλλά δεν
/// διαβάστηκε τώρα (ποτέ «δεν υπάρχει», που θα έγραφε 3 νύχτες πάνω στις 45).
typedef NightsRead = ({String? json, bool failed});

/// Η απάντηση της Kotlin {"state": missing|ok|error, "json"} (όπως το readPlan).
NightsRead parseNightsRead(Object? v) {
  if (v is! String) return (json: null, failed: true);
  try {
    final j = jsonDecode(v);
    if (j is! Map) return (json: null, failed: true);
    return switch (j['state']) {
      'missing' => (json: null, failed: false),
      'ok' when j['json'] is String => (json: j['json'] as String, failed: false),
      _ => (json: null, failed: true),
    };
  } catch (_) {
    return (json: null, failed: true);
  }
}

/// Οι λεπτομέρειες των τελευταίων νυχτών (ώρες, φάσεις, υπνάκοι) στο κινητό.
abstract class OuraNightsFile {
  Future<NightsRead> read();
  Future<void> write(String json);
}

class ChannelNightsFile implements OuraNightsFile {
  const ChannelNightsFile();

  @override
  Future<NightsRead> read() async {
    try {
      return parseNightsRead(await ChannelVault.channel.invokeMethod<String>('readNights'));
    } catch (_) {
      return (json: null, failed: true);
    }
  }

  @override
  Future<void> write(String json) async {
    try {
      await ChannelVault.channel.invokeMethod<bool>('writeNights', {'json': json});
    } catch (_) {}
  }
}

class MemoryNightsFile implements OuraNightsFile {
  String? content;

  /// Για τους ελέγχους: η ανάγνωση αποτυγχάνει (E4).
  bool failRead = false;
  int writes = 0;

  @override
  Future<NightsRead> read() async => failRead ? (json: null, failed: true) : (json: content, failed: false);

  @override
  Future<void> write(String json) async {
    writes++;
    content = json;
  }
}

/// Έλεγχος 2, C12: «τώρα» για την πρώτη νύχτα μιας σύνδεσης. Αν το ρολόι του κινητού είναι πάνω από μία μέρα μπροστά
/// από την ώρα του διακομιστή της Oura ([server], κεφαλίδα Date), ισχύει η ώρα του διακομιστή (σε τοπική ώρα).
DateTime clampToServer(DateTime phone, DateTime? server) {
  if (server == null) return phone;
  final local = server.toLocal();
  return phone.difference(local) > const Duration(days: 1) ? local : phone;
}
