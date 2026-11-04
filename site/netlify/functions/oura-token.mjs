// Μεσάζων για την ανταλλαγή κωδικού και την ανανέωση της σύνδεσης με την Oura.
//
// Γιατί υπάρχει: η Oura ζητά Client Secret στην ανταλλαγή κωδικού, και το secret δεν μπαίνει ΠΟΤΕ μέσα στην
// εφαρμογή. Εδώ το secret ζει μόνο ως μεταβλητή περιβάλλοντος του Netlify (OURA_CLIENT_SECRET), που τη βάζει ο
// ιδιοκτήτης στο Netlify. Ο μεσάζων:
// - δέχεται ΜΟΝΟ POST με form-urlencoded σώμα, για το δικό μας Client ID·
// - στην ανταλλαγή κωδικού απαιτεί code_verifier (PKCE) και ακριβώς μία από τις δηλωμένες διευθύνσεις επιστροφής·
// - προσθέτει το secret και προωθεί το ΙΔΙΟ αίτημα στην Oura, μία φορά (ο κωδικός είναι μιας χρήσης: ποτέ δεύτερη
//   προσπάθεια)·
// - επιστρέφει την απάντηση της Oura όπως είναι, χωρίς cache·
// - δεν αποθηκεύει και δεν καταγράφει τίποτα (ούτε κωδικούς ούτε tokens)· δεν βλέπει ποτέ δεδομένα υγείας.

const CLIENT_ID = 'af0dbf14-b534-4187-8d6b-6cc0cc6f41a1';
const REDIRECTS = new Set([
  'https://ygeia-forma.netlify.app/oura/callback',
  'ygeiaforma://oura-callback',
]);
// Πού προωθείται. Αλλάζει χωρίς νέα έκδοση της εφαρμογής, με τη μεταβλητή OURA_TOKEN_URL στο Netlify.
const ALLOWED_TARGETS = new Set([
  'https://api.ouraring.com/oauth/token',
  'https://api.ouraring.com/v2/oauth/token',
]);
const DEFAULT_TARGET = 'https://api.ouraring.com/oauth/token';
const MAX_BODY = 4096;
const UPSTREAM_TIMEOUT_MS = 20000;

function reply(status, obj) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
  });
}

function fail(status, error, description) {
  return reply(status, { error, error_description: description });
}

export default async (req) => {
  if (req.method !== 'POST') return fail(405, 'invalid_request', 'POST only');
  const type = (req.headers.get('content-type') || '').toLowerCase();
  if (!type.startsWith('application/x-www-form-urlencoded')) {
    return fail(415, 'invalid_request', 'form-urlencoded only');
  }
  const raw = await req.text();
  if (raw.length > MAX_BODY) return fail(413, 'invalid_request', 'body too large');

  const secret = Netlify.env.get('OURA_CLIENT_SECRET');
  if (!secret) return fail(503, 'proxy_not_configured', 'OURA_CLIENT_SECRET missing');

  const inp = new URLSearchParams(raw);
  if (inp.get('client_id') !== CLIENT_ID) return fail(400, 'invalid_client', 'unknown client');
  if (inp.has('client_secret')) return fail(400, 'invalid_request', 'client_secret not accepted');

  const grant = inp.get('grant_type');
  const out = new URLSearchParams();
  out.set('grant_type', grant || '');
  out.set('client_id', CLIENT_ID);
  out.set('client_secret', secret);

  if (grant === 'authorization_code') {
    const code = inp.get('code');
    const verifier = inp.get('code_verifier');
    const redirect = inp.get('redirect_uri');
    if (!code || code.length > 2048) return fail(400, 'invalid_request', 'code');
    if (!verifier || !/^[A-Za-z0-9\-._~]{43,128}$/.test(verifier)) {
      return fail(400, 'invalid_request', 'code_verifier (PKCE) required');
    }
    if (!REDIRECTS.has(redirect)) return fail(400, 'invalid_request', 'redirect_uri');
    out.set('code', code);
    out.set('code_verifier', verifier);
    out.set('redirect_uri', redirect);
  } else if (grant === 'refresh_token') {
    const refresh = inp.get('refresh_token');
    if (!refresh || refresh.length > 4096) return fail(400, 'invalid_request', 'refresh_token');
    out.set('refresh_token', refresh);
  } else {
    return fail(400, 'unsupported_grant_type', 'grant_type');
  }

  const configured = Netlify.env.get('OURA_TOKEN_URL');
  const target = configured && ALLOWED_TARGETS.has(configured) ? configured : DEFAULT_TARGET;

  let upstream;
  try {
    upstream = await fetch(target, {
      method: 'POST',
      headers: {
        'content-type': 'application/x-www-form-urlencoded',
        accept: 'application/json',
        'user-agent': 'YgeiaForma-token-proxy/1',
      },
      body: out.toString(),
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  } catch (_) {
    // Δίκτυο ή λήξη χρόνου: η εφαρμογή το βλέπει ως προσωρινό πρόβλημα. Καμία δεύτερη προσπάθεια εδώ.
    return fail(502, 'upstream_unreachable', 'Oura not reachable');
  }

  const body = await upstream.text();
  return new Response(body, {
    status: upstream.status,
    headers: {
      'content-type': upstream.headers.get('content-type') || 'application/json',
      'cache-control': 'no-store',
    },
  });
};

export const config = {
  path: '/api/oura/token',
  method: ['POST'],
};
