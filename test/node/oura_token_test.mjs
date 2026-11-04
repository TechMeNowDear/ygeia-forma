// Τρέχει τον μεσάζοντα (site/netlify/functions/oura-token.mjs) με node, με ψεύτικα Netlify.env και fetch (έλεγχος 2,
// C10). Καλείται από το test/oura_proxy_test.dart όταν υπάρχει node (στο GitHub Actions υπάρχει). Έξοδος ≠ 0 = σφάλμα.
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const env = { OURA_CLIENT_SECRET: 'S3CRET' };
globalThis.Netlify = { env: { get: (k) => env[k] } };
let upstream = null;
let calls = [];
globalThis.fetch = async (url, init) => {
  calls.push({ url, init });
  if (upstream instanceof Error) throw upstream;
  return new Response(upstream ?? '{"access_token":"A","refresh_token":"R"}', {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
};
const realTimeout = AbortSignal.timeout.bind(AbortSignal);
let timeoutMs = null;
AbortSignal.timeout = (ms) => {
  timeoutMs = ms;
  return realTimeout(ms);
};

const fn = path.resolve(process.argv[2] || 'site/netlify/functions/oura-token.mjs');
const mod = await import(pathToFileURL(fn).href);
const handler = mod.default;
const CLIENT = 'af0dbf14-b534-4187-8d6b-6cc0cc6f41a1';
const VERIFIER = 'a'.repeat(64);

function post(fields, type = 'application/x-www-form-urlencoded') {
  return new Request('https://ygeia-forma.netlify.app/api/oura/token', {
    method: 'POST',
    headers: { 'content-type': type },
    body: new URLSearchParams(fields).toString(),
  });
}
const code = (redirect) => ({
  grant_type: 'authorization_code',
  client_id: CLIENT,
  code: 'C',
  code_verifier: VERIFIER,
  redirect_uri: redirect,
});

let failed = 0;
async function check(name, f) {
  calls = [];
  upstream = null;
  timeoutMs = null;
  try {
    await f();
    console.log(`ok - ${name}`);
  } catch (e) {
    failed++;
    console.log(`not ok - ${name}: ${e.message}`);
  }
}
function eq(a, b, what) {
  if (a !== b) throw new Error(`${what}: ${JSON.stringify(a)} ≠ ${JSON.stringify(b)}`);
}

await check('GET → 405', async () => {
  const r = await handler(new Request('https://x/api/oura/token'));
  eq(r.status, 405, 'status');
});
await check('Ανταλλαγή με https: προωθείται με το secret, χρονικό όριο 8 s', async () => {
  const r = await handler(post(code('https://ygeia-forma.netlify.app/oura/callback')));
  eq(r.status, 200, 'status');
  eq(calls.length, 1, 'κλήσεις στην Oura');
  const sent = new URLSearchParams(calls[0].init.body);
  eq(sent.get('client_secret'), 'S3CRET', 'secret');
  eq(sent.get('redirect_uri'), 'https://ygeia-forma.netlify.app/oura/callback', 'redirect');
  eq(timeoutMs, 8000, 'χρονικό όριο (κάτω από το όριο του Netlify)');
  eq(r.headers.get('cache-control'), 'no-store', 'cache');
});
await check('Ανταλλαγή με ygeiaforma:// → 400 (μόνο το επαληθευμένο https)', async () => {
  const r = await handler(post(code('ygeiaforma://oura-callback')));
  eq(r.status, 400, 'status');
  eq((await r.json()).error, 'invalid_request', 'error');
  eq(calls.length, 0, 'καμία κλήση στην Oura');
});
await check('Χωρίς PKCE → 400', async () => {
  const f = code('https://ygeia-forma.netlify.app/oura/callback');
  delete f.code_verifier;
  eq((await handler(post(f))).status, 400, 'status');
});
await check('client_secret από τον καλούντα → 400', async () => {
  const r = await handler(post({ grant_type: 'refresh_token', client_id: CLIENT, refresh_token: 'R', client_secret: 'x' }));
  eq(r.status, 400, 'status');
});
await check('Άλλο Client ID → 400 invalid_client', async () => {
  const r = await handler(post({ grant_type: 'refresh_token', client_id: 'other', refresh_token: 'R' }));
  eq(r.status, 400, 'status');
  eq((await r.json()).error, 'invalid_client', 'error');
});
await check('Ανανέωση: προωθείται μία φορά', async () => {
  const r = await handler(post({ grant_type: 'refresh_token', client_id: CLIENT, refresh_token: 'R' }));
  eq(r.status, 200, 'status');
  eq(new URLSearchParams(calls[0].init.body).get('refresh_token'), 'R', 'refresh');
});
await check('Η Oura δεν απαντά → 502 upstream_unreachable', async () => {
  upstream = new Error('timeout');
  const r = await handler(post({ grant_type: 'refresh_token', client_id: CLIENT, refresh_token: 'R' }));
  eq(r.status, 502, 'status');
  eq((await r.json()).error, 'upstream_unreachable', 'error');
});
await check('Χωρίς secret στο Netlify → 503 proxy_not_configured', async () => {
  delete env.OURA_CLIENT_SECRET;
  const r = await handler(post({ grant_type: 'refresh_token', client_id: CLIENT, refresh_token: 'R' }));
  env.OURA_CLIENT_SECRET = 'S3CRET';
  eq(r.status, 503, 'status');
  eq((await r.json()).error, 'proxy_not_configured', 'error');
});
await check('Όριο αιτημάτων στο config (Netlify rateLimit)', async () => {
  const rl = mod.config.rateLimit;
  if (!rl) throw new Error('λείπει rateLimit');
  eq(rl.windowSize <= 180, true, 'windowSize ≤ 180');
  eq(rl.windowLimit > 0 && rl.windowLimit <= 60, true, 'windowLimit');
  eq(JSON.stringify(rl.aggregateBy), '["ip","domain"]', 'aggregateBy');
  eq(mod.config.path, '/api/oura/token', 'path');
});

console.log(failed === 0 ? 'ALL PASSED' : `${failed} FAILED`);
process.exit(failed === 0 ? 0 : 1);
