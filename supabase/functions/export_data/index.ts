// Owner: everything for this house (including soft-deleted rows) as JSON.
// The app turns it into an Excel file with one sheet per table.
import { handle } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";

const TABLES: [string, string][] = [
  ["attendance", "date"],
  ["holidays", "date"],
  ["leave_requests", "date"],
  ["dishes", "name"],
  ["menu", "date"],
  ["payments", "month"],
  ["monthly_snapshots", "month"],
  ["cook_device", "paired_at"],
  ["activity_log", "id"],
];

const SECRET = ["fcm_token", "device_id", "owner_device_id", "owner_fcm_token", "qr_token", "owner_pin_hash", "recovery_key_hash"];

// deno-lint-ignore no-explicit-any
function strip(row: Record<string, any>) {
  const out = { ...row };
  for (const k of SECRET) delete out[k];
  return out;
}

handle(async (body) => {
  const ctx = await ownerCtx(body);
  const data: Record<string, unknown[]> = {};
  for (const [t, order] of TABLES) {
    const rows: Record<string, unknown>[] = [];
    // Page through in chunks of 1000 (PostgREST default max).
    for (let from = 0;; from += 1000) {
      const chunk = must(
        await ctx.sb.from(t).select("*").eq("house_id", ctx.house.id).order(order)
          .range(from, from + 999),
      ) as Record<string, unknown>[];
      rows.push(...chunk);
      if (chunk.length < 1000) break;
    }
    data[t] = rows.map(strip);
  }
  data.settings = [strip(ctx.settings as unknown as Record<string, unknown>)];
  data.house = [strip(ctx.house as unknown as Record<string, unknown>)];
  return { exported_at: new Date().toISOString(), data };
});
