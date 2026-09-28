import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { AppError } from "./http.ts";

export type Actor = "owner" | "maid" | "system";

/**
 * Service-role client. The `x-actor` header is read by the activity_log
 * trigger so every change records who made it.
 */
export function db(actor: Actor): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { "x-actor": actor } },
    },
  );
}

/** Throws on a Supabase error, returns data otherwise. */
// deno-lint-ignore no-explicit-any
export function must(res: { data: unknown; error: { message: string; code?: string } | null }): any {
  if (res.error) {
    if (res.error.code === "23505") {
      throw new AppError("DUPLICATE", "This entry already exists");
    }
    throw new Error(res.error.message);
  }
  return res.data;
}
