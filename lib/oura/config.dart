/// Ρυθμίσεις της σύνδεσης με το Oura, σε ΕΝΑ σημείο.
///
/// Τη μέρα που θα έρθει το δαχτυλίδι: εγγραφή εφαρμογής στο https://cloud.ouraring.com/oauth/applications
/// με Redirect URI ακριβώς [ouraRedirectUri], και το Client ID μπαίνει στο [ouraClientId].
/// Το Client ID ΔΕΝ είναι μυστικό (φαίνεται σε κάθε σελίδα σύνδεσης). Το Client Secret δεν μπαίνει ΠΟΤΕ εδώ.
library;

/// Το Client ID της εφαρμογής μας στην Oura. Κενό = η σύνδεση δεν έχει ενεργοποιηθεί ακόμα.
const ouraClientId = '';

/// Αν η Oura δεν δέχεται ανταλλαγή κωδικού χωρίς Client Secret (PKCE μόνο), εδώ μπαίνει η διεύθυνση ενός
/// μικρού διακομιστή που προσθέτει το secret και προωθεί το ίδιο αίτημα στην Oura. Κενό = απευθείας στην Oura.
const ouraTokenProxy = '';

/// Οι δύο διευθύνσεις επιστροφής μετά τη σύνδεση. Τις πιάνει η OuraCallbackActivity (manifest):
/// - https (Android App Link, επαληθευμένο με /.well-known/assetlinks.json στο ygeia-forma.netlify.app). Αν ο browser
///   δεν ανοίξει την εφαρμογή, η σελίδα /oura/callback προωθεί το ίδιο query στο ygeiaforma://oura-callback.
/// - ygeiaforma://oura-callback (custom scheme), εφεδρική.
/// Γίνονται δεκτές ΜΟΝΟ αυτές οι δύο ακριβείς μορφές (δες parseCallback).
const ouraRedirectHttpsHost = 'ygeia-forma.netlify.app';
const ouraRedirectHttpsPath = '/oura/callback';
const ouraRedirectHttps = 'https://$ouraRedirectHttpsHost$ouraRedirectHttpsPath';
const ouraRedirectScheme = 'ygeiaforma';
const ouraRedirectHost = 'oura-callback';
const ouraRedirectCustom = '$ouraRedirectScheme://$ouraRedirectHost';

/// Η διεύθυνση που δηλώνεται στην Oura και στέλνεται ΙΔΙΑ στη σελίδα σύνδεσης και στην ανταλλαγή κωδικού.
/// Για custom scheme: `const ouraRedirectUri = ouraRedirectCustom;`
const ouraRedirectUri = ouraRedirectHttps;

/// Ποιος διακομιστής σύνδεσης της Oura χρησιμοποιείται.
/// - classic: ό,τι περιγράφει η τεκμηρίωση (cloud.ouraring.com/docs/authentication) και το OpenAPI 1.43.
/// - v2: ο νεότερος (api.ouraring.com/v2/oauth, RFC 8414 metadata στο /.well-known/oauth-authorization-server),
///   που δηλώνει ρητά «token_endpoint_auth_methods_supported: none» (εφαρμογές χωρίς secret, με PKCE).
/// Αν η classic απορρίψει την ανταλλαγή χωρίς secret, αλλάζει μόνο αυτή η γραμμή.
const ouraOAuth = OuraOAuthEndpoints.classic;

class OuraOAuthEndpoints {
  const OuraOAuthEndpoints._(this.authorize, this.token, this.revoke, this.scopes, this.revokeParam);

  final String authorize;
  final String token;
  final String revoke;

  /// Μόνο ό,τι χρειάζεται: «daily» («Daily summaries of sleep, activity and readiness», OpenAPI 1.43).
  /// Καλύπτει τα /sleep (με τους παλμούς, το HRV και τις αναπνοές της νύχτας), /daily_sleep, /daily_readiness.
  /// Όχι heartrate (δεν διαβάζουμε τη χρονοσειρά παλμών), email, personal, spo2, workout, tag, session.
  final String scopes;

  /// Πώς στέλνεται το token στην ανάκληση.
  final String revokeParam;

  static const classic = OuraOAuthEndpoints._(
    'https://cloud.ouraring.com/oauth/authorize',
    'https://api.ouraring.com/oauth/token',
    'https://api.ouraring.com/oauth/revoke',
    'daily',
    'access_token',
  );

  static const v2 = OuraOAuthEndpoints._(
    'https://api.ouraring.com/v2/oauth/authorize',
    'https://api.ouraring.com/v2/oauth/token',
    'https://api.ouraring.com/v2/oauth/token/revoke',
    'extapi:daily',
    'token',
  );
}

/// Η διεύθυνση για ανταλλαγή κωδικού και ανανέωση (η Oura ή ο διακομιστής-μεσάζων).
String get ouraTokenEndpoint => ouraTokenProxy.isNotEmpty ? ouraTokenProxy : ouraOAuth.token;

/// Το API δεδομένων (v2).
const ouraApiBase = 'https://api.ouraring.com/v2/usercollection/';

/// Τα συνθετικά δεδομένα δοκιμών της Oura (ίδια μορφή, χωρίς δαχτυλίδι). Θέλει οποιοδήποτε Authorization.
const ouraSandboxBase = 'https://api.ouraring.com/v2/sandbox/usercollection/';

/// Η Oura θέλει πάντα User-Agent που να λέει ποια εφαρμογή είμαστε.
const ouraUserAgent = 'YgeiaForma/1.0 (Android)';

/// Ανάγνωση όταν ανοίγει η εφαρμογή ή επιστρέφω σε αυτήν, το πολύ τόσο συχνά.
const ouraMinInterval = Duration(minutes: 30);

/// Πόσες μέρες πίσω ξαναδιαβάζονται κάθε φορά (η Oura μπορεί να διορθώσει την προηγούμενη νύχτα).
const ouraRecentDays = 3;

/// Πόσες νύχτες κρατιούνται με όλες τις λεπτομέρειες (φάσεις, ώρες) για τις οθόνες.
const ouraDetailDays = 45;
