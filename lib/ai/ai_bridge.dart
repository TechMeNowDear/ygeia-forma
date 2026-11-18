/// Η γέφυρα προς το AI (19/11): κινητό → Supabase Edge Function «ai-food» → Claude API.
///
/// - Το κλειδί του Claude API ΔΕΝ υπάρχει ποτέ στην εφαρμογή: είναι κρυφή ρύθμιση (secret) στο Supabase.
/// - Το repo είναι δημόσιο, άρα η διεύθυνση της γέφυρας δεν φτάνει: κάθε κλήση έχει το «κλειδί γέφυρας», 32 τυχαία bytes
///   που φτιάχνει το κινητό ([newBridgeToken]) και ο χρήστης βάζει στο Supabase (secret APP_TOKEN). Η function απορρίπτει
///   κάθε άλλη κλήση.
/// - Διεύθυνση και κλειδί κρυπτογραφημένα στο κινητό (Android Keystore, όπως τα tokens του Oura), εκτός αντιγράφων: σε
///   νέο κινητό η σύνδεση γίνεται ξανά.
/// - Στέλνεται μόνο ό,τι χρειάζεται το φαγητό (τρόφιμα, προτιμήσεις, κουζίνα, αριθμοί στόχων). Κανένα δεδομένο υγείας και
///   κανένα δεδομένο του Oura.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../oura/oura_api.dart' show OuraVault, VaultUnavailable;

const aiVaultUrl = 'ai_url';
const aiVaultToken = 'ai_token';

/// Μοντέλα (η function δέχεται μόνο αυτά). Σχέδιο εβδομάδας: το πιο προσεκτικό· συνταγές και αλλαγές: γρηγορότερο, ώστε
/// κάθε κλήση να χωράει άνετα στα 150″ του Supabase.
const aiModelPlan = 'claude-opus-5-5';
const aiModelRecipe = 'claude-sonnet-5-5';

/// Ως τόσο περιμένουμε μία απάντηση (το Supabase κόβει στα 150″).
const aiTimeout = Duration(seconds: 145);

/// Μία ερώτηση: [system] (σταθερό κομμάτι, κρατιέται στην cache του API για λίγα λεπτά) και τα μηνύματα της συζήτησης
/// (εναλλάξ «user» / «assistant», πρώτο και τελευταίο «user»).
class AiAsk {
  const AiAsk({required this.model, required this.system, required this.messages, this.maxTokens = 4000});
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
enum AiFail { notSetUp, offline, timeout, token, apiKey, paused, busy, credits, refused, server, bad }

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

String aiErrorText(AiFail f) => switch (f) {
      AiFail.notSetUp => 'Το AI δεν έχει συνδεθεί ακόμα: Ρυθμίσεις › AI για το φαγητό.',
      AiFail.offline => 'Χωρίς internet τώρα. Δοκίμασε όταν έχεις σύνδεση.',
      AiFail.timeout => 'Το AI άργησε πολύ να απαντήσει. Δοκίμασε ξανά σε λίγο.',
      AiFail.token => 'Η γέφυρα δεν δέχτηκε το κλειδί της εφαρμογής. Έλεγξε στο Supabase το APP_TOKEN (Ρυθμίσεις › AI για '
          'το φαγητό).',
      AiFail.apiKey => 'Η γέφυρα δεν έχει σωστό κλειδί του Claude API. Έλεγξε στο Supabase το ANTHROPIC_API_KEY (Ρυθμίσεις › '
          'AI για το φαγητό).',
      AiFail.paused => 'Το Supabase έκανε παύση στο project (λίγη χρήση). Άνοιξε το project στο supabase.com και πάτα '
          '«Restore project». Τα δεδομένα δεν χάνονται.',
      AiFail.busy => 'Το AI είναι φορτωμένο αυτή τη στιγμή. Δοκίμασε ξανά σε ένα λεπτό.',
      AiFail.credits => 'Τελείωσε η μηνιαία πίστωση του Claude API (ή το Console δεν είναι συνδεδεμένο με το πλάνο σου). '
          'Δεν έγινε καμία χρέωση.',
      AiFail.refused => 'Το AI δεν απάντησε σε αυτό. Δοκίμασε ξανά.',
      AiFail.server => 'Η γέφυρα ή το AI έχει πρόβλημα τώρα. Δοκίμασε ξανά σε λίγο.',
      AiFail.bad => 'Η απάντηση του AI δεν διαβάστηκε. Δοκίμασε ξανά.',
    };

/// Νέο κλειδί γέφυρας: 32 τυχαία bytes (κρυπτογραφικά ασφαλή), σε base64url χωρίς «=» (43 χαρακτήρες).
String newBridgeToken([math.Random? rnd]) {
  final r = rnd ?? math.Random.secure();
  return base64Url.encode([for (var i = 0; i < 32; i++) r.nextInt(256)]).replaceAll('=', '');
}

/// Η διεύθυνση της γέφυρας: μόνο https, μόνο *.supabase.co, μόνο η function «ai-food». Έτσι ένα λάθος επικόλλησης δεν
/// στέλνει ποτέ το κλειδί κάπου αλλού.
Uri? bridgeUrl(String raw) {
  final s = raw.trim();
  final m = RegExp(r'^https://([a-z0-9]{20})\.supabase\.co/functions/v1/ai-food/?$').firstMatch(s);
  if (m != null) return Uri.parse('https://${m.group(1)}.supabase.co/functions/v1/ai-food');
  // Μόνο το «Project ID» (20 πεζά/αριθμοί), όπως το δείχνει το Supabase.
  final id = RegExp(r'^[a-z0-9]{20}$').firstMatch(s);
  if (id != null) return Uri.parse('https://$s.supabase.co/functions/v1/ai-food');
  return null;
}

/// Η σύνδεση της εφαρμογής με τη γέφυρα (διεύθυνση + κλειδί), από το κρυπτογραφημένο αρχείο του κινητού.
class AiBridge {
  AiBridge(this.vault, {this.send = aiHttp});
  final OuraVault vault;
  final Future<(int, String)> Function(Uri url, String token, String body) send;

  static AiBridge? shared;

  Uri? _url;
  String? _token;
  bool _loaded = false;

  bool get ready => _url != null && _token != null;
  Uri? get url => _url;
  String? get token => _token;

  Future<void> load() async {
    try {
      final u = await vault.load(aiVaultUrl);
      final t = await vault.load(aiVaultToken);
      _url = u == null ? null : bridgeUrl(u);
      _token = t != null && t.length >= 32 ? t : null;
    } on VaultUnavailable {
      // ξανά στην επόμενη κλήση
      return;
    }
    _loaded = true;
  }

  /// Αποθηκεύει τη διεύθυνση. `false` αν δεν είναι διεύθυνση γέφυρας ή δεν γράφτηκε.
  Future<bool> setUrl(String raw) async {
    final u = bridgeUrl(raw);
    if (u == null) return false;
    if (!await vault.save(aiVaultUrl, u.toString())) return false;
    _url = u;
    return true;
  }

  /// Φτιάχνει (ή επιστρέφει το υπάρχον) κλειδί γέφυρας. null αν δεν γράφτηκε.
  Future<String?> ensureToken() async {
    if (!_loaded) await load();
    if (_token != null) return _token;
    final t = newBridgeToken();
    if (!await vault.save(aiVaultToken, t)) return null;
    _token = t;
    return t;
  }

  /// Νέο κλειδί (π.χ. αν το παλιό διέρρευσε). Μετά πρέπει να μπει ξανά στο Supabase.
  Future<String?> resetToken() async {
    final t = newBridgeToken();
    if (!await vault.save(aiVaultToken, t)) return null;
    _token = t;
    return t;
  }

  Future<void> disconnect() async {
    await vault.delete(aiVaultUrl);
    await vault.delete(aiVaultToken);
    _url = null;
    _token = null;
  }

  Future<AiReply> call(AiAsk ask) async {
    if (!_loaded) await load();
    final u = _url, t = _token;
    if (u == null || t == null) return const AiReply.failed(AiFail.notSetUp);
    final (int, String) r;
    try {
      r = await send(u, t, jsonEncode(ask.toJson())).timeout(aiTimeout);
    } on TimeoutException {
      return const AiReply.failed(AiFail.timeout);
    } on SocketException {
      return const AiReply.failed(AiFail.offline);
    } on HandshakeException {
      return const AiReply.failed(AiFail.offline);
    } on HttpException {
      return const AiReply.failed(AiFail.offline);
    }
    return parseBridgeReply(r.$1, r.$2);
  }
}

/// Η απάντηση της function: {"ok": true, "text": "…", "stop": "end_turn"} ή {"ok": false, "kind": "…"}.
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
  final kind = j is Map ? j['kind'] : null;
  return AiReply.failed(switch (kind) {
    'token' => AiFail.token,
    'apikey' || 'setup' => AiFail.apiKey,
    'credits' => AiFail.credits,
    'busy' => AiFail.busy,
    'timeout' => AiFail.timeout,
    'paused' => AiFail.paused,
    _ => status == 401 || status == 403
        ? AiFail.token
        : status == 429
            ? AiFail.busy
            : status == 504
                ? AiFail.timeout
                : status >= 500
                    ? AiFail.server
                    : AiFail.bad,
  });
}

/// Αποστολή με το HttpClient της Dart. Ποτέ δεν γράφεται το κλειδί σε μήνυμα σφάλματος.
Future<(int, String)> aiHttp(Uri url, String token, String body) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.postUrl(url).timeout(const Duration(seconds: 20));
    req.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    req.headers.set('x-app-token', token);
    req.add(utf8.encode(body));
    final res = await req.close().timeout(aiTimeout);
    final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 30));
    return (res.statusCode, text);
  } finally {
    client.close(force: true);
  }
}
