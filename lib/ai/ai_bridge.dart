/// Η γέφυρα προς το AI (19/11): κινητό → Supabase Edge Function «ai-food» → Claude API.
///
/// - Το κλειδί του Claude API ΔΕΝ υπάρχει ποτέ στην εφαρμογή: είναι κρυφή ρύθμιση (secret) στο Supabase.
/// - Το repo είναι δημόσιο, άρα η διεύθυνση της γέφυρας δεν φτάνει: κάθε κλήση έχει το «κλειδί γέφυρας», 32 τυχαία bytes
///   που φτιάχνει το κινητό ([newBridgeToken]) και ο χρήστης βάζει στο Supabase (secret APP_TOKEN). Η function απορρίπτει
///   κάθε άλλη κλήση.
/// - Διεύθυνση και κλειδί κρυπτογραφημένα στο κινητό (Android Keystore, όπως τα tokens του Oura), εκτός αντιγράφων: σε
///   νέο κινητό η σύνδεση γίνεται ξανά.
/// - Στέλνεται μόνο ό,τι χρειάζεται το φαγητό (τρόφιμα, προτιμήσεις, κουζίνα). Κανένα δεδομένο υγείας και κανένα δεδομένο
///   του Oura· οι στόχοι μόνο σε στρογγυλά νούμερα θερμίδων ανά γεύμα (έλεγχος 19/11, X-3).
/// - Ελέγχος 19/11: η περιοχή της function κλειδώνει στη Φρανκφούρτη (`x-region`), καμία ανακατεύθυνση (το κλειδί δεν
///   φεύγει ποτέ αλλού), κάθε σφάλμα γίνεται ελληνικό μήνυμα ([aiErrorText]), και η «Ακύρωση» σταματά τις νέες κλήσεις
///   ([AiCancel]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../oura/oura_api.dart' show OuraVault, VaultUnavailable;

const aiVaultUrl = 'ai_url';
const aiVaultToken = 'ai_token';

/// Η μέρα της τελευταίας πετυχημένης «Δοκιμής σύνδεσης» (για τη σελίδα ρυθμίσεων).
const aiVaultOk = 'ai_ok';

/// Μοντέλα (η function δέχεται μόνο αυτά και ορίζει μόνη της πόσο «σκέφτονται»). Σχέδιο εβδομάδας: το πιο προσεκτικό·
/// συνταγές και αλλαγές: γρηγορότερο, ώστε κάθε κλήση να χωράει άνετα στα 150″ του Supabase.
const aiModelPlan = 'claude-opus-5-5';
const aiModelRecipe = 'claude-sonnet-5-5';

/// Όριο εξόδου (σκέψη + απάντηση μετρούν μαζί). Ίσο ή κάτω από το όριο της function.
const aiMaxTokensPlan = 12000;
const aiMaxTokensRecipe = 8000;

/// Ως τόσο περιμένουμε μία απάντηση. Το Supabase κόβει στα 150″, η function σταματά το Claude στα 125″.
const aiTimeout = Duration(seconds: 148);

/// Η περιοχή της function (ΕΕ, Φρανκφούρτη): αλλιώς τρέχει όπου είναι πιο κοντά ο χρήστης (π.χ. σε ταξίδι, ΗΠΑ).
const aiRegion = 'eu-central-1';

/// Μία ερώτηση: [system] (σταθερό κομμάτι, κρατιέται στην cache του API για λίγα λεπτά) και τα μηνύματα της συζήτησης
/// (εναλλάξ «user» / «assistant», πρώτο και τελευταίο «user», κανένα κενό).
class AiAsk {
  const AiAsk({required this.model, required this.system, required this.messages, this.maxTokens = aiMaxTokensRecipe});
  final String model;
  final String system;
  final List<(String role, String text)> messages;
  final int maxTokens;

  Map<String, Object> toJson() => {
        'model': model,
        'max_tokens': maxTokens,
        'system': system,
        'messages': [
          for (final (r, t) in messages) {'role': r, 'content': t},
        ],
      };
}

/// Τι πήγε στραβά, για ελληνικό μήνυμα ([aiErrorText]).
enum AiFail {
  notSetUp,
  vault,
  offline,
  noProject,
  timeout,
  token,
  jwt,
  notDeployed,
  setup,
  apiKey,
  paused,
  busy,
  credits,
  model,
  refused,
  server,
  bad,
  cancelled,
}

class AiReply {
  const AiReply.ok(String this.text)
      : fail = null,
        cut = false;
  const AiReply.cutOff(String this.text)
      : fail = null,
        cut = true;
  const AiReply.failed(AiFail this.fail)
      : text = null,
        cut = false;
  final String? text;
  final AiFail? fail;

  /// Η απάντηση κόπηκε στο όριο μεγέθους (μισό JSON).
  final bool cut;
  bool get ok => text != null && !cut;
}

typedef AiCall = Future<AiReply> Function(AiAsk ask);

/// «Ακύρωση» (έλεγχος 19/11, U-1/I-11): μετά από αυτήν καμία ΝΕΑ κλήση στο AI. Όσες είναι ήδη στον δρόμο τελειώνουν και
/// αγνοούνται (η function δεν μπορεί να σταματήσει το Claude στη μέση).
class AiCancel {
  bool _on = false;
  bool get cancelled => _on;
  void cancel() => _on = true;

  AiCall wrap(AiCall call) => (a) async {
        if (_on) return const AiReply.failed(AiFail.cancelled);
        final r = await call(a);
        return _on ? const AiReply.failed(AiFail.cancelled) : r;
      };
}

String aiErrorText(AiFail f) => switch (f) {
      AiFail.notSetUp => 'Το AI δεν έχει συνδεθεί ακόμα: Ρυθμίσεις › AI για το φαγητό.',
      AiFail.vault => 'Δεν διαβάστηκε το κλειδί από την ασφαλή αποθήκευση του κινητού. Δοκίμασε ξανά σε λίγο.',
      AiFail.offline => 'Χωρίς internet τώρα. Δοκίμασε όταν έχεις σύνδεση.',
      AiFail.noProject => 'Δεν βρέθηκε project με αυτό το Project ID. Έλεγξέ το στις Ρυθμίσεις › AI για το φαγητό.',
      AiFail.timeout => 'Το AI άργησε πολύ να απαντήσει (η κλήση μπορεί να χρεώθηκε). Δοκίμασε ξανά σε λίγο.',
      AiFail.token => 'Η γέφυρα δεν δέχτηκε το κλειδί της εφαρμογής. Έλεγξε ότι το secret «APP_TOKEN» στο Supabase είναι '
          'ίδιο με το κλειδί στις Ρυθμίσεις › AI για το φαγητό.',
      AiFail.jwt => 'Η function ζητά σύνδεση χρήστη (JWT). Στο Supabase › Edge Functions › ai-food › Details, κλείσε το '
          '«Verify JWT» και αποθήκευσε.',
      AiFail.notDeployed => 'Η function «ai-food» δεν βρέθηκε στο Supabase. Έλεγξε το Project ID και ότι η function '
          'λέγεται ακριβώς ai-food.',
      AiFail.setup => 'Στο Supabase λείπει το secret «ANTHROPIC_API_KEY». Βάλ’ το στο Edge Functions › Secrets.',
      AiFail.apiKey => 'Το Claude API δεν δέχτηκε το κλειδί API. Φτιάξε νέο στο Claude Console και βάλ’ το στο Supabase '
          '(secret «ANTHROPIC_API_KEY»).',
      AiFail.paused => 'Το Supabase έκανε παύση στο project (λίγη χρήση). Άνοιξε το project στο supabase.com και πάτα '
          '«Resume project». Τα δεδομένα δεν χάνονται.',
      AiFail.busy => 'Το AI είναι φορτωμένο αυτή τη στιγμή. Δοκίμασε ξανά σε ένα λεπτό.',
      AiFail.credits => 'Τελείωσε η πίστωση ή το όριο δαπάνης του Claude API (Claude Console › Billing / Limits). Δεν '
          'έγινε καμία επιπλέον χρέωση.',
      AiFail.model => 'Το μοντέλο του AI δεν υπάρχει πια. Χρειάζεται νέα έκδοση της εφαρμογής.',
      AiFail.refused => 'Το AI δεν απάντησε σε αυτό. Δοκίμασε ξανά.',
      AiFail.server => 'Η γέφυρα ή το AI έχει πρόβλημα τώρα. Δοκίμασε ξανά σε λίγο.',
      AiFail.bad => 'Η απάντηση του AI δεν διαβάστηκε. Δοκίμασε ξανά.',
      AiFail.cancelled => 'Ακυρώθηκε.',
    };

/// Νέο κλειδί γέφυρας: 32 τυχαία bytes (κρυπτογραφικά ασφαλή), σε base64url χωρίς «=» (43 χαρακτήρες).
String newBridgeToken([math.Random? rnd]) {
  final r = rnd ?? math.Random.secure();
  return base64Url.encode([for (var i = 0; i < 32; i++) r.nextInt(256)]).replaceAll('=', '');
}

/// Η διεύθυνση της γέφυρας: μόνο https, μόνο *.supabase.co, μόνο η function «ai-food». Δεκτά: το Project ID, το «Project
/// URL» του Supabase ή η διεύθυνση της function. Έτσι ένα λάθος επικόλλησης δεν στέλνει ποτέ το κλειδί κάπου αλλού.
Uri? bridgeUrl(String raw) {
  final s = raw.trim().toLowerCase();
  final m = RegExp(r'^https://([a-z0-9]{20})\.supabase\.co(/functions/v1/ai-food)?/?$').firstMatch(s);
  final id = m?.group(1) ?? RegExp(r'^[a-z0-9]{20}$').firstMatch(s)?.group(0);
  return id == null ? null : Uri.parse('https://$id.supabase.co/functions/v1/ai-food');
}

/// Η σύνδεση της εφαρμογής με τη γέφυρα (διεύθυνση + κλειδί), από το κρυπτογραφημένο αρχείο του κινητού.
class AiBridge {
  AiBridge(this.vault, {this.send = aiHttp});
  final OuraVault vault;
  final Future<(int, String)> Function(Uri url, String token, String body) send;

  static AiBridge? shared;

  Uri? _url;
  String? _token;
  String? _okDay;
  bool _loaded = false;

  bool get loaded => _loaded;
  bool get ready => _url != null && _token != null;
  Uri? get url => _url;
  String? get token => _token;

  /// Η μέρα (ΕΕΕΕ-ΜΜ-ΗΗ) της τελευταίας πετυχημένης δοκιμής με την τωρινή διεύθυνση και το τωρινό κλειδί, ή null.
  String? get okDay => _okDay;

  /// Διαβάζει από το κινητό. `false` αν η ασφαλής αποθήκευση δεν απάντησε (τότε δεν αλλάζει τίποτα).
  Future<bool> load() async {
    try {
      final u = await vault.load(aiVaultUrl);
      final t = await vault.load(aiVaultToken);
      final ok = await vault.load(aiVaultOk);
      _url = u == null ? null : bridgeUrl(u);
      _token = t != null && t.length >= 32 ? t : null;
      _okDay = ok;
    } on VaultUnavailable {
      return false;
    }
    _loaded = true;
    return true;
  }

  Future<void> _clearOk() async {
    _okDay = null;
    await vault.delete(aiVaultOk);
  }

  /// Αποθηκεύει τη διεύθυνση. `false` αν δεν είναι διεύθυνση γέφυρας ή δεν γράφτηκε.
  Future<bool> setUrl(String raw) async {
    final u = bridgeUrl(raw);
    if (u == null) return false;
    if (u == _url) return true;
    if (!await vault.save(aiVaultUrl, u.toString())) return false;
    _url = u;
    await _clearOk();
    return true;
  }

  /// Φτιάχνει (ή επιστρέφει το υπάρχον) κλειδί γέφυρας. null αν δεν διαβάστηκε ή δεν γράφτηκε. Ποτέ δεν γράφει νέο κλειδί
  /// πάνω σε ένα που απλώς δεν διαβάστηκε (έλεγχος 19/11, X-11).
  Future<String?> ensureToken() async {
    if (!_loaded && !await load()) return null;
    if (_token != null) return _token;
    final t = newBridgeToken();
    if (!await vault.save(aiVaultToken, t)) return null;
    _token = t;
    await _clearOk();
    return t;
  }

  /// Νέο κλειδί (π.χ. αν το παλιό το είδε κάποιος άλλος). Μετά πρέπει να μπει ξανά στο Supabase.
  Future<String?> resetToken() async {
    final t = newBridgeToken();
    if (!await vault.save(aiVaultToken, t)) return null;
    _token = t;
    await _clearOk();
    return t;
  }

  Future<void> disconnect() async {
    await vault.delete(aiVaultUrl);
    await vault.delete(aiVaultToken);
    await vault.delete(aiVaultOk);
    _url = null;
    _token = null;
    _okDay = null;
  }

  /// Σημειώνει ότι η «Δοκιμή σύνδεσης» πέτυχε σήμερα.
  Future<void> markOk(String day) async {
    if (await vault.save(aiVaultOk, day)) _okDay = day;
  }

  Future<AiReply> call(AiAsk ask) async {
    if (!_loaded && !await load()) return const AiReply.failed(AiFail.vault);
    final u = _url, t = _token;
    if (u == null || t == null) return const AiReply.failed(AiFail.notSetUp);
    try {
      final r = await send(u, t, jsonEncode(ask.toJson())).timeout(aiTimeout);
      return parseBridgeReply(r.$1, r.$2);
    } on TimeoutException {
      return const AiReply.failed(AiFail.timeout);
    } on SocketException catch (e) {
      // Λάθος Project ID (σωστή μορφή, δεν υπάρχει): το όνομα δεν βρίσκεται στο DNS.
      final m = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
      return AiReply.failed(m.contains('host lookup') || m.contains('no address') ? AiFail.noProject : AiFail.offline);
    } on HandshakeException {
      return const AiReply.failed(AiFail.offline);
    } on TlsException {
      return const AiReply.failed(AiFail.offline);
    } on HttpException {
      return const AiReply.failed(AiFail.offline);
    } on FormatException {
      return const AiReply.failed(AiFail.bad);
    } catch (_) {
      // Ποτέ το μήνυμα του σφάλματος στην αναφορά (μπορεί να έχει τη διεύθυνση).
      return const AiReply.failed(AiFail.server);
    }
  }
}

/// Η απάντηση της function: {"ok": true, "text": "…", "stop": "end_turn"} ή {"ok": false, "kind": "…"}. Χωρίς «kind»
/// απαντά η πύλη του Supabase (π.χ. 401 όταν η function ζητά JWT, 404 όταν δεν υπάρχει).
AiReply parseBridgeReply(int status, String body) {
  if (status == 540) return const AiReply.failed(AiFail.paused);
  Object? j;
  try {
    j = jsonDecode(body);
  } catch (_) {
    j = null;
  }
  if (j is Map && j['ok'] == true && j['text'] is String) {
    final text = j['text'] as String;
    if (j['stop'] == 'refusal') return const AiReply.failed(AiFail.refused);
    return j['stop'] == 'max_tokens' ? AiReply.cutOff(text) : AiReply.ok(text);
  }
  final kind = j is Map && j['ok'] == false ? j['kind'] : null;
  return AiReply.failed(switch (kind) {
    'token' => AiFail.token,
    'setup' => AiFail.setup,
    'apikey' => AiFail.apiKey,
    'credits' => AiFail.credits,
    'busy' => AiFail.busy,
    'timeout' => AiFail.timeout,
    'paused' => AiFail.paused,
    'model' => AiFail.model,
    'bad' || 'size' || 'method' => AiFail.bad,
    _ => status == 401 || status == 403
        ? AiFail.jwt
        : status == 404
            ? AiFail.notDeployed
            : status == 429
                ? AiFail.busy
                : status == 504 || status == 546
                    ? AiFail.timeout
                    : status >= 500 || (status >= 300 && status < 400)
                        ? AiFail.server
                        : AiFail.bad,
  });
}

/// Αποστολή με το HttpClient της Dart. Χωρίς ανακατευθύνσεις (το κλειδί δεν φεύγει ποτέ σε άλλη διεύθυνση), με όριο
/// χρόνου που κλείνει και τη σύνδεση. Ποτέ δεν γράφεται το κλειδί σε μήνυμα σφάλματος.
Future<(int, String)> aiHttp(Uri url, String token, String body) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 5);
  final deadline = Timer(aiTimeout + const Duration(seconds: 5), () => client.close(force: true));
  try {
    final req = await client.postUrl(url).timeout(const Duration(seconds: 20));
    req.followRedirects = false;
    req.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    req.headers.set('x-app-token', token);
    req.headers.set('x-region', aiRegion);
    req.add(utf8.encode(body));
    final res = await req.close().timeout(aiTimeout);
    final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(const Duration(seconds: 30));
    return (res.statusCode, utf8.decode(bytes, allowMalformed: true));
  } finally {
    deadline.cancel();
    client.close(force: true);
  }
}
