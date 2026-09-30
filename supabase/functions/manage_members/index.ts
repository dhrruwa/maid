// Owner: the family members who log in to the Family app (name + 4-digit PIN).
// body: { device_id, action: 'list' }
//       { device_id, action: 'add', name, pin }
//       { device_id, action: 'rename', id, name }
//       { device_id, action: 'set_pin', id, pin }   new PIN; their phone is logged out
//       { device_id, action: 'unlink', id }         their phone is logged out
//       { device_id, action: 'remove', id }         deactivated; future bookings cancelled
// Every action returns { members: [...] }; the others also return { member }
// ('remove' also returns { cancelled_bookings }).
// PINs and PIN hashes are never returned.
import { AppError, handle, requireFields } from "../_shared/http.ts";
import { must } from "../_shared/db.ts";
import { Ctx, ownerCtx } from "../_shared/auth.ts";
import { isPin, nameKey, pinHash, pinOf, slotCutoffMs, validName } from "../_shared/family.ts";
import { Slot } from "../_shared/pay.ts";
import { nowIst } from "../_shared/time.ts";
import { kannadaOf } from "../_shared/translate.ts";

interface Row {
  id: string;
  name: string;
  device_id: string | null;
  linked_at: string | null;
  created_at: string;
}

const COLS = "id,name,device_id,linked_at,created_at";

const pub = (m: Row) => ({
  id: m.id,
  name: m.name,
  linked: m.device_id !== null,
  linked_at: m.linked_at,
});

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const UNLINK = { device_id: null, fcm_token: null, linked_at: null };

async function list(ctx: Ctx): Promise<Row[]> {
  return must(
    await ctx.sb.from("members").select(COLS).eq("house_id", ctx.house.id).eq("active", true),
  ) as Row[];
}

const sorted = (rows: Row[]) =>
  rows.map(pub).sort((a, b) => a.name.localeCompare(b.name, "en", { sensitivity: "base" }));

function requirePin(body: Record<string, unknown>): string {
  const pin = pinOf(body.pin);
  if (!isPin(pin)) throw new AppError("BAD_PIN", "The PIN must be exactly 4 digits");
  return pin;
}

async function assertNameFree(ctx: Ctx, name: string, exceptId?: string) {
  const taken = (await list(ctx)).some((m) => m.id !== exceptId && nameKey(m.name) === nameKey(name));
  if (taken) throw new AppError("NAME_TAKEN", `There is already a family member called ${name}`, { name });
}

/** Runs a write; a unique-name clash from the database becomes NAME_TAKEN. */
async function write(
  q: PromiseLike<{ data: unknown; error: { message: string; code?: string } | null }>,
  name?: string,
): Promise<Row | null> {
  const res = await q;
  if (res.error?.code === "23505" && name) {
    throw new AppError("NAME_TAKEN", `There is already a family member called ${name}`, { name });
  }
  return must(res) as Row | null;
}

handle(async (body) => {
  requireFields(body, "action");
  const ctx = await ownerCtx(body);
  const { sb, house } = ctx;
  const action = String(body.action);

  if (action === "list") return { members: sorted(await list(ctx)) };

  let member: Row | null;
  let cancelled = 0;
  if (action === "add") {
    requireFields(body, "name", "pin");
    const name = validName(body.name);
    const pin = requirePin(body);
    await assertNameFree(ctx, name);
    const id = crypto.randomUUID();
    member = await write(
      sb.from("members").insert({
        id,
        house_id: house.id,
        name,
        name_kn: await kannadaOf(sb, name),
        pin_hash: await pinHash(id, pin),
      })
        .select(COLS).single(),
      name,
    );
  } else {
    requireFields(body, "id");
    const id = String(body.id);
    if (!UUID.test(id)) throw new AppError("NOT_FOUND", "Family member not found");
    const current = must(
      await sb.from("members").select(COLS).eq("id", id).eq("house_id", house.id).eq("active", true)
        .maybeSingle(),
    ) as Row | null;
    if (!current) throw new AppError("NOT_FOUND", "Family member not found");
    const update = (patch: Record<string, unknown>, name?: string) =>
      write(sb.from("members").update(patch).eq("id", id).select(COLS).single(), name);

    switch (action) {
      case "rename": {
        requireFields(body, "name");
        const name = validName(body.name);
        if (name === current.name) {
          member = current;
          break;
        }
        await assertNameFree(ctx, name, id);
        member = await update({ name, name_kn: await kannadaOf(sb, name) }, name);
        break;
      }
      case "set_pin": {
        requireFields(body, "pin");
        const pin = requirePin(body);
        member = await update({
          pin_hash: await pinHash(id, pin),
          failed_attempts: 0,
          locked_until: null,
          ...UNLINK,
        });
        break;
      }
      case "unlink":
        member = current.device_id === null ? current : await update(UNLINK);
        break;
      case "remove": {
        // Future meals they booked (whose window has not started) are cancelled first.
        const now = nowIst();
        const nowMs = Date.parse(now.iso);
        const upcoming = must(
          await sb.from("meal_bookings").select("id,date,slot").eq("member_id", id)
            .is("cancelled_at", null).gte("date", now.date),
        ) as { id: string; date: string; slot: Slot }[];
        const cancel = upcoming.filter((b) => slotCutoffMs(ctx.settings, b.date, b.slot) > nowMs)
          .map((b) => b.id);
        cancelled = cancel.length;
        if (cancel.length) {
          must(
            await sb.from("meal_bookings").update({ cancelled_at: new Date().toISOString() })
              .in("id", cancel).is("cancelled_at", null),
          );
        }
        member = await update({ active: false, ...UNLINK });
        break;
      }
      default:
        throw new AppError("BAD_ACTION", `Unknown action: ${action}`);
    }
  }

  const out: Record<string, unknown> = { member: member ? pub(member) : null, members: sorted(await list(ctx)) };
  if (action === "remove") out.cancelled_bookings = cancelled;
  return out;
});
