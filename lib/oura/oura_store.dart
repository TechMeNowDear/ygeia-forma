/// Το Oura μέσα στην κατάσταση της εφαρμογής (HealthStore): σύνδεση, ανάγνωση, αποσύνδεση, κατάσταση.
///
/// - Διαβάζει ΜΟΝΟ όταν ανοίγει η εφαρμογή ή επιστρέφω σε αυτήν (μαζί με τη Samsung), το πολύ κάθε 30 λεπτά,
///   τις τελευταίες 3 μέρες. Καμία δουλειά στο παρασκήνιο, καμία συνεχής ανανέωση.
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
      OuraErrorKind.reconnect || OuraErrorKind.noRefresh => const Duration(hours: 6),
      OuraErrorKind.subscription || OuraErrorKind.format => const Duration(hours: 1),
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

  Future<bool> savePrefsNow();
  Future<bool> setPlan(SourcePlan p);

  // Οι ρυθμίσεις για το πότε διαβάστηκε / δοκιμάστηκε το Oura (στο Prefs).
  int? get ouraSyncedMs;
  set ouraSyncedMs(int? v);
  String? get ouraSyncedTo;
  set ouraSyncedTo(String? v);
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

  /// Οι τελευταίες νύχτες του Oura με τις λεπτομέρειές τους, παλιότερη πρώτη.
  List<OuraNight> ouraNights = const [];

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
    try {
      ouraHasTokens = await ouraLink.hasTokens;
    } on OuraError {
      // Η αποθήκευση δεν απάντησε τώρα: τα tokens δεν θεωρούνται χαμένα (ξανά στην επόμενη ανάγνωση).
      ouraHasTokens = plan.ouraFrom != null;
    } catch (_) {}
    try {
      ouraNights = decodeOuraNights(await ouraNightsFile.read());
    } catch (_) {}
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
    if (!ouraHasTokens || ouraError == OuraErrorKind.reconnect || ouraError == OuraErrorKind.noRefresh) {
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

  /// Το αποτέλεσμα της τελευταίας σύνδεσης, για να το δείξει η οθόνη (μία φορά).
  OuraErrorKind? ouraLoginError;
  bool ouraJustConnected = false;

  /// Η επιστροφή από την Oura. Σειρά: ανταλλαγή του κωδικού → ΠΡΩΤΑ το σχέδιο πηγών (αρχείο) → ΜΕΤΑ τα tokens.
  /// Αν δεν γραφτεί το σχέδιο, τα tokens δεν κρατιούνται (ανακαλούνται)· αν δεν γραφτούν τα tokens, το σχέδιο
  /// επιστρέφει όπως ήταν. Η πρώτη νύχτα ήρθε μαζί με το state ([beginOuraLogin]).
  Future<void> completeOuraLogin(String uri) async {
    if (parseCallback(uri) == null) return;
    // Χωρίς γνωστό σχέδιο πηγών δεν συνδέεται (δεν θα μπορούσε να αλλάξει η πηγή): ο κωδικός δεν χρησιμοποιείται.
    if (!canChangePlan) {
      ouraLoginError = OuraErrorKind.cancelled;
      notifyListeners();
      return;
    }
    ouraConnecting = true;
    ouraLoginError = null;
    notifyListeners();
    final epoch = _ouraEpoch;
    try {
      final ex = await ouraLink.exchange(uri);
      if (ex == null) return;
      if (epoch != _ouraEpoch) {
        await ouraLink.discard(ex.tokens);
        return;
      }
      final now = ouraClock();
      final today = dayOf(now);
      // Χωρίς αποθηκευμένη απόφαση (παλιά εκκρεμής σύνδεση): από απόψε. Ποτέ πριν από σήμερα.
      var from = ex.from ?? DateTime(today.year, today.month, today.day + 1);
      if (from.isBefore(today)) from = today;
      final before = plan;
      final next = plan.withEra(Source.oura, from);
      final changed = next != plan;
      if (changed && !await setPlan(next)) {
        // Η πηγή δεν άλλαξε: τα tokens δεν κρατιούνται.
        await ouraLink.discard(ex.tokens);
        ouraLoginError = OuraErrorKind.cancelled;
        return;
      }
      if (epoch != _ouraEpoch || !await ouraLink.adopt(ex.tokens, ex.gen)) {
        // Τα tokens δεν γράφτηκαν (ή αποσυνδέθηκε στο μεταξύ): το σχέδιο επιστρέφει, τίποτα μισό.
        if (changed && epoch == _ouraEpoch) await setPlan(before);
        await ouraLink.discard(ex.tokens);
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
      // Αν η πρώτη νύχτα είναι η σημερινή, διαβάζεται αμέσως (μπορεί να έχει ήδη έρθει).
      if (!from.isAfter(today)) unawaited(syncOura(force: true));
    } on OuraError catch (e) {
      ouraLoginError = e.kind;
      errors.report(e, StackTrace.current, extra: {'where': 'oura-login'});
    } catch (e, st) {
      ouraLoginError = OuraErrorKind.format;
      errors.report(e, st, extra: {'where': 'oura-login'});
    } finally {
      ouraConnecting = false;
      notifyListeners();
    }
  }

  /// Μια σύνδεση έμεινε μισή και καθαρίστηκε στην εκκίνηση ([_cleanHalfConnection]).
  bool ouraIncomplete = false;

  /// Μισή σύνδεση στην εκκίνηση (π.χ. έκλεισε η εφαρμογή ανάμεσα στο σχέδιο και στα tokens), χωρίς καμία ένδειξη
  /// Oura (νύχτες, ανάγνωση, τιμές «o.*»):
  /// - tokens χωρίς εποχή Oura → σβήνονται·
  /// - εποχή Oura από σήμερα ή αύριο χωρίς tokens → φεύγει.
  /// Και στις δύο: «Η σύνδεση δεν ολοκληρώθηκε· δοκίμασε ξανά». Ποτέ «άγνωστο σχέδιο» γι' αυτό.
  Future<void> _cleanHalfConnection() async {
    if (!historyReady || !canChangePlan) return;
    if (ouraNights.isNotEmpty || ouraSyncedTo != null) return;
    if (history.values.any((r) => r.keys.any(ouraKeySet.contains))) return;
    final today = dayOf(ouraClock());
    final last = plan.eras.isEmpty ? null : plan.eras.last;
    if (ouraHasTokens && !plan.eras.any((e) => e.source == Source.oura)) {
      _ouraEpoch++;
      await ouraLink.disconnect();
      ouraHasTokens = false;
      ouraIncomplete = true;
      ouraLoginError = OuraErrorKind.incomplete;
    } else if (!ouraHasTokens && last != null && last.source == Source.oura && !last.from.isBefore(today)) {
      if (await setPlan(SourcePlan(plan.eras.sublist(0, plan.eras.length - 1)))) {
        ouraIncomplete = true;
        ouraLoginError = OuraErrorKind.incomplete;
        ouraConnectedMs = null;
        await savePrefsNow();
      }
    }
  }

  /// Πριν από τις 04:00: «η νύχτα που κοιμάσαι τώρα»· μετά: «η νύχτα που μόλις τελείωσε» (ακόμα κι αν η σύνδεση
  /// έγινε μέσα στη νύχτα: το πρωί έχει ήδη τελειώσει).
  String get ouraFirstNightText {
    final asleep = ouraClock().hour < 4;
    return asleep ? 'Η νύχτα που κοιμάσαι τώρα μετρά από το δαχτυλίδι' : 'Η νύχτα που μόλις τελείωσε μετρά από το δαχτυλίδι';
  }

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
    _ouraEpoch++;
    final today = dayOf(ouraClock());
    final from = DateTime(today.year, today.month, today.day + 1);
    await ouraLink.disconnect();
    ouraHasTokens = false;
    ouraError = null;
    ouraTriedMs = null;
    ouraBackoffMs = null;
    ouraConnectedMs = null;
    ouraIncomplete = false;
    if (plan.eras.any((e) => e.source == Source.oura && e.from.isAfter(today))) {
      await setPlan(SourcePlan([for (final e in plan.eras) if (!(e.source == Source.oura && e.from.isAfter(today))) e]));
    }
    if (plan.nightSource(from) == Source.oura) await setPlan(plan.withEra(Source.none, from));
    await savePrefsNow();
    notifyListeners();
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

  Future<void> _syncOnce(bool force) async {
    if (!historyReady || !prefsReady || !planReady) return;
    final now = ouraClock();
    final today = dayOf(now);
    // Μόνο όταν το Oura είναι πηγή κάποιας νύχτας ως σήμερα: χωρίς σύνδεση δεν γίνεται καμία κλήση.
    final f = plan.ouraFrom;
    if (f == null || !ouraHasTokens || f.isAfter(today)) return;
    // Το Oura δεν είναι πηγή σήμερα (π.χ. «ξανά από το ρολόι») και έχει διαβαστεί ως το τέλος του: τίποτα να
    // διαβαστεί πια, ούτε με tokens.
    if (plan.nightSource(today) != Source.oura) {
      DateTime? w;
      for (final e in plan.eras) {
        if (!e.from.isAfter(today)) w = e.from;
      }
      final synced = ouraSyncedTo == null ? null : parseDateKey(ouraSyncedTo!);
      if (w != null && synced != null && !synced.isBefore(DateTime(w.year, w.month, w.day - 1))) return;
    }
    final ms = now.millisecondsSinceEpoch;
    var tried = ouraTriedMs;
    var backoff = ouraBackoffMs;
    // Χρόνοι από ρολόι που είχε πάει μπροστά: ληγμένοι (αλλιώς η ανάγνωση θα έμενε μπλοκαρισμένη).
    if (tried != null && tried > ms) tried = null;
    if (backoff != null && backoff > ms + ouraMaxBackoff.inMilliseconds) backoff = null;
    if (force) {
      if (!ouraCanSyncNow) return;
    } else {
      if (backoff != null && ms < backoff) return;
      if (tried != null && ms - tried < ouraMinInterval.inMilliseconds) return;
    }

    // Ποιες μέρες: τις τελευταίες [ouraRecentDays]· αν δεν έχει διαβαστεί για καιρό, από εκεί που είχε μείνει
    // (το πολύ 60 μέρες πίσω). Ποτέ πριν από τη σύνδεση.
    final syncedTo = ouraSyncedTo == null ? null : parseDateKey(ouraSyncedTo!);
    var from = DateTime(today.year, today.month, today.day - (ouraRecentDays - 1));
    if (syncedTo == null || syncedTo.isBefore(from)) {
      from = syncedTo == null ? f : DateTime(syncedTo.year, syncedTo.month, syncedTo.day - 1);
    }
    final floor = DateTime(today.year, today.month, today.day - 60);
    if (from.isBefore(floor)) from = floor;
    if (from.isBefore(f)) from = f;

    final epoch = _ouraEpoch;
    ouraTriedMs = ms;
    ouraSyncing = true;
    notifyListeners();
    try {
      final batch = await ouraLink.fetchNights(from, today);
      if (epoch != _ouraEpoch) return; // αποσυνδέθηκε στο μεταξύ: τίποτα δεν κρατιέται
      final rows = await ouraRowsOffMain(batch.nights);
      if (epoch != _ouraEpoch) return;
      final changed = mergeOura(history, rows, from: from, to: today, plan: plan);
      final saved = await saveDaysNow(changed);
      if (epoch != _ouraEpoch) return;
      ouraNights = mergeOuraNights(ouraNights, batch.nights, from: from, to: today, today: today, keepDays: ouraDetailDays);
      await _writeNights(encodeOuraNights(ouraNights));
      ouraError = null;
      if (saved) {
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
      if (e.kind == OuraErrorKind.format || e.kind == OuraErrorKind.noRefresh) {
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

/// Οι λεπτομέρειες των τελευταίων νυχτών (ώρες, φάσεις, υπνάκοι) στο κινητό.
abstract class OuraNightsFile {
  Future<String?> read();
  Future<void> write(String json);
}

class ChannelNightsFile implements OuraNightsFile {
  const ChannelNightsFile();

  @override
  Future<String?> read() async {
    try {
      return await ChannelVault.channel.invokeMethod<String>('readNights');
    } catch (_) {
      return null;
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

  @override
  Future<String?> read() async => content;

  @override
  Future<void> write(String json) async => content = json;
}
