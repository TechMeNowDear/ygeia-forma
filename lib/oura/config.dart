/// Ρυθμίσεις της σύνδεσης με το Oura, σε ΕΝΑ σημείο.
///
/// Τη μέρα που θα έρθει το δαχτυλίδι: εγγραφή εφαρμογής στο developer portal της Oura (developer.ouraring.com· το
/// παλιό cloud.ouraring.com/oauth/applications παραπέμπει εκεί) με Redirect URI ακριβώς [ouraRedirectUri], και το
/// Client ID μπαίνει στο [ouraClientId].
/// Το Client ID ΔΕΝ είναι μυστικό (φαίνεται σε κάθε σελίδα σύνδεσης). Το Client Secret δεν μπαίνει ΠΟΤΕ εδώ.
library;

/// Το Client ID της εφαρμογής μας στην Oura. Κενό = η σύνδεση δεν έχει ενεργοποιηθεί ακόμα.
const ouraClientId = 'af0dbf14-b534-4187-8d6b-6cc0cc6f41a1';

/// Τα δικαιώματα (scope) που ζητάμε, σε ΜΙΑ γραμμή. Κενό = η προεπιλογή του [ouraOAuth] («daily» στο classic,
/// «extapi:daily» στο v2). Αν το νέο portal δείχνει άλλα κουτάκια, π.χ. `'daily sleep'` ή `'extapi:daily'`.
/// Την απόφαση για το αν φτάνουν την παίρνουν ΜΟΝΟ τα 401/403 των δεδομένων (το «scope» της απάντησης δεν ελέγχεται).
const ouraScopes = '';

/// Ο μεσάζων για την ανταλλαγή κωδικού και την ανανέωση: Netlify Function στο site/netlify/functions/oura-token.mjs.
/// Η Oura ζητά Client Secret, και το secret δεν μπαίνει ΠΟΤΕ στην εφαρμογή: ζει μόνο στο Netlify (OURA_CLIENT_SECRET).
/// Ο μεσάζων δέχεται μόνο το δικό μας Client ID, απαιτεί PKCE και δεν αποθηκεύει τίποτα. Κενό = απευθείας στην Oura.
const ouraTokenProxy = 'https://ygeia-forma.netlify.app/api/oura/token';

/// Οι δύο διευθύνσεις από τις οποίες η εφαρμογή δέχεται την επιστροφή μετά τη σύνδεση. Τις πιάνει η
/// OuraCallbackActivity (manifest):
/// - https (Android App Link, επαληθευμένο με /.well-known/assetlinks.json στο ygeia-forma.netlify.app). Αν ο browser
///   δεν ανοίξει την εφαρμογή, η σελίδα /oura/callback προωθεί το ίδιο query στο ygeiaforma://oura-callback.
/// - ygeiaforma://oura-callback (custom scheme): ΜΟΝΟ ως αυτή η προώθηση από τη σελίδα /oura/callback.
/// Γίνονται δεκτές ΜΟΝΟ αυτές οι δύο ακριβείς μορφές (δες parseCallback).
const ouraRedirectHttpsHost = 'ygeia-forma.netlify.app';
const ouraRedirectHttpsPath = '/oura/callback';
const ouraRedirectHttps = 'https://$ouraRedirectHttpsHost$ouraRedirectHttpsPath';
const ouraRedirectScheme = 'ygeiaforma';
const ouraRedirectHost = 'oura-callback';
const ouraRedirectCustom = '$ouraRedirectScheme://$ouraRedirectHost';

/// Η διεύθυνση που δηλώνεται στην Oura και στέλνεται ΙΔΙΑ στη σελίδα σύνδεσης και στην ανταλλαγή κωδικού.
/// Round 7 (R7-A11-5): ΜΟΝΟ η https. Ο μεσάζων (site/netlify/functions/oura-token.mjs, REDIRECTS· έλεγχος 2, C10) δέχεται
/// μόνο αυτήν: με το ygeiaforma:// κάθε σύνδεση θα τελείωνε σε «Η Oura δεν δέχτηκε τη σύνδεση». Το ygeiaforma://
/// χρησιμεύει μόνο ως προώθηση από τη σελίδα /oura/callback (πιο πάνω). Δεν υπάρχει «εναλλακτική μίας γραμμής».
const ouraRedirectUri = ouraRedirectHttps;

/// Ποιος διακομιστής σύνδεσης της Oura χρησιμοποιείται.
/// - portal (προεπιλογή, έλεγχος 4/11): όπως το classic, αλλά η σελίδα σύνδεσης είναι η
///   https://developer.ouraring.com/authorize, που η τεκμηρίωση της Oura (cloud.ouraring.com/docs/authentication,
///   4/11/2026) δίνει «for new OAuth clients» — η δική μας εφαρμογή γράφτηκε στο developer.ouraring.com. Ίδια
///   ανταλλαγή κωδικού, ίδια ανάκληση· μπορεί να ανοίξει την έγκριση μέσα στην εφαρμογή της Oura.
/// - classic: ό,τι περιγράφει η τεκμηρίωση για τις παλιές εφαρμογές (cloud.ouraring.com/oauth/authorize).
/// - v2: ο νεότερος (api.ouraring.com/v2/oauth, RFC 8414 metadata στο /.well-known/oauth-authorization-server),
///   που δηλώνει ρητά «token_endpoint_auth_methods_supported: none» (εφαρμογές χωρίς secret, με PKCE).
/// Η αλλαγή είναι μόνο αυτή η γραμμή (και οι διευθύνσεις είναι ήδη στη λίστα του Android, OuraBridge.ALLOWED_HOSTS).
const ouraOAuth = OuraOAuthEndpoints.portal;

class OuraOAuthEndpoints {
  const OuraOAuthEndpoints._(this.authorize, this.token, this.revoke, this.scopes, this.revokeParam);

  final String authorize;
  final String token;
  final String revoke;

  /// Προεπιλογή όταν το [ouraScopes] είναι κενό. Μόνο ό,τι χρειάζεται: «daily» («Daily summaries of sleep, activity and readiness», OpenAPI 1.43).
  /// Καλύπτει τα /sleep (με τους παλμούς, το HRV και τις αναπνοές της νύχτας), /daily_sleep, /daily_readiness.
  /// Και «spo2» (7/11): ο μέσος όρος οξυγόνου της νύχτας (daily_spo2). Το όνομα είναι «spo2» κατά την επίσημη
  /// τεκμηρίωση (cloud.ouraring.com/docs/authentication)· το «spo2Daily» η Oura το αγνοεί σιωπηλά.
  /// Όχι heartrate (δεν διαβάζουμε τη χρονοσειρά παλμών), email, personal, workout, tag, session.
  final String scopes;

  /// Πώς στέλνεται το token στην ανάκληση.
  final String revokeParam;

  static const classic = OuraOAuthEndpoints._(
    'https://cloud.ouraring.com/oauth/authorize',
    'https://api.ouraring.com/oauth/token',
    'https://api.ouraring.com/oauth/revoke',
    'daily spo2',
    'access_token',
  );

  /// Η σελίδα σύνδεσης για νέες εφαρμογές (developer.ouraring.com)· τα υπόλοιπα όπως το [classic].
  static const portal = OuraOAuthEndpoints._(
    'https://developer.ouraring.com/authorize',
    'https://api.ouraring.com/oauth/token',
    'https://api.ouraring.com/oauth/revoke',
    'daily spo2',
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

/// Αν η σύνδεση ζητά το οξυγόνο (άδεια «spo2»).
bool ouraRequestsSpo2([OuraOAuthEndpoints e = ouraOAuth]) =>
    (ouraScopes.trim().isEmpty ? e.scopes : ouraScopes).toLowerCase().contains('spo2');

/// Το API δεδομένων (v2).
const ouraApiBase = 'https://api.ouraring.com/v2/usercollection/';

/// Τα συνθετικά δεδομένα δοκιμών της Oura (ίδια μορφή, χωρίς δαχτυλίδι). Θέλει οποιοδήποτε Authorization.
const ouraSandboxBase = 'https://api.ouraring.com/v2/sandbox/usercollection/';

/// Η Oura θέλει πάντα User-Agent που να λέει ποια εφαρμογή είμαστε.
const ouraUserAgent = 'YgeiaForma/1.0 (Android)';

/// Αυτόματη ανάγνωση όταν ανοίγει η εφαρμογή ή επιστρέφω σε αυτήν, το πολύ τόσο συχνά (όταν δεν περιμένουμε νύχτα).
const ouraMinInterval = Duration(minutes: 30);

/// Round 1 (S5-10): ρητή ενέργεια του χρήστη (τράβηγμα προς τα κάτω, «Ενημέρωση τώρα», κουμπί κάρτας) ή επιστροφή
/// στην εφαρμογή όσο περιμένουμε τη νύχτα: διαβάζει ΠΑΝΤΑ. Μόνο φρένο αυτά τα λίγα δευτερόλεπτα από την προηγούμενη
/// προσπάθεια (για διπλά πατήματα) και η αναμονή που ζήτησε η ίδια η Oura (429). Κόστος μιας ανάγνωσης: 3–4 μικρά
/// αιτήματα· το όριο της Oura είναι 5.000 αιτήματα ανά 5 λεπτά.
const ouraUserGap = Duration(seconds: 10);

/// Round 1 (S5-2 / U2a-05): πριν από αυτή την ώρα η νύχτα με τη σημερινή ημερομηνία δεν έχει τελειώσει (κοιμάσαι ή
/// δεν έχεις κοιμηθεί ακόμα): δεν «περιμένουμε» τίποτα και δεν λέμε ότι λείπει. Ίδιο όριο με την πρώτη νύχτα της
/// σύνδεσης (`firstNightChoice`).
const ouraNightDueHour = 4;

/// Πόσες μέρες πίσω ξαναδιαβάζονται κάθε φορά (η Oura μπορεί να διορθώσει την προηγούμενη νύχτα).
const ouraRecentDays = 3;

/// Νύχτες του Oura που λείπουν ακόμα ξαναζητούνται για τόσες μέρες πίσω (έλεγχος 4/11, A3: το δαχτυλίδι μπορεί να
/// συγχρονίσει αργά, π.χ. σε ταξίδι), με το ίδιο όριο συχνότητας ([ouraMinInterval]).
const ouraMissingDays = 30;

/// Αν η εφαρμογή έμεινε κλειστή πολύ καιρό, το Oura διαβάζεται ως τόσες μέρες πίσω (από την αρχή της εποχής).
const ouraMaxBackDays = 90;

/// Πόσες νύχτες κρατιούνται με όλες τις λεπτομέρειες (φάσεις, ώρες) για τις οθόνες.
const ouraDetailDays = 45;
