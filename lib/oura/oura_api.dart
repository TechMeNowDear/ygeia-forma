/// Σύνδεση με το Oura (OAuth2 με PKCE) και ανάγνωση δεδομένων (API v2), χωρίς βιβλιοθήκες.
///
/// - Σύνδεση μία φορά: «authorization code» με PKCE (S256) και «state». Χωρίς Client Secret στην εφαρμογή.
/// - Μετά, μόνη της: το refresh token ανανεώνει την πρόσβαση χωρίς τον χρήστη. Είναι μιας χρήσης, άρα
///   το νέο αποθηκεύεται ΠΡΙΝ χρησιμοποιηθεί η νέα πρόσβαση, και οι ανανεώσεις γίνονται μία-μία.
/// - 401: μία ανανέωση και ξανά· αν ξαναγίνει, «Χρειάζεται νέα σύνδεση». 403: συνδρομή/άδεια. 429: αργότερα.
/// - Ποτέ δεν γράφονται tokens, κωδικοί ή τιμές υγείας σε σφάλματα ή στο Sentry.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'config.dart';
import 'oura_model.dart';
import 'sha256.dart';

// ---------------------------------------------------------------------------
// HTTP (αντικαθίσταται στους ελέγχους)
// ---------------------------------------------------------------------------

class OuraResponse {
  const OuraResponse(this.status, this.body, {this.retryAfter});
  final int status;
  final String body;

  /// Από την κεφαλίδα Retry-After (δευτερόλεπτα), στο 429.
  final Duration? retryAfter;
}

typedef OuraSend = Future<OuraResponse> Function(String method, Uri url, {Map<String, String> headers, String? form});

/// Αποστολή με το HttpClient της Dart (όπως η αναφορά σφαλμάτων). Σφάλμα δικτύου = εξαίρεση.
Future<OuraResponse> ouraHttp(String method, Uri url, {Map<String, String> headers = const {}, String? form}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = ouraUserAgent;
  try {
    final req = await client.openUrl(method, url).timeout(const Duration(seconds: 20));
    req.headers.set(HttpHeaders.userAgentHeader, ouraUserAgent);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    headers.forEach(req.headers.set);
    if (form != null) {
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.add(utf8.encode(form));
    }
    final res = await req.close().timeout(const Duration(seconds: 30));
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 30));
    final ra = int.tryParse(res.headers.value('retry-after') ?? '');
    return OuraResponse(res.statusCode, body, retryAfter: ra == null ? null : Duration(seconds: ra));
  } finally {
    client.close(force: true);
  }
}

// ---------------------------------------------------------------------------
// Αποθήκευση (κρυπτογραφημένη στο Android Keystore, δες OuraBridge.kt)
// ---------------------------------------------------------------------------

/// Η αποθήκευση δεν απάντησε τώρα (π.χ. προσωρινό σφάλμα του Keystore): τα αρχεία μένουν, ξανά αργότερα.
class VaultUnavailable implements Exception {
  const VaultUnavailable();
  @override
  String toString() => 'VaultUnavailable';
}

abstract class OuraVault {
  /// null = δεν υπάρχει (ή δεν αποκρυπτογραφείται πια, π.χ. μετά από επαναφορά σε άλλο κινητό).
  /// Πετάει [VaultUnavailable] σε προσωρινό σφάλμα.
  Future<String?> load(String name);

  /// `true` αν γράφτηκε.
  Future<bool> save(String name, String value);
  Future<void> delete(String name);
}

class MemoryVault implements OuraVault {
  final Map<String, String> data = {};
  bool failSaves = false;
  bool failLoads = false;

  @override
  Future<String?> load(String name) async {
    if (failLoads) throw const VaultUnavailable();
    return data[name];
  }

  @override
  Future<bool> save(String name, String value) async {
    if (failSaves) return false;
    data[name] = value;
    return true;
  }

  @override
  Future<void> delete(String name) async => data.remove(name);
}

const vaultTokens = 'oura_tokens';
const vaultPending = 'oura_pending';

/// Σημάδι «συνδέεται» (κρυπτογραφημένο, ατομικό): γράφεται ΠΡΙΝ από το σχέδιο πηγών και σβήνεται όταν κρατηθούν τα
/// tokens. Αν βρεθεί στην εκκίνηση χωρίς tokens, η σύνδεση έμεινε μισή.
const vaultConnecting = 'oura_connecting';

// ---------------------------------------------------------------------------
// Tokens και σφάλματα
// ---------------------------------------------------------------------------

class OuraTokens {
  const OuraTokens({required this.access, required this.refresh, required this.expiresAt});
  final String access;
  final String refresh;

  /// Πότε λήγει η πρόσβαση (ms από την εποχή Unix).
  final int expiresAt;

  bool expiringSoon(DateTime now) => now.millisecondsSinceEpoch > expiresAt - const Duration(minutes: 10).inMilliseconds;

  String toJson() => jsonEncode({'a': access, 'r': refresh, 'e': expiresAt});

  static OuraTokens? fromJson(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map || j['a'] is! String || j['r'] is! String || j['e'] is! num) return null;
      return OuraTokens(access: j['a'] as String, refresh: j['r'] as String, expiresAt: (j['e'] as num).toInt());
    } catch (_) {
      return null;
    }
  }

  /// Από την απάντηση του /oauth/token. Χωρίς refresh_token δεν μπορεί να ανανεώνεται μόνη της: σφάλμα.
  static OuraTokens parseResponse(String body, DateTime now) {
    final j = jsonDecode(body);
    if (j is! Map) throw const FormatException('token: όχι αντικείμενο');
    final a = j['access_token'];
    final r = j['refresh_token'];
    final e = j['expires_in'];
    if (a is! String || a.isEmpty) throw const FormatException('token: λείπει access_token');
    if (r is! String || r.isEmpty) throw const OuraError(OuraErrorKind.noRefresh);
    final secs = e is num ? e.toInt() : 86400;
    return OuraTokens(access: a, refresh: r, expiresAt: now.add(Duration(seconds: secs)).millisecondsSinceEpoch);
  }
}

enum OuraErrorKind {
  /// Χρειάζεται νέα σύνδεση (το refresh token δεν ισχύει πια, ή 401 και μετά την ανανέωση).
  reconnect,

  /// 403: η συνδρομή δεν είναι ενεργή ή δεν δόθηκε άδεια.
  subscription,

  /// 429: πολλά αιτήματα· ξανά μετά από λίγο.
  rateLimited,

  /// Δίκτυο ή διακομιστής (5xx): ξανά αργότερα.
  network,

  /// Η απάντηση δεν είχε τη μορφή που περιμέναμε.
  format,

  /// Η Oura δεν έδωσε refresh token (θα χρειαζόταν σύνδεση κάθε 30 μέρες).
  noRefresh,

  /// Η Oura απέρριψε την ανταλλαγή του κωδικού (π.χ. θέλει Client Secret).
  tokenRejected,

  /// Δεν δόθηκε άδεια στη σελίδα της Oura.
  denied,

  /// Η σύνδεση ακυρώθηκε (αποσύνδεση στο μεταξύ) ή οι πηγές δεν μπορούν να αλλάξουν τώρα.
  cancelled,

  /// Το νήμα ανάγνωσης δεν ξεκίνησε (έγινε στο κύριο νήμα· μόνο για αναφορά).
  isolate,

  /// Η σύνδεση άργησε ή δεν ταιριάζει (state).
  stale,

  /// Μια σύνδεση έμεινε μισή (έκλεισε η εφαρμογή στη μέση) και καθαρίστηκε στην εκκίνηση.
  incomplete,

  /// Δεν έχει μπει Client ID.
  notConfigured,

  /// Δεν άνοιξε ο browser.
  noBrowser,
}

class OuraError implements Exception {
  const OuraError(this.kind, {this.retryAfter, this.status});
  final OuraErrorKind kind;
  final Duration? retryAfter;
  final int? status;

  /// Χωρίς καμία προσωπική πληροφορία: μόνο το είδος και ο κωδικός HTTP.
  @override
  String toString() => 'OuraError(${kind.name}${status == null ? '' : ', HTTP $status'})';
}

/// Ελληνικό κείμενο για τον χρήστη.
String ouraErrorText(OuraErrorKind k) => switch (k) {
      OuraErrorKind.reconnect => 'Χρειάζεται νέα σύνδεση με το Oura.',
      OuraErrorKind.subscription =>
        'Η Oura δεν δίνει δεδομένα: η συνδρομή Oura δεν είναι ενεργή ή δεν δόθηκε άδεια για τον ύπνο.',
      OuraErrorKind.rateLimited => 'Η Oura ζήτησε να περιμένουμε λίγο. Θα ξαναδοκιμάσει μόνη της.',
      OuraErrorKind.network => 'Δεν υπάρχει σύνδεση με την Oura αυτή τη στιγμή. Θα ξαναδοκιμάσει μόνη της.',
      OuraErrorKind.format => 'Η Oura έστειλε κάτι που δεν διαβάστηκε. Το είδαμε και θα το διορθώσουμε.',
      OuraErrorKind.noRefresh => 'Η Oura δεν έδωσε μόνιμη σύνδεση. Δεν συνδέθηκε, για να μη χρειάζεται νέα σύνδεση κάθε μήνα.',
      OuraErrorKind.tokenRejected => 'Η Oura δεν δέχτηκε τη σύνδεση. Δεν άλλαξε τίποτα· ο ύπνος μένει από το ρολόι.',
      OuraErrorKind.denied => 'Δεν δόθηκε άδεια στη σελίδα της Oura. Δεν άλλαξε τίποτα.',
      OuraErrorKind.cancelled => 'Η σύνδεση δεν ολοκληρώθηκε. Δεν άλλαξε τίποτα· δοκίμασε ξανά σε λίγο.',
      OuraErrorKind.isolate => 'Η ανάγνωση έγινε πιο αργά από το συνηθισμένο.',
      OuraErrorKind.stale => 'Η σύνδεση άργησε. Πάτα ξανά «Σύνδεση με Oura».',
      OuraErrorKind.incomplete => 'Η σύνδεση δεν ολοκληρώθηκε· δοκίμασε ξανά.',
      OuraErrorKind.notConfigured => 'Η εγγραφή στην Oura γίνεται τη μέρα που θα έρθει το δαχτυλίδι.',
      OuraErrorKind.noBrowser => 'Δεν άνοιξε ο browser του κινητού.',
    };

/// Το είδος σφάλματος από έναν κωδικό HTTP (εκτός 2xx).
OuraErrorKind kindForStatus(int status) => switch (status) {
      401 => OuraErrorKind.reconnect,
      403 => OuraErrorKind.subscription,
      429 => OuraErrorKind.rateLimited,
      _ when status >= 500 => OuraErrorKind.network,
      _ => OuraErrorKind.format,
    };

// ---------------------------------------------------------------------------
// PKCE και σελίδα σύνδεσης
// ---------------------------------------------------------------------------

const _unreserved = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// Τυχαίο κείμενο από τους χαρακτήρες που επιτρέπει το RFC 7636 (43–128).
String randomVerifier([int length = 64, Random? rng]) {
  final r = rng ?? Random.secure();
  return List.generate(length, (_) => _unreserved[r.nextInt(_unreserved.length)]).join();
}

class OuraPending {
  const OuraPending({required this.state, required this.verifier, required this.created, this.from});
  final String state;
  final String verifier;
  final DateTime created;

  /// Η πρώτη νύχτα του Oura, όπως αποφασίστηκε πριν ανοίξει ο browser (κρυπτογραφημένα μαζί με το state).
  final DateTime? from;

  /// Πόση ώρα δίνεται για να ολοκληρωθεί η σύνδεση στη σελίδα της Oura.
  static const lifetime = Duration(minutes: 20);
  bool expired(DateTime now) => now.difference(created) > lifetime || now.isBefore(created.subtract(const Duration(minutes: 1)));

  String toJson() => jsonEncode({
        's': state,
        'v': verifier,
        'c': created.millisecondsSinceEpoch,
        if (from != null) 'f': '${from!.year}-${from!.month.toString().padLeft(2, '0')}-${from!.day.toString().padLeft(2, '0')}',
      });

  static OuraPending? fromJson(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map || j['s'] is! String || j['v'] is! String || j['c'] is! num) return null;
      final f = j['f'] is String ? DateTime.tryParse(j['f'] as String) : null;
      return OuraPending(
        state: j['s'] as String,
        verifier: j['v'] as String,
        created: DateTime.fromMillisecondsSinceEpoch((j['c'] as num).toInt()),
        from: f == null ? null : DateTime(f.year, f.month, f.day),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Η διεύθυνση της σελίδας σύνδεσης της Oura.
Uri ouraAuthorizeUrl({required String clientId, required OuraPending p, OuraOAuthEndpoints endpoints = ouraOAuth}) =>
    Uri.parse(endpoints.authorize).replace(queryParameters: {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': ouraRedirectUri,
      'scope': endpoints.scopes,
      'state': p.state,
      'code_challenge': pkceChallenge(p.verifier),
      'code_challenge_method': 'S256',
    });

/// Μόνο οι δύο ακριβείς μορφές: https://ygeia-forma.netlify.app/oura/callback ή ygeiaforma://oura-callback.
/// Καμία άλλη διεύθυνση, θύρα, χρήστης ή διαδρομή.
bool isOuraRedirect(Uri u) {
  if (u.userInfo.isNotEmpty) return false;
  if (u.scheme == 'https') {
    return u.host == ouraRedirectHttpsHost && !u.hasPort && u.path == ouraRedirectHttpsPath;
  }
  if (u.scheme == ouraRedirectScheme) {
    return u.host == ouraRedirectHost && !u.hasPort && (u.path.isEmpty || u.path == '/');
  }
  return false;
}

/// Η επιστροφή από την Oura: κωδικός ή σφάλμα, και το state.
({String? code, String? error, String? state})? parseCallback(String uri) {
  final u = Uri.tryParse(uri);
  if (u == null || !isOuraRedirect(u)) return null;
  // Οι παράμετροι έρχονται στο query· για σιγουριά διαβάζουμε και το fragment.
  final q = {...Uri.splitQueryString(u.fragment), ...u.queryParameters};
  return (code: q['code'], error: q['error'], state: q['state']);
}

String _form(Map<String, String> m) =>
    m.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');

// ---------------------------------------------------------------------------
// Η σύνδεση: tokens, ανανέωση, ανάγνωση
// ---------------------------------------------------------------------------

class OuraLink {
  OuraLink({
    required this.vault,
    OuraSend? send,
    DateTime Function()? clock,
    this.clientId = ouraClientId,
    this.endpoints = ouraOAuth,
    String? tokenEndpoint,
    this.apiBase = ouraApiBase,
  })  : _send = send ?? ouraHttp,
        _clock = clock ?? DateTime.now,
        tokenEndpoint = tokenEndpoint ?? ouraTokenEndpoint;

  final OuraVault vault;
  final OuraSend _send;
  final DateTime Function() _clock;
  final String clientId;
  final OuraOAuthEndpoints endpoints;
  final String tokenEndpoint;
  final String apiBase;

  OuraTokens? _tokens;
  bool _loaded = false;

  /// «Γενιά» της σύνδεσης: αυξάνει σε κάθε αποσύνδεση. Ό,τι ξεκίνησε σε παλιότερη γενιά (ανανέωση, σύνδεση,
  /// ανάγνωση) πετά το αποτέλεσμά του και δεν αποθηκεύει ποτέ tokens. Η αποσύνδεση κερδίζει πάντα.
  int _gen = 0;
  int get generation => _gen;

  /// Νέα tokens που δεν γράφτηκαν ακόμα (απέτυχε η αποθήκευση): ξαναδοκιμάζεται σε κάθε επόμενη χρήση.
  bool _unsaved = false;

  Future<OuraTokens?>? _refreshing;

  bool get configured => clientId.isNotEmpty;

  /// Πετάει [OuraError] (network) αν η αποθήκευση δεν απαντά τώρα: τα tokens δεν θεωρούνται χαμένα.
  Future<OuraTokens?> tokens() async {
    if (!_loaded) {
      final gen = _gen;
      final String? raw;
      try {
        raw = await vault.load(vaultTokens);
      } on VaultUnavailable {
        throw const OuraError(OuraErrorKind.network);
      }
      if (gen != _gen) return null; // αποσυνδέθηκε στο μεταξύ
      _tokens = OuraTokens.fromJson(raw);
      _loaded = true;
    }
    if (_unsaved && _tokens != null) {
      if (await vault.save(vaultTokens, _tokens!.toJson())) _unsaved = false;
    }
    return _tokens;
  }

  Future<bool> get hasTokens async => (await tokens()) != null;

  /// Ξεκινά τη σύνδεση: φτιάχνει και κρατά (κρυπτογραφημένα) state και verifier, και δίνει τη διεύθυνση.
  /// [from]: η πρώτη νύχτα του Oura, κρατιέται με το state ως την επιστροφή.
  Future<Uri> begin({DateTime? from}) async {
    if (!configured) throw const OuraError(OuraErrorKind.notConfigured);
    final p = OuraPending(state: randomVerifier(32), verifier: randomVerifier(64), created: _clock(), from: from);
    if (!await vault.save(vaultPending, p.toJson())) throw const OuraError(OuraErrorKind.stale);
    return ouraAuthorizeUrl(clientId: clientId, p: p, endpoints: endpoints);
  }

  /// Η επιστροφή από την Oura, μαζί: ανταλλαγή και αποθήκευση. Επιστρέφει true αν συνδέθηκε. Ό,τι δεν ταιριάζει
  /// αγνοείται (false). Η εφαρμογή χρησιμοποιεί [exchange] και [adopt] χωριστά (πρώτα το σχέδιο πηγών).
  Future<bool> complete(String uri) async {
    final ex = await exchange(uri);
    if (ex == null) return false;
    if (!await adopt(ex.tokens, ex.gen)) throw const OuraError(OuraErrorKind.cancelled);
    return true;
  }

  /// Η επιστροφή από την Oura: έλεγχος state και ανταλλαγή του κωδικού. Τα tokens ΔΕΝ αποθηκεύονται εδώ
  /// ([adopt]). null = δεν είναι δική μας επιστροφή (αγνοείται).
  Future<({OuraTokens tokens, DateTime? from, int gen})?> exchange(String uri) async {
    final cb = parseCallback(uri);
    if (cb == null) return null;
    final gen = _gen;
    final OuraPending? pending;
    try {
      pending = OuraPending.fromJson(await vault.load(vaultPending));
    } on VaultUnavailable {
      throw const OuraError(OuraErrorKind.cancelled);
    }
    // Επιστροφή χωρίς δική μας εκκρεμή σύνδεση, ή με άλλο state: δεν είναι δική μας (CSRF) — αγνοείται.
    if (pending == null || cb.state == null || cb.state != pending.state) return null;
    await vault.delete(vaultPending); // ο κωδικός και το state είναι μιας χρήσης
    if (pending.expired(_clock())) throw const OuraError(OuraErrorKind.stale);
    if (cb.error != null) throw const OuraError(OuraErrorKind.denied);
    final code = cb.code;
    if (code == null || code.isEmpty) throw const OuraError(OuraErrorKind.format);
    final res = await _post(tokenEndpoint, {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': ouraRedirectUri,
      'client_id': clientId,
      'code_verifier': pending.verifier,
    });
    if (res.status == 400 || res.status == 401) throw OuraError(OuraErrorKind.tokenRejected, status: res.status);
    if (res.status != 200) throw OuraError(kindForStatus(res.status), status: res.status, retryAfter: res.retryAfter);
    final t = OuraTokens.parseResponse(res.body, _clock());
    return (tokens: t, from: pending.from, gen: gen);
  }

  /// Κρατά τα tokens μιας νέας σύνδεσης: μόνο αν γράφτηκαν στην αποθήκευση και δεν έγινε αποσύνδεση στο μεταξύ.
  Future<bool> adopt(OuraTokens t, int gen) async {
    if (gen != _gen) return false;
    if (!await vault.save(vaultTokens, t.toJson()) || gen != _gen) {
      await vault.delete(vaultTokens);
      // Ούτε στη μνήμη μένουν παλιά tokens (π.χ. νέα σύνδεση μετά από παλιότερη).
      _tokens = null;
      _loaded = true;
      _unsaved = false;
      return false;
    }
    _tokens = t;
    _loaded = true;
    _unsaved = false;
    return true;
  }

  /// Το σημάδι «συνδέεται» ([vaultConnecting]). `false` αν δεν γράφτηκε.
  Future<bool> markConnecting(String json) => vault.save(vaultConnecting, json);

  /// Πετάει [VaultUnavailable] αν η αποθήκευση δεν απαντά.
  Future<String?> connectingMarker() => vault.load(vaultConnecting);
  Future<void> clearConnecting() => vault.delete(vaultConnecting);

  /// Tokens που δεν κρατήθηκαν (π.χ. δεν γράφτηκε το σχέδιο πηγών): ανάκληση στην Oura, τίποτα στο κινητό.
  Future<void> discard(OuraTokens t) => _revoke(t);

  Future<void> _revoke(OuraTokens t) async {
    try {
      final u = Uri.parse(endpoints.revoke);
      if (endpoints.revokeParam == 'access_token') {
        // Όπως στην τεκμηρίωση της Oura: POST /oauth/revoke?access_token=…
        await _send('POST', u.replace(queryParameters: {'access_token': t.access})).timeout(const Duration(seconds: 15));
      } else {
        await _send('POST', u, form: _form({'token': t.refresh, 'client_id': clientId})).timeout(const Duration(seconds: 15));
      }
    } catch (_) {
      // Χωρίς ίντερνετ: τα tokens σβήνονται έτσι κι αλλιώς από το κινητό.
    }
  }

  /// Αποθηκεύει τα νέα tokens μόνο αν δεν έγινε αποσύνδεση από τότε που ξεκίνησε το αίτημα ([gen]).
  Future<bool> _store(OuraTokens t, int gen) async {
    if (gen != _gen) return false;
    final ok = await vault.save(vaultTokens, t.toJson());
    // Αποσύνδεση όσο γραφόταν: σβήνουμε ό,τι γράφτηκε.
    if (gen != _gen) {
      await vault.delete(vaultTokens);
      return false;
    }
    _tokens = t;
    _loaded = true;
    _unsaved = !ok;
    return true;
  }

  Future<OuraResponse> _post(String url, Map<String, String> form) async {
    try {
      return await _send('POST', Uri.parse(url), form: _form(form));
    } on OuraError {
      rethrow;
    } catch (_) {
      throw const OuraError(OuraErrorKind.network);
    }
  }

  /// Ανανέωση: μία κάθε φορά (όποιος ζητήσει ενώ τρέχει, περιμένει την ίδια).
  Future<OuraTokens?> refresh() => _refreshing ??= _refreshOnce().whenComplete(() => _refreshing = null);

  Future<OuraTokens?> _refreshOnce() async {
    final gen = _gen;
    final old = await tokens();
    if (old == null) throw const OuraError(OuraErrorKind.reconnect);
    final res = await _post(tokenEndpoint, {
      'grant_type': 'refresh_token',
      'refresh_token': old.refresh,
      'client_id': clientId,
    });
    if (res.status == 400 || res.status == 401) {
      // Το refresh token δεν ισχύει πια (μιας χρήσης, ή ανακλήθηκε στην Oura).
      throw OuraError(OuraErrorKind.reconnect, status: res.status);
    }
    if (res.status != 200) throw OuraError(kindForStatus(res.status), status: res.status, retryAfter: res.retryAfter);
    final t = OuraTokens.parseResponse(res.body, _clock());
    // ΠΡΩΤΑ αποθήκευση του νέου refresh token, ΜΕΤΑ χρήση της νέας πρόσβασης. Μετά από αποσύνδεση δεν
    // αποθηκεύεται τίποτα (τα tokens επιστρέφονται μόνο για να ανακληθούν).
    await _store(t, gen);
    return t;
  }

  /// GET στο API με ανανέωση όταν χρειάζεται. 401 → μία ανανέωση και ξανά.
  Future<String> _get(Uri url) async {
    final gen = _gen;
    var t = await tokens();
    if (t == null) throw const OuraError(OuraErrorKind.reconnect);
    if (t.expiringSoon(_clock())) {
      try {
        t = await refresh() ?? t;
      } on OuraError catch (e) {
        // Χωρίς δίκτυο για την πρόωρη ανανέωση: η τωρινή πρόσβαση ισχύει ακόμα (λήγει σε λίγα λεπτά).
        final stillValid = _clock().millisecondsSinceEpoch < t!.expiresAt;
        if (e.kind != OuraErrorKind.network || !stillValid) rethrow;
      }
    }
    if (gen != _gen) throw const OuraError(OuraErrorKind.reconnect);
    var res = await _getWith(url, t!.access);
    if (res.status == 401) {
      t = await refresh();
      if (t == null || gen != _gen) throw const OuraError(OuraErrorKind.reconnect);
      res = await _getWith(url, t.access);
      if (res.status == 401) throw const OuraError(OuraErrorKind.reconnect, status: 401);
    }
    if (gen != _gen) throw const OuraError(OuraErrorKind.reconnect);
    if (res.status != 200) throw OuraError(kindForStatus(res.status), status: res.status, retryAfter: res.retryAfter);
    return res.body;
  }

  Future<OuraResponse> _getWith(Uri url, String access) async {
    try {
      return await _send('GET', url, headers: {'Authorization': 'Bearer $access'});
    } catch (_) {
      throw const OuraError(OuraErrorKind.network);
    }
  }

  /// Όλες οι σελίδες ενός endpoint για τις μέρες [from, to] (με τις άκρες).
  Future<List<Map<String, dynamic>>> fetchAll(String endpoint, DateTime from, DateTime to, {int maxPages = 40}) async {
    String d(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    // Το end_date της Oura δεν περιλαμβάνει τη μέρα του (έλεγχος στο sandbox, 2/11): ζητάμε ως την επόμενη
    // και κρατάμε μόνο τις μέρες που θέλουμε.
    final params = {'start_date': d(from), 'end_date': d(DateTime(to.year, to.month, to.day + 1))};
    final out = <Map<String, dynamic>>[];
    String? next;
    final seen = <String>{};
    for (var page = 0; page < maxPages; page++) {
      final url = Uri.parse('$apiBase$endpoint').replace(queryParameters: {...params, if (next != null) 'next_token': next});
      final body = await _get(url);
      final Object? j;
      try {
        j = jsonDecode(body);
      } catch (_) {
        throw const OuraError(OuraErrorKind.format);
      }
      final ({List<Map<String, dynamic>> data, String? next}) p;
      try {
        p = parseOuraPage(j);
      } on FormatException {
        throw const OuraError(OuraErrorKind.format);
      }
      out.addAll(p.data);
      next = p.next;
      if (next == null) return out;
      // Ίδιο next_token δύο φορές: η Oura δεν προχωρά — σταματάμε αντί για ατελείωτο βρόχο.
      if (!seen.add(next)) throw const OuraError(OuraErrorKind.format);
    }
    throw const OuraError(OuraErrorKind.format);
  }

  /// Ύπνος, βαθμολογίες ύπνου και ετοιμότητα για τις μέρες [from, to], διαβασμένα.
  Future<OuraBatch> fetchNights(DateTime from, DateTime to) async {
    final sleep = await fetchAll('sleep', from, to);
    final dailySleep = await fetchAll('daily_sleep', from, to);
    final readiness = await fetchAll('daily_readiness', from, to);
    final b = parseOura(sleep: sleep, dailySleep: dailySleep, readiness: readiness);
    final a = DateTime(from.year, from.month, from.day);
    final z = DateTime(to.year, to.month, to.day);
    return OuraBatch([for (final n in b.nights) if (!n.day.isBefore(a) && !n.day.isAfter(z)) n], skipped: b.skipped);
  }

  /// Αποσύνδεση: ανάκληση στην Oura (αν γίνεται) και σβήσιμο των tokens από το κινητό. Δεν πετάει ποτέ.
  /// Κερδίζει κάθε αίτημα που τρέχει: νέα γενιά αμέσως, και ό,τι ανανέωση έτρεχε δεν αποθηκεύεται.
  Future<void> disconnect() async {
    // ΠΡΩΤΑ το σημάδι «συνδέεται»: ένα σημάδι που θα έμενε χωρίς tokens θα αναιρούσε στην εκκίνηση μια σύνδεση που
    // είχε χρησιμοποιηθεί.
    await vault.delete(vaultConnecting);
    OuraTokens? t;
    try {
      t = _loaded ? _tokens : OuraTokens.fromJson(await vault.load(vaultTokens));
    } catch (_) {}
    final running = _refreshing;
    _gen++;
    _tokens = null;
    _loaded = true;
    _unsaved = false;
    if (running != null) {
      try {
        // Η ανανέωση που έτρεχε: δεν αποθηκεύει (άλλη γενιά)· αν πέτυχε, ανακαλούμε τα νέα tokens.
        t = await running.timeout(const Duration(seconds: 30)) ?? t;
      } catch (_) {}
    }
    if (t != null) await _revoke(t);
    _tokens = null;
    _loaded = true;
    _unsaved = false;
    await vault.delete(vaultTokens);
    await vault.delete(vaultPending);
  }
}
