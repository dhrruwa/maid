// Owner: activity timeline (newest first) with filters and readable text.
// body: { device_id, types?: ['attendance','menu','leave','holiday','payment','settings'],
//         from?, to?, actor?: 'owner'|'maid'|'system', search?, before_id?, limit? }
import { handle } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { ownerCtx } from "../_shared/auth.ts";
import { isValidDate, minToLabel, monthLabel, shortDate, toIst } from "../_shared/time.ts";

const TYPE_TABLES: Record<string, string[]> = {
  attendance: ["attendance"],
  menu: ["menu", "dishes"],
  leave: ["leave_requests"],
  holiday: ["holidays"],
  payment: ["payments", "monthly_snapshots"],
  settings: ["settings", "house", "cook_device", "pairing_tokens"],
};

// deno-lint-ignore no-explicit-any
type J = Record<string, any> | null;

interface Row {
  id: number;
  actor: string;
  action: string;
  entity_type: string;
  entity_id: string | null;
  old_value: J;
  new_value: J;
  note: string | null;
  created_at: string;
}

const who = (a: string) => (a === "owner" ? "Owner" : a === "maid" ? "Maid" : "System");
const slotName = (s: string) => (s === "full" ? "full day" : s);
const SETTING_LABELS: Record<string, string> = {
  weekday_rate: "weekday rate",
  weekend_rate: "weekend rate",
  morning_start: "morning start",
  morning_end: "morning end",
  evening_start: "evening start",
  evening_end: "evening end",
  notify_scan: "scan notifications",
  notify_leave: "leave notifications",
  notify_offline: "offline notifications",
  notify_payday: "payday notifications",
  notify_menu: "menu notifications to maid",
  name: "house name",
  radius_m: "radius",
  lat: "location",
};

function changes(o: J, n: J, skip: string[] = []): string[] {
  if (!o || !n) return [];
  const out: string[] = [];
  for (const k of Object.keys(n)) {
    if (["updated_at", "created_at", ...skip].includes(k)) continue;
    if (JSON.stringify(o[k]) !== JSON.stringify(n[k])) out.push(k);
  }
  return out;
}

function describe(r: Row, dishNames: Map<string, string>): string {
  const n = r.new_value ?? {};
  const o = r.old_value ?? {};
  const W = who(r.actor);
  switch (r.entity_type) {
    case "attendance": {
      const when = `${slotName(n.slot)} on ${shortDate(n.date)}`;
      if (r.action === "create") {
        if (n.is_manual) return `${W} added ${when} manually (₹${n.amount})`;
        const t = minToLabel(toIst(new Date(n.scanned_at)).minutes);
        return `${W} marked ${n.slot} attendance at ${t}${n.is_offline ? " (offline)" : ""} (₹${n.amount})`;
      }
      if (r.action === "delete") return `${W} removed ${when} entry`;
      if (r.action === "restore") return `${W} restored ${when} entry`;
      return `${W} edited ${when} entry`;
    }
    case "menu": {
      const dish = dishNames.get(n.dish_id) ?? "a dish";
      const where = `${shortDate(n.date)} ${n.slot}`;
      if (r.action === "create") return `${W} added ${dish} to ${where} menu`;
      if (r.action === "delete") return `${W} removed ${dish} from ${where} menu`;
      if (r.action === "restore") return `${W} restored ${dish} on ${where} menu`;
      return `${W} changed ${dish} on ${where} menu`;
    }
    case "dishes":
      if (r.action === "create") return `${W} saved dish "${n.name}"`;
      if (r.action === "delete") return `${W} deleted dish "${n.name}"`;
      if (r.action === "restore") return `${W} restored dish "${n.name}"`;
      if (o.name !== n.name) return `${W} renamed dish "${o.name}" → "${n.name}"`;
      return `${W} edited dish "${n.name}"`;
    case "holidays": {
      const what = `${n.paid ? "paid" : "unpaid"} holiday on ${shortDate(n.date)} (${slotName(n.slot)})`;
      if (r.action === "create") return `${W} set ${what}`;
      if (r.action === "delete") return `${W} removed ${what}`;
      if (r.action === "restore") return `${W} restored ${what}`;
      return `${W} changed ${what}`;
    }
    case "leave_requests": {
      const what = `leave for ${shortDate(n.date)} (${slotName(n.slot)})`;
      if (r.action === "create") return `${W} requested ${what}`;
      if (r.action === "delete") return `${W} removed ${what}`;
      if (r.action === "restore") return `${W} restored ${what}`;
      if (o.status !== n.status) {
        const d = n.status === "approved_paid"
          ? "approved as paid"
          : n.status === "approved_unpaid"
          ? "approved as unpaid"
          : n.status === "rejected"
          ? "rejected"
          : `set to ${n.status}`;
        return `${W} ${d}: ${what}`;
      }
      return `${W} edited ${what}`;
    }
    case "payments":
      return `${W} marked ${monthLabel(n.month)} salary ₹${n.total_amount} as paid (${shortDate(n.paid_on)})`;
    case "monthly_snapshots":
      return r.action === "create"
        ? `${monthLabel(n.month)} summary frozen`
        : `${monthLabel(n.month)} slip saved`;
    case "settings": {
      const ch = changes(o, n);
      if (r.action === "create") return `Default settings created`;
      return `${W} changed ${ch.map((k) => `${SETTING_LABELS[k] ?? k}: ${o[k]} → ${n[k]}`).join(", ")}`;
    }
    case "house": {
      if (r.action === "create") return `${W} set up the house "${n.name}"`;
      const ch = changes(o, n);
      const parts: string[] = [];
      for (const k of ch) {
        if (k === "qr_token") parts.push("regenerated the attendance QR");
        else if (k === "owner_pin_hash") parts.push("changed the PIN");
        else if (k === "owner_fcm_token") continue;
        else if (k === "owner_device_id") parts.push("moved the owner app to a new phone");
        else if (k === "lng") continue;
        else if (k === "lat") parts.push("updated the house location");
        else parts.push(`changed ${SETTING_LABELS[k] ?? k}: ${o[k]} → ${n[k]}`);
      }
      return parts.length ? `${W} ${parts.join(", ")}` : `${W} updated the house`;
    }
    case "cook_device":
      if (r.action === "create") return `Maid phone paired (${n.name})`;
      if (o.active && !n.active) return `Maid phone unpaired (${n.name})`;
      if (o.lang !== n.lang) return `Maid switched app language to ${n.lang === "kn" ? "Kannada" : "English"}`;
      return `Maid phone updated (${n.name})`;
    case "pairing_tokens":
      return r.action === "create" ? `${W} created a pairing code` : `Pairing code used or expired`;
    default:
      return `${W} ${r.action}d ${r.entity_type}`;
  }
}

handle(async (body) => {
  const ctx = await ownerCtx(body);
  const { sb, house } = ctx;
  const limit = Math.min(Number(body.limit) || 50, 200);

  let q = sb.from("activity_log").select("*").eq("house_id", house.id);

  const types: string[] = Array.isArray(body.types) ? body.types : [];
  const tables = types.flatMap((t) => TYPE_TABLES[t] ?? []);
  if (tables.length) q = q.in("entity_type", tables);
  if (["owner", "maid", "system"].includes(body.actor)) q = q.eq("actor", body.actor);
  if (isValidDate(body.from)) q = q.gte("created_at", new Date(body.from + "T00:00:00+05:30").toISOString());
  if (isValidDate(body.to)) q = q.lte("created_at", new Date(body.to + "T23:59:59.999+05:30").toISOString());
  if (body.before_id) q = q.lt("id", Number(body.before_id));

  if (body.search && String(body.search).trim()) {
    const s = String(body.search).trim().replace(/[,()*%\\]/g, " ").slice(0, 60);
    const dishIds = (must(
      await sb.from("dishes").select("id").eq("house_id", house.id).ilike("name", `%${s}%`),
    ) as { id: string }[]).map((d) => d.id);
    const ors = [
      `note.ilike.*${s}*`,
      `new_value->>name.ilike.*${s}*`,
      `new_value->>reason.ilike.*${s}*`,
      `new_value->>note.ilike.*${s}*`,
    ];
    if (dishIds.length) ors.push(`new_value->>dish_id.in.(${dishIds.join(",")})`);
    q = q.or(ors.join(","));
  }

  // The house's dish names load alongside the log (one round trip instead of
  // two); any referenced dish not found there is still looked up by id below.
  const [logRes, houseDishes] = await Promise.all([
    q.order("id", { ascending: false }).limit(limit),
    sb.from("dishes").select("id,name").eq("house_id", house.id),
  ]);
  const rows = must(logRes) as Row[];

  // Hide noisy internal rows (FCM token refreshes, pairing token bookkeeping).
  const visible = rows.filter((r) => {
    if (r.entity_type === "pairing_tokens" && r.action === "update") return false;
    if (r.action === "update" && (r.entity_type === "house" || r.entity_type === "cook_device")) {
      const ch = changes(r.old_value, r.new_value);
      if (ch.every((k) => k === "owner_fcm_token" || k === "fcm_token")) return false;
    }
    if (r.entity_type === "monthly_snapshots" && r.action === "update") return false;
    return true;
  });

  const ids = new Set<string>();
  for (const r of visible) {
    if (r.entity_type === "menu") {
      if (r.new_value?.dish_id) ids.add(r.new_value.dish_id);
      if (r.old_value?.dish_id) ids.add(r.old_value.dish_id);
    }
  }
  const dishNames = new Map<string, string>();
  if (ids.size) {
    const known = new Map<string, string>();
    if (!houseDishes.error) {
      for (const d of houseDishes.data as { id: string; name: string }[]) known.set(d.id, d.name);
    }
    const missing = [...ids].filter((id) => !known.has(id));
    for (const id of ids) if (known.has(id)) dishNames.set(id, known.get(id)!);
    if (missing.length) {
      for (const d of must(await sb.from("dishes").select("id,name").in("id", missing)) as { id: string; name: string }[]) {
        dishNames.set(d.id, d.name);
      }
    }
  }

  const restorable = new Set(["attendance", "holidays", "dishes", "menu", "leave_requests"]);
  return {
    events: visible.map((r) => ({
      id: r.id,
      actor: r.actor,
      action: r.action,
      entity_type: r.entity_type,
      entity_id: r.entity_id,
      text: describe(r, dishNames),
      note: r.note,
      old_value: r.old_value,
      new_value: r.new_value,
      created_at: r.created_at,
      can_restore: r.action === "delete" && restorable.has(r.entity_type),
    })),
    next_before_id: rows.length === limit ? rows[rows.length - 1].id : null,
  };
});
