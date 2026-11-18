// «Υγεία & Φόρμα»: γέφυρα κινητού → Claude API, μόνο για το AI του φαγητού (19/11).
//
// Ασφάλεια (το repo είναι δημόσιο):
// - Κανένα μυστικό εδώ. Το κλειδί του Claude API (ANTHROPIC_API_KEY) και το κλειδί της εφαρμογής (APP_TOKEN) είναι
//   secrets του Supabase που βάζει ο χρήστης.
// - Δέχεται μόνο κλήσεις με το σωστό x-app-token (σύγκριση σταθερού χρόνου), μόνο POST, μόνο τα δύο μοντέλα, με όριο
//   μεγέθους ερώτησης και απάντησης.
// - Δεν γράφει ποτέ στα logs το περιεχόμενο (ερωτήσεις, απαντήσεις, κλειδιά): μόνο το είδος του σφάλματος.
// Ανάπτυξη: supabase functions deploy ai-food --no-verify-jwt (ο έλεγχος γίνεται με το APP_TOKEN).

const MODELS = new Set(["claude-opus-5-5", "claude-sonnet-5-5"]);
const MAX_BODY = 400_000; // bytes
const MAX_TOKENS = 8000;
const MAX_MESSAGES = 9;
const TIMEOUT_MS = 140_000; // το Supabase κόβει στα 150″

const enc = new TextEncoder();

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function fail(status: number, kind: string): Response {
  console.log(`ai-food: ${kind} (${status})`);
  return json(status, { ok: false, kind });
}

// Σύγκριση σταθερού χρόνου, ώστε ο χρόνος απάντησης να μη δείχνει πόσοι χαρακτήρες ήταν σωστοί.
function sameToken(a: string, b: string): boolean {
  const x = enc.encode(a), y = enc.encode(b);
  let diff = x.length ^ y.length;
  const n = Math.max(x.length, y.length);
  for (let i = 0; i < n; i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0 && x.length > 0;
}

type Msg = { role: "user" | "assistant"; content: string };

function readAsk(j: unknown): { model: string; max: number; system: string; messages: Msg[] } | null {
  if (typeof j !== "object" || j === null) return null;
  const o = j as Record<string, unknown>;
  const model = o.model, max = o.max_tokens, system = o.system, messages = o.messages;
  if (typeof model !== "string" || !MODELS.has(model)) return null;
  if (typeof max !== "number" || !Number.isInteger(max) || max < 1 || max > MAX_TOKENS) return null;
  if (typeof system !== "string" || system.length === 0) return null;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > MAX_MESSAGES) return null;
  const out: Msg[] = [];
  for (let i = 0; i < messages.length; i++) {
    const m = messages[i] as Record<string, unknown>;
    const role = i % 2 === 0 ? "user" : "assistant";
    if (typeof m !== "object" || m === null || m.role !== role || typeof m.content !== "string" || m.content.length === 0) {
      return null;
    }
    out.push({ role, content: m.content });
  }
  if (out[out.length - 1].role !== "user") return null;
  return { model, max, system, messages: out };
}

// Λίγη κίνηση στη βάση, ώστε το δωρεάν project να μη θεωρείται ανενεργό. Δεν περιμένουμε και δεν μας νοιάζει αν αποτύχει.
function touchDb() {
  const url = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !key) return;
  fetch(`${url}/rest/v1/`, { headers: { apikey: key }, signal: AbortSignal.timeout(5000) })
    .then((r) => r.body?.cancel())
    .catch(() => {});
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return fail(405, "method");
  const appToken = Deno.env.get("APP_TOKEN") ?? "";
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
  if (appToken.length < 32 || apiKey.length === 0) return fail(500, "setup");
  if (!sameToken(req.headers.get("x-app-token") ?? "", appToken)) return fail(401, "token");

  const len = Number(req.headers.get("content-length") ?? "0");
  if (len > MAX_BODY) return fail(413, "size");
  let raw: string;
  try {
    raw = await req.text();
  } catch {
    return fail(400, "bad");
  }
  if (enc.encode(raw).length > MAX_BODY) return fail(413, "size");
  let ask;
  try {
    ask = readAsk(JSON.parse(raw));
  } catch {
    ask = null;
  }
  if (!ask) return fail(400, "bad");
  touchDb();

  let res: Response;
  try {
    res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: ask.model,
        max_tokens: ask.max,
        // Το σταθερό κομμάτι (λίστα τροφίμων) μένει στην cache του API για λίγα λεπτά: γρηγορότερες οι επόμενες συνταγές.
        system: [{ type: "text", text: ask.system, cache_control: { type: "ephemeral" } }],
        messages: ask.messages,
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (e) {
    return fail(504, e instanceof DOMException && e.name === "TimeoutError" ? "timeout" : "server");
  }

  let body: Record<string, unknown> = {};
  try {
    body = await res.json();
  } catch {
    return fail(502, "server");
  }
  if (!res.ok) {
    const err = (body.error ?? {}) as Record<string, unknown>;
    const type = String(err.type ?? "");
    const msg = String(err.message ?? "").toLowerCase();
    if (res.status === 401 || res.status === 403) return fail(502, "apikey");
    if (res.status === 429 || res.status === 529 || type === "overloaded_error") return fail(503, "busy");
    if (msg.includes("credit") || msg.includes("billing")) return fail(402, "credits");
    if (res.status >= 500) return fail(502, "server");
    return fail(502, "bad");
  }
  const content = Array.isArray(body.content) ? body.content : [];
  const text = content
    .filter((b: Record<string, unknown>) => b && b.type === "text" && typeof b.text === "string")
    .map((b: Record<string, unknown>) => b.text as string)
    .join("");
  return json(200, { ok: true, text, stop: String(body.stop_reason ?? "") });
});
