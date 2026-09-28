// Request/response plumbing shared by every Edge Function.

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** A business error the app shows to the user. `code` is stable; apps translate it. */
export class AppError extends Error {
  constructor(
    public code: string,
    message: string,
    public details: Record<string, unknown> = {},
    public status = 200,
  ) {
    super(message);
  }
}

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// deno-lint-ignore no-explicit-any
export type Body = Record<string, any>;

/**
 * Wraps a handler. Success → { ok: true, ...result }.
 * AppError → { ok: false, error: { code, message, details } } (HTTP 200 so the
 * apps can read it without special exception handling).
 */
export function handle(fn: (body: Body, req: Request) => Promise<unknown>) {
  Deno.serve(async (req) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    let body: Body = {};
    try {
      const text = await req.text();
      body = text ? JSON.parse(text) : {};
    } catch {
      return json({ ok: false, error: { code: "BAD_JSON", message: "Body must be JSON" } }, 400);
    }
    try {
      const result = await fn(body, req);
      return json({ ok: true, ...(result as object ?? {}) });
    } catch (e) {
      if (e instanceof AppError) {
        return json(
          { ok: false, error: { code: e.code, message: e.message, details: e.details } },
          e.status,
        );
      }
      console.error(e);
      return json(
        { ok: false, error: { code: "SERVER_ERROR", message: String((e as Error)?.message ?? e) } },
        500,
      );
    }
  });
}

export function requireFields(body: Body, ...names: string[]) {
  for (const n of names) {
    if (body[n] === undefined || body[n] === null || body[n] === "") {
      throw new AppError("MISSING_FIELD", `Missing field: ${n}`, { field: n }, 400);
    }
  }
}

/** For scheduled / internal functions: caller must send the CRON_SECRET. */
export function requireCronSecret(req: Request) {
  const expected = Deno.env.get("CRON_SECRET");
  if (!expected || req.headers.get("x-cron-secret") !== expected) {
    throw new AppError("FORBIDDEN", "Invalid cron secret", {}, 403);
  }
}

export function randomHex(bytes: number): string {
  const a = new Uint8Array(bytes);
  crypto.getRandomValues(a);
  return Array.from(a, (b) => b.toString(16).padStart(2, "0")).join("");
}

export async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Metres between two lat/lng points. */
export function haversineM(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}
