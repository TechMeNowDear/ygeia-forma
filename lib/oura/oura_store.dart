/// Το Oura μέσα στην κατάσταση της εφαρμογής (HealthStore): σύνδεση, ανάγνωση, αποσύνδεση, κατάσταση.
///
/// - Διαβάζει ΜΟΝΟ όταν ανοίγει η εφαρμογή ή επιστρέφω σε αυτήν (μαζί με τη Samsung), το πολύ κάθε 30 λεπτά,
///   τις τελευταίες 3 μέρες. Καμία δουλειά στο παρασκήνιο, καμία συνεχής ανανέωση.
/// - Γράφει στο ιστορικό ΜΟΝΟ τις μέρες που η «νύχτα» έρχεται από το Oura (δες sources.dart), με τα κλειδιά του.
/// - Κρατά τις λεπτομέρειες των τελευταίων νυχτών (ώρες, φάσεις, υπνάκοι) για τις οθόνες.
library;

import 'dart:async';
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

/// Η αποθήκευση στο κινητό (Android Keystore) μέσω της γέφυρας «ygeia/oura».
class ChannelVault implements OuraVault {
  const ChannelVault();
  static const channel = MethodChannel('ygeia/oura');

  @override
  Future<String?> load(String name) async {
    try {
      return await channel.invokeMethod<String>('vaultLoad', {'name': name});
    } catch (_) {
      return null;
    }
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
  /// Δεν έχει συνδεθεί ποτέ (ή αποσυνδέθηκε): η εφαρμογή δουλεύει όπως πάντα.
  off,

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

mixin OuraStore on ChangeNotifier {
  // Από το HealthStore.
  Map<String, Map<String, double>> get history;
  SourcePlan get plan;
  bool get historyReady;
  bool get prefsReady;
  Future<bool> saveDaysNow(Set<String> keys);
  Future<bool> savePrefsNow();
  Future<bool> setPlan(SourcePlan p);

  // Οι ρυθμίσεις για το πότε διαβάστηκε το Oura (στο Prefs).
  int? get ouraSyncedMs;
  set ouraSyncedMs(int? v);
  String? get ouraSyncedTo;
  set ouraSyncedTo(String? v);

  /// Η σύνδεση (αντικαθίσταται στους ελέγχους).
  OuraLink ouraLink = OuraLink(vault: const ChannelVault());

  /// Για τους ελέγχους: «τώρα».
  DateTime Function() ouraClock = DateTime.now;

  /// Οι τελευταίες νύχτες του Oura με τις λεπτομέρειές τους, παλιότερη πρώτη.
  List<OuraNight> ouraNights = const [];

  /// Οι ώρες ύπνου του Oura (μόνο για τους παλμούς της μέρας).
  SleepWindows get ouraWindows => ouraSleepWindows(ouraNights);

  bool ouraHasTokens = false;
  bool ouraSyncing = false;
  bool ouraConnecting = false;

  /// Το τελευταίο σφάλμα (για την κατάσταση· ποτέ με προσωπικά στοιχεία).
  OuraErrorKind? ouraError;
  DateTime? _ouraBackoffUntil;
  bool _ouraStarted = false;

  /// Η σύνδεση με την Oura είναι διαθέσιμη (έχει μπει Client ID).
  bool get ouraConfigured => ouraLink.configured;

  /// Το Oura είναι η πηγή του ύπνου σήμερα.
  bool get ouraActive => plan.nightSource(dayOf(ouraClock())) == Source.oura;

  /// Ο ύπνος σήμερα δεν έχει πηγή (αποσυνδέθηκε το Oura).
  bool get sleepUnsourced => plan.nightSource(dayOf(ouraClock())) == Source.none;

  DateTime? get ouraLastSync => ouraSyncedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(ouraSyncedMs!);

  Future<void> startOura() async {
    if (_ouraStarted) return;
    _ouraStarted = true;
    try {
      ouraHasTokens = await ouraLink.hasTokens;
      ouraNights = decodeOuraNights(await _readNights());
    } catch (_) {}
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

  Future<String?> _readNights() async {
    try {
      return await ChannelVault.channel.invokeMethod<String>('readNights');
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeNights(List<OuraNight> nights) async {
    try {
      await ChannelVault.channel.invokeMethod<bool>('writeNights', {'json': encodeOuraNights(nights)});
    } catch (_) {}
  }

  /// Η κατάσταση για τις κάρτες της Σήμερα και τη σελίδα «Oura».
  OuraStatus get ouraStatus {
    final today = dayOf(ouraClock());
    final src = plan.nightSource(today);
    if (src == Source.none) return OuraStatus.disconnected;
    if (src != Source.oura) return OuraStatus.off;
    if (!ouraHasTokens || ouraError == OuraErrorKind.reconnect) return OuraStatus.reconnect;
    if (ouraError == OuraErrorKind.subscription) return OuraStatus.subscription;
    if (ouraError != null) return OuraStatus.retry;
    if (ouraNightFor(today)?.main != null) return OuraStatus.ok;
    return ouraClock().hour < 12 ? OuraStatus.waiting : OuraStatus.missing;
  }

  OuraNight? ouraNightFor(DateTime day) {
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

  /// Η τελευταία νύχτα που ήρθε από το δαχτυλίδι.
  OuraNight? get lastOuraNight {
    for (final n in ouraNights.reversed) {
      if (n.main != null) return n;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Σύνδεση
  // ---------------------------------------------------------------------------

  /// Ανοίγει τη σελίδα της Oura στον browser. Επιστρέφει σφάλμα για την οθόνη, ή null αν άνοιξε.
  Future<OuraErrorKind?> beginOuraLogin() async {
    if (!ouraConfigured) return OuraErrorKind.notConfigured;
    try {
      final url = await ouraLink.begin();
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

  /// Η επιστροφή από την Oura. Μόνο αν πετύχει αλλάζει η πηγή του ύπνου (από σήμερα).
  Future<void> completeOuraLogin(String uri) async {
    ouraConnecting = true;
    ouraLoginError = null;
    notifyListeners();
    try {
      final ok = await ouraLink.complete(uri);
      if (!ok) return;
      ouraHasTokens = true;
      ouraError = null;
      _ouraBackoffUntil = null;
      final today = dayOf(ouraClock());
      if (plan.nightSource(today) != Source.oura) {
        await setPlan(plan.withEra(Source.oura, today));
        // Τιμές νύχτας του ρολογιού που είχαν γραφτεί ήδη για σήμερα φεύγουν (η νύχτα είναι πια του Oura).
        await saveDaysNow(stripForeignWatchNight(history, plan, from: today));
      }
      ouraJustConnected = true;
      ouraSyncedMs = null; // πρώτη ανάγνωση αμέσως
      await savePrefsNow();
      unawaited(syncOura(force: true));
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

  /// Αποσύνδεση: ανάκληση, σβήσιμο tokens, τα δεδομένα μένουν. Από σήμερα ο ύπνος δεν έχει πηγή
  /// (κενές νύχτες), ώσπου να συνδεθεί ξανά ή να διαλέξει ρητά το ρολόι ([sleepFromWatchAgain]).
  Future<void> disconnectOura() async {
    await ouraLink.disconnect();
    ouraHasTokens = false;
    ouraError = null;
    final today = dayOf(ouraClock());
    if (plan.nightSource(today) == Source.oura) await setPlan(plan.withEra(Source.none, today));
    notifyListeners();
  }

  /// Αναίρεση της αποσύνδεσης αμέσως μετά (το πλήκτρο «Αναίρεση»): μόνο το σχέδιο πηγών επιστρέφει.
  /// Η σύνδεση χρειάζεται ξανά «Σύνδεση με Oura» (τα tokens έχουν ανακληθεί).
  Future<void> restorePlan(SourcePlan previous) => setPlan(previous);

  /// Ρητή επιλογή: ο ύπνος ξανά από το ρολόι, από σήμερα (νέα αλλαγή πηγής).
  Future<void> sleepFromWatchAgain() async {
    final today = dayOf(ouraClock());
    await setPlan(plan.withEra(Source.watch, today));
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Ανάγνωση
  // ---------------------------------------------------------------------------

  Future<void>? _sync;

  /// Διαβάζει το Oura αν είναι η πηγή του ύπνου και πέρασε αρκετή ώρα (ή [force]). Μία ανάγνωση τη φορά.
  Future<void> syncOura({bool force = false}) => _sync ??= _syncOnce(force).whenComplete(() => _sync = null);

  Future<void> _syncOnce(bool force) async {
    if (!historyReady || !prefsReady) return;
    final now = ouraClock();
    final today = dayOf(now);
    // Μόνο όταν το Oura είναι (ή ήταν πρόσφατα) πηγή: χωρίς σύνδεση δεν γίνεται καμία κλήση.
    final f = plan.ouraFrom;
    if (f == null || !ouraHasTokens) return;
    if (_ouraBackoffUntil != null && now.isBefore(_ouraBackoffUntil!)) return;
    final last = ouraLastSync;
    if (!force && last != null && now.difference(last) < ouraMinInterval && ouraError == null) return;

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
    if (from.isAfter(today)) from = today;

    ouraSyncing = true;
    notifyListeners();
    try {
      final batch = await ouraLink.fetchNights(from, today);
      // Σε άλλο νήμα αν είναι πολλά (πρώτη ανάγνωση): εδώ μόνο λίγες εκατοντάδες εγγραφές το πολύ.
      final rows = batch.nights.length > 20
          ? await Isolate.run(() => ouraRows(batch.nights))
          : ouraRows(batch.nights);
      final changed = mergeOura(history, rows, from: from, to: today, plan: plan);
      final saved = await saveDaysNow(changed);
      ouraNights = mergeOuraNights(ouraNights, batch.nights, from: from, to: today, today: today, keepDays: ouraDetailDays);
      await _writeNights(ouraNights);
      ouraError = null;
      _ouraBackoffUntil = null;
      if (saved) {
        ouraSyncedMs = now.millisecondsSinceEpoch;
        ouraSyncedTo = dateKey(today);
        await savePrefsNow();
      }
      if (batch.skipped > 0) {
        // Να το μάθουμε (μόνο πόσες, ποτέ ποιες τιμές).
        errors.report(StateError('Oura: ${batch.skipped} εγγραφές χωρίς απαραίτητα πεδία'), StackTrace.current,
            extra: {'where': 'oura-parse'});
      }
    } on OuraError catch (e) {
      ouraError = e.kind;
      if (e.kind == OuraErrorKind.reconnect) ouraHasTokens = await ouraLink.hasTokens;
      if (e.kind == OuraErrorKind.rateLimited) {
        _ouraBackoffUntil = now.add(e.retryAfter ?? const Duration(minutes: 15));
      } else if (e.kind == OuraErrorKind.network) {
        _ouraBackoffUntil = now.add(const Duration(minutes: 5));
      }
      // Στο Sentry μόνο ό,τι δεν είναι φυσιολογικό (όχι δίκτυο, όχι 429)· μόνο το είδος.
      if (e.kind == OuraErrorKind.format || e.kind == OuraErrorKind.noRefresh) {
        errors.report(e, StackTrace.current, extra: {'where': 'oura-sync'});
      }
    } catch (e, st) {
      ouraError = OuraErrorKind.format;
      errors.report(e, st, extra: {'where': 'oura-sync'});
    } finally {
      ouraSyncing = false;
      notifyListeners();
    }
  }

  /// «Ενημέρωση τώρα» από τη σελίδα Oura.
  Future<void> syncOuraNow() => syncOura(force: true);

  @visibleForTesting
  void resetOuraForTest() {
    _ouraStarted = false;
    _ouraBackoffUntil = null;
  }
}
