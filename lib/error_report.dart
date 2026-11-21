// Αναφορά σφαλμάτων στο Sentry (project «ygeia-forma», EU), χωρίς βιβλιοθήκη.
//
// Τι στέλνει: το σφάλμα, τη στοίβα (σε ποιο σημείο του κώδικα έγινε), την οθόνη,
// την έκδοση, το μοντέλο της συσκευής και την έκδοση Android.
// Τι ΔΕΝ στέλνει ποτέ: δεδομένα υγείας ή φαγητού, ονόματα, λογαριασμούς, τοποθεσία.
//
// Μπαταρία: τίποτα δεν τρέχει μόνο του. Στέλνει μόνο όταν γίνει σφάλμα, μία φορά
// λίγο μετά το άνοιγμα και όταν επιστρέφω στην εφαρμογή — και μόνο αν υπάρχει κάτι στην ουρά.
// Χωρίς ίντερνετ: τα σφάλματα μένουν ως αρχεία στη συσκευή (το πολύ 20) και φεύγουν αργότερα.
// Το ίδιο αρχείο ουράς γεμίζει και η πλευρά Android (ErrorQueue.kt) όταν κρασάρει ο κώδικας Kotlin.
//
// Διακόπτης (έλεγχος 9/11, E3-05 / V-A-23): Ρυθμίσεις › Απόρρητο › «Αναφορές σφαλμάτων». Ανοιχτός από την αρχή, όπως
// λέει η πολιτική απορρήτου (έννομο συμφέρον, με δικαίωμα αντίρρησης). Κλειστός: τίποτα δεν μπαίνει στην ουρά ούτε
// στέλνεται, και ό,τι περίμενε σβήνεται. Η επιλογή ζει στην πλευρά Android (ErrorQueue.kt), ώστε να ισχύει και για τα
// κρασαρίσματα Kotlin πριν ανοίξει η Flutter· η Flutter τη μαθαίνει με το «info» και ΔΕΝ στέλνει τίποτα πριν τη μάθει.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Δημόσιο κλειδί αποστολής (DSN) του project. Δεν είναι μυστικό: επιτρέπει μόνο αποστολή σφαλμάτων,
/// όχι ανάγνωση. Το Sentry το σχεδιάζει να μπαίνει μέσα στις εφαρμογές.
const _dsnKey = '43f057892c4faefcdddc9398a17863c7';
final sentryEndpoint = Uri.parse(
  'https://o4512356027793408.ingest.de.sentry.io/api/4512356100079696/envelope/'
  '?sentry_key=$_dsnKey&sentry_version=7&sentry_client=ygeia-forma-report%2F1',
);

/// Πόσα σφάλματα κρατάει η ουρά στη συσκευή.
const maxQueue = 20;

/// Πόσα στέλνει το πολύ τη μέρα (προστασία από βρόχο σφαλμάτων).
const maxPerDay = 30;

/// Το ίδιο σφάλμα μία φορά το λεπτό.
const dedupeWindow = Duration(minutes: 1);

/// Αποστολή ενός φακέλου (envelope)· επιστρέφει τον κωδικό HTTP ή πετάει σφάλμα δικτύου.
typedef Poster = Future<int> Function(String body);

Future<int> httpPost(String body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.postUrl(sentryEndpoint).timeout(const Duration(seconds: 15));
    req.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
    req.add(utf8.encode(body));
    final res = await req.close().timeout(const Duration(seconds: 15));
    await res.drain<void>();
    return res.statusCode;
  } finally {
    client.close(force: true);
  }
}

class ErrorReporter {
  ErrorReporter({
    this.dir,
    this.release = 'ygeia-forma@dev',
    this.environment = kReleaseMode ? 'android' : 'debug',
    this.device = const {},
    Poster? post,
    DateTime Function()? clock,
    this.persist,
  })  : _post = post ?? httpPost,
        _clock = clock ?? DateTime.now;

  /// Αν επιτρέπεται η αποστολή (ο διακόπτης «Αναφορές σφαλμάτων»). Ως να έρθει η επιλογή από την πλευρά Android
  /// ([configure]) δεν στέλνεται τίποτα ούτως ή άλλως (δεν υπάρχει φάκελος ουράς).
  final ValueNotifier<bool> sending = ValueNotifier<bool>(true);
  bool get enabled => sending.value;

  /// Πού γράφεται η επιλογή (στην εφαρμογή: η πλευρά Android). Στις δοκιμές: τίποτα ή ψεύτικο.
  Future<void> Function(bool on)? persist;

  /// Φάκελος της ουράς (files/errq στη συσκευή). Αν λείπει, η αναφορά απλώς δεν κάνει τίποτα.
  Directory? dir;
  String release;
  final String environment;

  /// Μοντέλο συσκευής και έκδοση Android (από την πλευρά Android).
  Map<String, String> device;

  final Poster _post;
  final DateTime Function() _clock;

  /// Η οθόνη που βλέπω τώρα, π.χ. «Υγεία › Ύπνος» ή «Διατροφή › Ημερολόγιο › Ποσότητα».
  String get screen => [base, ..._routes].join(' › ');
  String base = 'Σήμερα';
  final List<String> _routes = [];

  final Map<String, DateTime> _recent = {};
  final List<Map<String, Object?>> _early = [];

  /// Τα τελευταία σφάλματα, για την «Αναφορά για έλεγχο» (στη μνήμη μπαίνουν και με κλειστή την αποστολή· δεν φεύγουν από
  /// το κινητό αν δεν τα στείλει ο ίδιος ο χρήστης).
  /// Έλεγχος 21/11 (K8-06): με ΑΝΟΙΧΤΕΣ τις «Αναφορές σφαλμάτων» γράφονται και σε ένα μικρό αρχείο ([recentFile], ως
  /// [recentMax] γραμμές) και διαβάζονται στο επόμενο άνοιγμα, σημειωμένα «run: previous». Πριν ζούσαν ΜΟΝΟ στη μνήμη: ό,τι
  /// πήγε στραβά χθες το βράδυ είχε χαθεί όταν έβγαινε η αναφορά το επόμενο πρωί.
  /// K8-R-10 (ανεξάρτητος έλεγχος): με ΚΛΕΙΣΤΕΣ τις αναφορές δεν γράφεται ούτε διαβάζεται αρχείο, και το κλείσιμο το σβήνει
  /// ([_clearQueue]· το ίδιο κάνει η πλευρά Android, ErrorQueue.kt): η πολιτική απορρήτου λέει «κλειστές, όσες περίμεναν στο
  /// κινητό σβήνονται», και ένα αρχείο σφαλμάτων που μένει θα την έκανε ψέμα.
  final List<Map<String, Object?>> recentErrors = [];
  static const recentMax = 30;

  /// Το αρχείο των τελευταίων σφαλμάτων, μέσα στον φάκελο της ουράς (δεν μπαίνει σε κανένα αντίγραφο). Το όνομα ΔΕΝ
  /// τελειώνει σε «.json»: ό,τι τελειώνει σε «.json» εκεί είναι γεγονός προς αποστολή (το στέλνει και το σβήνει η ουρά,
  /// από εδώ και από την πλευρά Android)· αυτό δεν στέλνεται ποτέ (όπως το «.count»).
  static const recentFile = '.recent';
  Future<void>? _recentReading;
  Future<void> _recentWrites = Future.value();
  final Map<String, DateTime> _recentSaved = {};

  /// Διαβάζει ΜΙΑ φορά τα σφάλματα της προηγούμενης εκτέλεσης και τα βάζει ΠΡΙΝ από τα τωρινά, με «run: previous».
  /// K8-R-09 (ανεξάρτητος έλεγχος): η ανάγνωση είναι ένα Future που το περιμένουν ΟΛΟΙ. Πριν ένα bool γινόταν true πριν
  /// τελειώσει η ανάγνωση: σφάλμα που αναφερόταν εκείνα τα ms έγραφε το αρχείο μόνο με τον εαυτό του και τα σφάλματα της
  /// προηγούμενης εκτέλεσης χάνονταν από τον δίσκο (ή διαβάζονταν διπλά). Χωρίς φάκελο ή με κλειστές αναφορές: τίποτα.
  Future<void> _readRecent() {
    if (dir == null || !enabled) return Future.value();
    return _recentReading ??= _doReadRecent();
  }

  Future<void> _doReadRecent() async {
    final d = dir;
    if (d == null) return;
    try {
      final f = File('${d.path}/$recentFile');
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! List) return;
      final old = <Map<String, Object?>>[
        for (final x in j)
          if (x is Map) {for (final e in x.entries) '${e.key}': e.value, 'run': 'previous'},
      ];
      recentErrors.insertAll(0, old);
      if (recentErrors.length > recentMax) recentErrors.removeRange(0, recentErrors.length - recentMax);
    } catch (_) {
      // Χαλασμένο αρχείο: σαν να μην υπήρχε.
    }
  }

  /// Γράφει τα [recentErrors] στο αρχείο (μία εγγραφή τη φορά, με τη σειρά· κάθε εγγραφή γράφει ό,τι υπάρχει ΤΗ ΣΤΙΓΜΗ που
  /// έρχεται η σειρά της, και πάντα μετά την ανάγνωση της προηγούμενης εκτέλεσης). Χωρίς φάκελο ή με κλειστές αναφορές:
  /// τίποτα.
  Future<void> _writeRecent() {
    final d = dir;
    if (d == null || !enabled) return Future.value();
    return _recentWrites = _recentWrites.then((_) async {
      try {
        await _readRecent();
        if (!enabled) return;
        if (!await d.exists()) await d.create(recursive: true);
        await File('${d.path}/$recentFile').writeAsString(jsonEncode(recentErrors), flush: true);
      } catch (_) {
        // Η αναφορά σφαλμάτων δεν πρέπει ποτέ να χαλάσει την εφαρμογή.
      }
    });
  }

  /// Σβήνει το αρχείο των τελευταίων σφαλμάτων (κλείσιμο των «Αναφορών σφαλμάτων»): μετά από ό,τι εγγραφή είναι στη σειρά.
  Future<void> _deleteRecent() {
    final d = dir;
    if (d == null) return Future.value();
    return _recentWrites = _recentWrites.then((_) async {
      try {
        final f = File('${d.path}/$recentFile');
        if (await f.exists()) await f.delete();
      } catch (_) {}
    });
  }

  /// Φάκελος, έκδοση και συσκευή, όταν έρθουν από την πλευρά Android.
  /// Ό,τι σφάλμα έγινε ως τότε μπαίνει τώρα στην ουρά.
  Future<void> configure({required Directory dir, required String release, required Map<String, String> device, bool enabled = true}) async {
    this.dir = dir;
    this.release = release;
    this.device = device;
    sending.value = enabled;
    // K8-06: τα σφάλματα της προηγούμενης εκτέλεσης· και ό,τι έγινε ως τώρα σε αυτήν γράφεται (αν έγινε κάτι).
    final hadNow = recentErrors.isNotEmpty;
    await _readRecent();
    if (hadNow) await _writeRecent();
    final early = List.of(_early);
    _early.clear();
    if (!enabled) {
      await _clearQueue();
      return;
    }
    for (final e in early) {
      e['release'] = release;
      e['contexts'] = _contexts();
      try {
        await _enqueue(e);
      } catch (_) {}
    }
  }

  Map<String, Object?> _contexts() => {
        'os': {'name': 'Android', if (device['android'] != null) 'version': device['android']},
        'device': {if (device['model'] != null) 'model': device['model']},
      };
  bool _busy = false;

  /// Σφάλματα που είναι φυσιολογικά (χωρίς ίντερνετ, αργή σύνδεση) δεν αναφέρονται.
  static bool isNoise(Object e) =>
      e is SocketException ||
      e is HttpException ||
      e is HandshakeException ||
      e is TimeoutException ||
      e is TlsException;

  /// Κεντρική κλήση. Δεν πετάει ποτέ σφάλμα η ίδια· οι κλήσεις της εφαρμογής δεν την περιμένουν.
  Future<void> report(Object error, StackTrace? stack, {bool handled = true, Map<String, Object?> extra = const {}}) async {
    try {
      if (isNoise(error)) return;
      final entry = <String, Object?>{
        'at': _clock().toIso8601String(),
        // K8-13: και σε ms (η ώρα χωρίς ζώνη δεν ξεχωρίζει την επαναλαμβανόμενη ώρα της αλλαγής ώρας).
        'atMs': _clock().millisecondsSinceEpoch,
        'type': (error is FlutterErrorDetails ? error.exception : error).runtimeType.toString(),
        'message': _message(error),
        'screen': screen,
        'handled': handled,
        'frames': [
          for (final f in parseDartStack(stack?.toString() ?? '').reversed.take(8))
            '${f['function'] ?? ''} ${f['filename'] ?? ''}:${f['lineno'] ?? ''}',
        ],
      };
      recentErrors.add(entry);
      if (recentErrors.length > recentMax) recentErrors.removeAt(0);
      // K8-06: και στο αρχείο (με ανοιχτές τις αναφορές), ώστε να επιζήσει από το κλείσιμο της εφαρμογής.
      // Το ίδιο σφάλμα γράφεται στο αρχείο το πολύ μία φορά στο [dedupeWindow]: ένα σφάλμα που επαναλαμβάνεται σε κάθε
      // καρέ δεν γράφει στον δίσκο σε κάθε καρέ (μπαταρία). Η υπογραφή από τη δική του γραμμή (K8-R-09: πριν από την
      // τελευταία της λίστας, που μετά από αναμονή μπορεί να είναι άλλου σφάλματος).
      final savedSig = '${entry['type']}:${entry['message']}';
      final savedNow = _clock();
      final savedLast = _recentSaved[savedSig];
      if (savedLast == null || savedNow.difference(savedLast) >= dedupeWindow) {
        _recentSaved[savedSig] = savedNow;
        await _writeRecent();
      }
      if (!enabled) return;
      final sig = '${error.runtimeType}:${_firstLine(error.toString())}';
      final now = _clock();
      final last = _recent[sig];
      if (last != null && now.difference(last) < dedupeWindow) return;
      _recent[sig] = now;
      final event = buildEvent(error, stack, handled: handled, extra: extra);
      if (dir == null) {
        // Τα πρώτα κλάσματα του δευτερολέπτου, πριν έρθει ο φάκελος: στη μνήμη, ως 5.
        if (_early.length < 5) _early.add(event);
        return;
      }
      await _enqueue(event);
      await flush();
    } catch (_) {
      // Η αναφορά σφαλμάτων δεν πρέπει ποτέ να χαλάσει την εφαρμογή.
    }
  }

  Map<String, Object?> buildEvent(Object error, StackTrace? stack, {bool handled = true, Map<String, Object?> extra = const {}}) {
    final raw = stack?.toString() ?? '';
    final frames = parseDartStack(raw);
    final now = _clock();
    return {
      'event_id': _uuid(),
      'timestamp': now.toUtc().millisecondsSinceEpoch / 1000,
      'platform': 'dart',
      'level': 'error',
      'release': release,
      'environment': environment,
      'sdk': {'name': 'ygeia-forma.report', 'version': '1'},
      'tags': {'screen': screen, 'handled': '$handled', 'source': 'dart'},
      'contexts': _contexts(),
      'extra': {
        ...extra,
        // Αν δεν διαβάστηκε καμία γραμμή της στοίβας, κρατάμε την ωμή (κομμένη), για να μη χαθεί.
        if (frames.isEmpty && raw.isNotEmpty) 'stack': raw.length > 4000 ? raw.substring(0, 4000) : raw,
      },
      'exception': {
        'values': [
          {
            'type': error.runtimeType.toString(),
            'value': _message(error),
            if (frames.isNotEmpty) 'stacktrace': {'frames': frames},
            'mechanism': {'type': handled ? 'handled' : 'onerror', 'handled': handled},
          },
        ],
      },
    };
  }

  /// Μόνο η πρώτη γραμμή του μηνύματος και ως 300 χαρακτήρες: κάποια σφάλματα (π.χ. FormatException)
  /// κουβαλάνε κομμάτι από το κείμενο που διάβαζαν.
  /// Έλεγχος του fix-accuracy (N5), όπως στην Kotlin (E3-19): τα ArgumentError / RangeError γράφουν την τιμή που
  /// απορρίφθηκε («Invalid argument: 82.4»)· στέλνεται μόνο ο τύπος τους.
  static String _message(Object e) {
    final x = e is FlutterErrorDetails ? e.exception : e;
    if (x is ArgumentError) return '';
    final s = _firstLine(e is FlutterErrorDetails ? e.exceptionAsString() : e.toString());
    return s.length > 300 ? '${s.substring(0, 300)}…' : s;
  }

  static String _firstLine(String s) {
    final i = s.indexOf('\n');
    return (i < 0 ? s : s.substring(0, i)).trim();
  }

  static final _rng = Random();
  static String _uuid() => List.generate(32, (_) => _rng.nextInt(16).toRadixString(16)).join();

  Future<void> _enqueue(Map<String, Object?> event) async {
    final d = dir!;
    if (!await d.exists()) await d.create(recursive: true);
    final name = '${_clock().millisecondsSinceEpoch.toString().padLeft(14, '0')}_${event['event_id']}.json';
    await File('${d.path}/$name').writeAsString(jsonEncode(event), flush: true);
    // Όχι άπειρη ουρά: φεύγουν τα παλαιότερα.
    final files = await _queued();
    for (final f in files.take(max(0, files.length - maxQueue))) {
      await _delete(f);
    }
  }

  Future<List<File>> _queued() async {
    final d = dir;
    if (d == null || !await d.exists()) return const [];
    final files = <File>[];
    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.json')) files.add(e);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  static Future<void> _delete(File f) async {
    try {
      await f.delete();
    } catch (_) {}
  }

  /// Πόσα περιμένουν στην ουρά (για τους ελέγχους).
  Future<int> pending() async => (await _queued()).length;

  /// Σβήνει ό,τι περιμένει (και όσα έγραψε η πλευρά Android).
  Future<void> _clearQueue() async {
    _early.clear();
    for (final f in await _queued()) {
      await _delete(f);
    }
    // K8-R-10: και το αρχείο των τελευταίων σφαλμάτων (με κλειστές τις αναφορές δεν μένει αρχείο σφαλμάτων στο κινητό).
    await _deleteRecent();
  }

  /// Ο διακόπτης «Αναφορές σφαλμάτων». Κλείσιμο: σβήνονται αμέσως όσα περίμεναν. Η επιλογή γράφεται πρώτα, ώστε μια
  /// αποτυχία εγγραφής να μη δείχνει «κλειστό» ενώ μετά την επανεκκίνηση θα ήταν ανοιχτό. `false` αν δεν γράφτηκε.
  Future<bool> setEnabled(bool on) async {
    try {
      await persist?.call(on);
    } catch (_) {
      return false;
    }
    sending.value = on;
    if (!on) {
      try {
        await _clearQueue();
      } catch (_) {}
    }
    return true;
  }

  /// Στέλνει ό,τι περιμένει, με τη σειρά. Σταματά στο πρώτο σφάλμα δικτύου (θα ξαναδοκιμάσει αργότερα).
  /// Πάνω από [maxPerDay] αποστολές τη μέρα: τα υπόλοιπα πετιούνται (σημάδι βρόχου, όχι νέα πληροφορία).
  Future<void> flush() async {
    if (_busy) return;
    if (!enabled) {
      await _clearQueue();
      return;
    }
    _busy = true;
    try {
      final files = await _queued();
      if (files.isEmpty) return;
      final countFile = File('${dir!.path}/.count');
      final day = _clock().toIso8601String().substring(0, 10);
      var sent = 0;
      try {
        final j = jsonDecode(await countFile.readAsString()) as Map;
        if (j['day'] == day) sent = (j['n'] as num).toInt();
      } catch (_) {}
      final before = sent;
      for (final f in files) {
        // Ο διακόπτης έκλεισε στη μέση: τίποτα άλλο δεν φεύγει.
        if (!enabled) break;
        if (sent >= maxPerDay) {
          await _delete(f);
          continue;
        }
        Object? id;
        String text;
        try {
          text = await f.readAsString();
          id = (jsonDecode(text) as Map)['event_id'];
        } catch (_) {
          await _delete(f); // χαλασμένο αρχείο
          continue;
        }
        final body = '${jsonEncode({'event_id': id, 'sent_at': _clock().toUtc().toIso8601String()})}\n'
            '${jsonEncode({'type': 'event'})}\n$text';
        int status;
        try {
          status = await _post(body);
        } catch (_) {
          break; // χωρίς σύνδεση: μένει στην ουρά
        }
        if (status == 429 || status >= 500) break; // το Sentry λέει «αργότερα»
        // 2xx: στάλθηκε. 400/413: χαλασμένο γεγονός, δεν το ξαναστέλνουμε.
        if (status >= 200 && status < 300) sent++;
        await _delete(f);
      }
      if (sent != before) {
        try {
          await countFile.writeAsString(jsonEncode({'day': day, 'n': sent}));
        } catch (_) {}
      }
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  // ----- Οθόνη -----

  void setBase(String s) {
    if (s == base) return;
    base = s;
    _screenChanged();
  }

  void _push(String name) {
    _routes.add(name);
    _screenChanged();
  }

  void _pop(String name) {
    final i = _routes.lastIndexOf(name);
    if (i >= 0) _routes.removeAt(i);
    _screenChanged();
  }

  /// Η πλευρά Android κρατάει κι αυτή την οθόνη, για τα δικά της σφάλματα.
  void Function(String screen)? onScreen;
  void _screenChanged() {
    try {
      onScreen?.call(screen);
    } catch (_) {}
  }

  late final NavigatorObserver observer = _ScreenObserver(this);
}

class _ScreenObserver extends NavigatorObserver {
  _ScreenObserver(this.r);
  final ErrorReporter r;

  String? _name(Route<dynamic>? route) {
    if (route == null || route.isFirst) return null;
    return route.settings.name ?? (route is PopupRoute ? 'παράθυρο' : 'σελίδα');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final n = _name(route);
    if (n != null) r._push(n);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final n = _name(route);
    if (n != null) r._pop(n);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => didPop(route, previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) didPop(oldRoute, null);
    if (newRoute != null) didPush(newRoute, null);
  }
}

/// Γραμμές στοίβας της Dart: «#3  Foo.bar (package:ygeia_forma/x.dart:12:5)».
/// Το Sentry θέλει την παλαιότερη κλήση πρώτη, άρα αντίστροφα.
List<Map<String, Object?>> parseDartStack(String stack) {
  final re = RegExp(r'^#\d+\s+(.+?)\s+\((.+?)(?::(\d+))?(?::(\d+))?\)\s*$');
  final out = <Map<String, Object?>>[];
  for (final line in stack.split('\n')) {
    final m = re.firstMatch(line.trim());
    if (m == null) continue;
    final file = m.group(2)!;
    out.add({
      'function': m.group(1),
      'filename': file,
      'abs_path': file,
      if (m.group(3) != null) 'lineno': int.parse(m.group(3)!),
      if (m.group(4) != null) 'colno': int.parse(m.group(4)!),
      'in_app': file.startsWith('package:ygeia_forma/'),
    });
  }
  return out.reversed.toList();
}

// ---------------------------------------------------------------------------
// Σύνδεση με την εφαρμογή
// ---------------------------------------------------------------------------

/// Ο ένας αναφορέας της εφαρμογής.
final errors = ErrorReporter();

const _channel = MethodChannel('ygeia/errors');

class _Resume with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(errors.flush());
  }
}

/// Τα επιπλέον της αναφοράς για ένα σφάλμα της Flutter. Έλεγχος 3, E6: το «context» μπορεί να περιγράφει widget με
/// το κείμενό του (π.χ. «building Text("…")», με όνομα ή τιμή)· στέλνεται ΜΟΝΟ το είδος του, ποτέ η περιγραφή.
Map<String, Object?> flutterErrorExtra(FlutterErrorDetails details) => {
      if (details.library != null) 'library': details.library,
      if (details.context != null) 'context': details.context.runtimeType.toString(),
    };

/// Στήνεται στην αρχή της main(). Πιάνει σφάλματα της Flutter και ό,τι ξεφύγει (async).
/// Τα στοιχεία συσκευής και ο φάκελος έρχονται από την πλευρά Android χωρίς να καθυστερεί η πρώτη οθόνη.
void installErrorReporting() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (!kReleaseMode) previous?.call(details);
    if (details.silent) return;
    unawaited(errors.report(details.exception, details.stack, handled: false, extra: flutterErrorExtra(details)));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(errors.report(error, stack, handled: false));
    return true;
  };

  errors.onScreen = (s) => _channel.invokeMethod('screen', s).catchError((_) => null);
  errors.persist = (on) async {
    final ok = await _channel.invokeMethod<bool>('setEnabled', on);
    if (ok != true) throw StateError('setEnabled');
  };
  WidgetsBinding.instance.addObserver(_Resume());

  // Φάκελος και στοιχεία συσκευής αμέσως (μία γρήγορη κλήση, δεν καθυστερεί την πρώτη οθόνη)·
  // αποστολή ό,τι έμεινε από την προηγούμενη φορά (ή από κρασάρισμα Android) 5 δευτερόλεπτα μετά.
  unawaited(() async {
    try {
      final info = await _channel.invokeMapMethod<String, Object?>('info');
      if (info == null) return;
      await errors.configure(
        dir: Directory(info['dir'] as String),
        release: 'ygeia-forma@${info['version']}',
        device: {'model': '${info['model']}', 'android': '${info['android']}'},
        // Παλιότερη πλευρά Android χωρίς τον διακόπτη: ανοιχτός (όπως πριν).
        enabled: info['enabled'] != false,
      );
    } catch (_) {}
  }());
  Timer(const Duration(seconds: 5), () => unawaited(errors.flush()));
}
