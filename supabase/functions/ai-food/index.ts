// «Υγεία & Φόρμα»: γέφυρα κινητού → Claude API, μόνο για το AI του φαγητού (19/11, έλεγχος 19/11).
//
// Ασφάλεια (το repo είναι δημόσιο):
// - Κανένα μυστικό εδώ. Το κλειδί του Claude API (ANTHROPIC_API_KEY) και το κλειδί της εφαρμογής (APP_TOKEN) είναι
//   secrets του Supabase που βάζει ο χρήστης.
// - Πρώτα ο έλεγχος του x-app-token (σύγκριση σταθερού χρόνου): χωρίς αυτό καμία άλλη πληροφορία δεν επιστρέφεται.
// - Μόνο POST, μόνο τα δύο μοντέλα, με όριο μεγέθους ερώτησης και απάντησης. Πόσο «σκέφτεται» το μοντέλο το ορίζει ΕΔΩ η
//   function (όχι η εφαρμογή), ώστε το κλειδί να μη γίνεται μοχλός κόστους.
// - Δεν γράφει ποτέ στα logs το περιεχόμενο (ερωτήσεις, απαντήσεις, κλειδιά): μόνο το είδος του σφάλματος.
// - Για όριο δαπάνης: κλειδί API σε ξεχωριστό Workspace του Claude Console, με όριο δαπάνης στο Workspace.
// Ανάπτυξη: supabase functions deploy ai-food --no-verify-jwt (ο έλεγχος γίνεται με το APP_TOKEN).

const MAX_BODY = 200_000; // bytes
const MAX_SYSTEM = 100_000; // χαρακτήρες
const MAX_TOKENS = 16_000; // σκέψη + απάντηση
const MAX_MESSAGES = 9;
const TIMEOUT_MS = 125_000; // το Supabase κόβει στα 150″· περιθώριο για το ανέβασμα και την απάντηση

// Τα μοντέλα και πόσο σκέφτονται (τεκμηρίωση effort, 19/11/2026):
// - Opus 5.5: η σκέψη είναι πάντα ανοιχτή· «low» για να χωράει στον χρόνο και στο όριο.
// - Sonnet 5.5: χωρίς σκέψη πριν την απάντηση («between_tools»), effort «medium».
const MODELS: Record<string, Record<string, unknown>> = {
  "claude-opus-5-5": { output_config: { effort: "low" } },
  "claude-sonnet-5-5": { thinking: { type: "between_tools" }, output_config: { effort: "medium" } },
};

const enc = new TextEncoder();

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function fail(status: number, kind: string, log = kind): Response {
  console.log(`ai-food: ${log} (${status})`);
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
  if (typeof model !== "string" || !(model in MODELS)) return null;
  if (typeof max !== "number" || !Number.isInteger(max) || max < 1 || max > MAX_TOKENS) return null;
  if (typeof system !== "string" || system.trim().length === 0 || system.length > MAX_SYSTEM) return null;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > MAX_MESSAGES) return null;
  const out: Msg[] = [];
  for (let i = 0; i < messages.length; i++) {
    const m = messages[i] as Record<string, unknown>;
    const role = i % 2 === 0 ? "user" : "assistant";
    if (typeof m !== "object" || m === null || m.role !== role || typeof m.content !== "string" || m.content.trim().length === 0) {
      return null;
    }
    out.push({ role, content: m.content });
  }
  if (out[out.length - 1].role !== "user") return null;
  return { model, max, system, messages: out };
}

// Το είδος του σφάλματος του Claude API (τεκμηρίωση «API errors» του Claude).
function apiFailKind(status: number, body: Record<string, unknown>): [number, string] {
  const err = (body.error ?? {}) as Record<string, unknown>;
  const type = String(err.type ?? "");
  const msg = String(err.message ?? "").toLowerCase();
  const details = (err.details ?? {}) as Record<string, unknown>;
  const code = String(details.error_code ?? "");
  if (status === 402 || type === "billing_error" || code === "enforced_spend_limit_reached" ||
      msg.includes("credit") || msg.includes("billing") || msg.includes("usage limit")) return [402, "credits"];
  if (status === 401 || status === 403 || type === "authentication_error" || type === "permission_error") {
    return [502, "apikey"];
  }
  if (status === 404 || type === "not_found_error") return [502, "model"];
  if (status === 429 || status === 529 || type === "overloaded_error" || type === "rate_limit_error") return [503, "busy"];
  if (status === 504 || type === "timeout_error") return [504, "timeout"];
  if (status >= 500) return [502, "server"];
  return [502, "bad"];
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return fail(405, "method");
  // 1. Το κλειδί της εφαρμογής, πριν από οτιδήποτε άλλο.
  const appToken = Deno.env.get("APP_TOKEN") ?? "";
  if (appToken.length < 32) return fail(401, "token", "setup-token");
  if (!sameToken(req.headers.get("x-app-token") ?? "", appToken)) return fail(401, "token");
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
  if (apiKey.length === 0) return fail(500, "setup", "setup-key");

  // 2. Η ερώτηση.
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

  // 3. Το Claude API.
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
        ...MODELS[ask.model],
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
    const [status, kind] = apiFailKind(res.status, body);
    return fail(status, kind, `${kind} api-${res.status}`);
  }
  // Μόνο το κείμενο (οι σκέψεις του μοντέλου δεν επιστρέφονται) και οι αριθμοί χρήσης (χωρίς περιεχόμενο).
  const content = Array.isArray(body.content) ? body.content : [];
  const text = content
    .filter((b: Record<string, unknown>) => b && b.type === "text" && typeof b.text === "string")
    .map((b: Record<string, unknown>) => b.text as string)
    .join("");
  const u = (body.usage ?? {}) as Record<string, unknown>;
  const usage: Record<string, number> = {};
  for (const k of ["input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]) {
    if (typeof u[k] === "number") usage[k] = u[k] as number;
  }
  return json(200, { ok: true, text, stop: String(body.stop_reason ?? ""), usage });
});
