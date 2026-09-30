// English → Kannada for the Maid app. Text is translated once, when it is
// saved, and cached in `translations`. Gemini (GEMINI_API_KEY secret) does it
// first: it writes what a cook would say ("no onion" → ಈರುಳ್ಳಿ ಹಾಕಬೇಡಿ,
// "Set Dosa" → ಸೆಟ್ ದೋಸೆ). If it is slow, busy or unset, Google's free web
// endpoint takes over, then MyMemory's machine translation. MyMemory's shared
// memory also holds user-submitted junk ("Ramesh" → a birthday greeting), so
// only its "MT!" answers are used. Never throws: null means "show the English".
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const TIMEOUT_MS = 2500;
const GEMINI_MODEL = "gemini-flash-lite-latest"; // ~1 s; the 3.x names were 2–4 s or busy
const GEMINI_TIMEOUT_MS = 4000;
const KANNADA = /[ಀ-೿]/;
const LATIN = /[A-Za-z]/;

async function fetchJson(url: string): Promise<unknown> {
  const res = await fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS) });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return await res.json();
}

/** Several texts in one request; a null for any item it could not do. */
async function gemini(texts: string[]): Promise<(string | null)[]> {
  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key || !texts.length) return texts.map(() => null);
  try {
    const prompt = "Translate each English item for a Kannada-speaking home cook in Karnataka into " +
      "natural Kannada script. Dish names: write the name Kannada cooks use (transliterate when " +
      "there is no Kannada word, e.g. 'Set Dosa' -> 'ಸೆಟ್ ದೋಸೆ'). People's names: write them in " +
      "Kannada script. Return only a JSON array of strings, same order and length.\n" +
      JSON.stringify(texts);
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": key },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: prompt }] }],
          generationConfig: { responseMimeType: "application/json", temperature: 0 },
        }),
        signal: AbortSignal.timeout(GEMINI_TIMEOUT_MS),
      },
    );
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const d = await res.json();
    const out = JSON.parse(d?.candidates?.[0]?.content?.parts?.[0]?.text ?? "null");
    if (!Array.isArray(out) || out.length !== texts.length) throw new Error("bad reply shape");
    return out.map((k) => (typeof k === "string" && KANNADA.test(k) ? k.trim().slice(0, 600) : null));
  } catch (e) {
    console.warn(`translate (gemini) failed: ${e}`);
    return texts.map(() => null);
  }
}

async function google(text: string): Promise<string | null> {
  const q = new URLSearchParams({ client: "gtx", sl: "en", tl: "kn", dt: "t", q: text });
  const d = await fetchJson(`https://translate.googleapis.com/translate_a/single?${q}`) as unknown[][];
  const out = (d?.[0] as unknown[][] ?? []).map((p) => (typeof p?.[0] === "string" ? p[0] : "")).join("");
  return out.trim() || null;
}

async function myMemory(text: string): Promise<string | null> {
  const q = new URLSearchParams({ q: text, langpair: "en|kn", mt: "1" });
  const d = await fetchJson(`https://api.mymemory.translated.net/get?${q}`) as {
    matches?: { translation?: string; "created-by"?: string }[];
  };
  const mt = d?.matches?.find((m) => m["created-by"] === "MT!" && m.translation?.trim());
  return mt?.translation?.trim() ?? null;
}

async function translateOne(text: string): Promise<string | null> {
  for (const engine of [google, myMemory]) {
    try {
      const kn = await engine(text);
      if (kn && KANNADA.test(kn)) return kn.slice(0, 600);
    } catch (e) {
      console.warn(`translate (${engine.name}) failed: ${e}`);
    }
  }
  return null;
}

const clean = (t: unknown) => (typeof t === "string" ? t.trim() : "");

/**
 * Kannada for each text, in the same order. Empty text → null; text that is
 * already Kannada (or has no English letters, like "2 + 1") comes back as is.
 */
export async function toKannada(sb: SupabaseClient, texts: unknown[]): Promise<(string | null)[]> {
  const src = texts.map(clean);
  const need = [...new Set(src.filter((t) => t && LATIN.test(t) && !KANNADA.test(t)))];
  const found = new Map<string, string>();
  if (need.length) {
    const { data } = await sb.from("translations").select("en,kn").in("en", need);
    for (const r of (data ?? []) as { en: string; kn: string }[]) found.set(r.en, r.kn);
    const missing = need.filter((t) => !found.has(t));
    const byGemini = await gemini(missing);
    const fresh = await Promise.all(missing.map((t, i) => byGemini[i] ?? translateOne(t)));
    const rows = missing.map((en, i) => ({ en, kn: fresh[i] })).filter((r) => r.kn) as { en: string; kn: string }[];
    for (const r of rows) found.set(r.en, r.kn);
    // A cache miss is not an error: the next save simply translates again.
    if (rows.length) await sb.from("translations").upsert(rows, { onConflict: "en", ignoreDuplicates: true });
  }
  return src.map((t) => (!t ? null : LATIN.test(t) && !KANNADA.test(t) ? found.get(t) ?? null : t));
}

export async function kannadaOf(sb: SupabaseClient, text: unknown): Promise<string | null> {
  return (await toKannada(sb, [text]))[0];
}

/**
 * The owner typed the Kannada themselves (e.g. corrected a dish name): keep it
 * for this text from now on. Blank → forget the correction.
 */
export async function rememberKannada(sb: SupabaseClient, en: unknown, kn: unknown) {
  const e = clean(en);
  const k = clean(kn);
  if (!e) return;
  if (!k) {
    await sb.from("translations").delete().eq("en", e).eq("manual", true);
    return;
  }
  await sb.from("translations").upsert(
    { en: e, kn: k.slice(0, 600), manual: true, updated_at: new Date().toISOString() },
    { onConflict: "en" },
  );
}
