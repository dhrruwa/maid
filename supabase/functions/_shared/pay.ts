// Salary / attendance calculator. One place that turns the rules into numbers,
// used by the dashboard, the calendar, the salary card, slips and payday.

import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { must } from "./db.ts";
import { Ctx, Settings } from "./auth.ts";
import {
  daysBetween,
  dowOf,
  IstNow,
  isWeekend,
  monthBounds,
  nextMonth,
  nowIst,
  timeToMin,
  toIst,
} from "./time.ts";

export type Slot = "morning" | "evening";
export const SLOTS: Slot[] = ["morning", "evening"];

export type SlotState =
  | "done"
  | "missed"
  | "pending" // today, window not over yet
  | "upcoming" // a future day
  | "holiday_paid"
  | "holiday_unpaid"
  | "leave_paid"
  | "leave_unpaid"
  | "not_needed" // Saturday/Sunday evening
  | "none"; // before the house was set up

export type DayStatus = "green" | "yellow" | "red" | "blue" | "purple" | "grey" | "none";

export interface DishLine {
  menu_id: string;
  dish_id: string;
  name: string;
  youtube_url: string | null;
  dish_notes: string | null;
  notes: string | null;
  // Kannada copies for the Maid app (null: not translated, show the English).
  name_kn: string | null;
  dish_notes_kn: string | null;
  notes_kn: string | null;
}

export interface SlotInfo {
  state: SlotState;
  rate: number;
  amount: number;
  attendance: null | {
    id: string;
    scanned_at: string;
    uploaded_at: string;
    distance_m: number | null;
    is_offline: boolean;
    is_manual: boolean;
    note: string | null;
    amount: number;
  };
  holiday: null | { id: string; paid: boolean; note: string | null; slot: string };
  leave: null | { id: string; status: string; reason: string | null; slot: string };
}

export interface DayInfo {
  date: string;
  dow: number;
  status: DayStatus;
  amount: number;
  has_menu: boolean;
  menu: { morning: DishLine[]; evening: DishLine[] };
  slots: { morning: SlotInfo; evening: SlotInfo };
}

export interface MonthSummary {
  month: string;
  house_name: string;
  maid_name: string | null;
  generated_at: string;
  frozen: boolean;
  rates: {
    weekday_rate: number;
    weekend_rate: number;
    paid_off_rate?: number; // absent on slips frozen before it existed
    morning_start: string;
    morning_end: string;
    evening_start: string;
    evening_end: string;
  };
  days: DayInfo[];
  counts: {
    visits_done: number;
    missed: number;
    full_days: number;
    half_days: number;
    holidays: number;
    leaves: number;
    weekday_visits: number;
    weekend_visits: number;
    paid_off_slots: number;
  };
  totals: {
    earned: number;
    weekday_amount: number;
    weekend_amount: number;
    paid_off_amount: number;
    remaining_expected: number;
    expected_total: number;
    lost: number;
  };
  holidays: { id: string; date: string; slot: string; paid: boolean; note: string | null }[];
  leaves: {
    id: string;
    date: string;
    slot: string;
    status: string;
    reason: string | null;
    created_at: string;
    decided_at: string | null;
  }[];
  payment: null | { paid_on: string; total_amount: number };
}

export function slotExpected(date: string, slot: Slot): boolean {
  return slot === "morning" || !isWeekend(date);
}

export function slotRate(settings: Settings, date: string, slot: Slot): number {
  if (!slotExpected(date, slot)) return 0;
  return isWeekend(date) ? settings.weekend_rate : settings.weekday_rate;
}

export function slotWindow(settings: Settings, slot: Slot): [number, number] {
  return slot === "morning"
    ? [timeToMin(settings.morning_start), timeToMin(settings.morning_end)]
    : [timeToMin(settings.evening_start), timeToMin(settings.evening_end)];
}

const covers = (rowSlot: string, slot: Slot) => rowSlot === "full" || rowSlot === slot;

export async function menuFor(
  sb: SupabaseClient,
  houseId: string,
  from: string,
  to: string,
): Promise<Map<string, { morning: DishLine[]; evening: DishLine[] }>> {
  const rows = must(
    await sb.from("menu")
      .select("id,date,slot,notes,notes_kn,sort_order,dish_id,dishes(name,name_kn,youtube_url,notes,notes_kn)")
      .eq("house_id", houseId).is("deleted_at", null)
      .gte("date", from).lte("date", to)
      .order("sort_order"),
  ) as {
    id: string;
    date: string;
    slot: Slot;
    notes: string | null;
    notes_kn: string | null;
    dish_id: string;
    dishes: {
      name: string;
      name_kn: string | null;
      youtube_url: string | null;
      notes: string | null;
      notes_kn: string | null;
    } | null;
  }[];
  const out = new Map<string, { morning: DishLine[]; evening: DishLine[] }>();
  for (const r of rows) {
    if (!out.has(r.date)) out.set(r.date, { morning: [], evening: [] });
    out.get(r.date)![r.slot].push({
      menu_id: r.id,
      dish_id: r.dish_id,
      name: r.dishes?.name ?? "?",
      youtube_url: r.dishes?.youtube_url ?? null,
      dish_notes: r.dishes?.notes ?? null,
      notes: r.notes,
      name_kn: r.dishes?.name_kn ?? null,
      dish_notes_kn: r.dishes?.notes_kn ?? null,
      notes_kn: r.notes_kn,
    });
  }
  return out;
}

/**
 * Month summary. Paid months come back frozen from monthly_snapshots so old
 * slips never change even if rates change later.
 */
export async function computeMonth(
  ctx: Ctx,
  month: string,
  opts: { now?: IstNow; ignoreSnapshot?: boolean } = {},
): Promise<MonthSummary> {
  const { sb, house, settings } = ctx;

  const now = opts.now ?? nowIst();
  const { first, last, days } = monthBounds(month);
  const startDate = toIst(new Date(house.created_at)).date;

  // The frozen-snapshot lookup runs in the same parallel batch as the live
  // queries (one round trip instead of two); a snapshot, if present, wins.
  const [snapRes, att, hol, lv, pay, menuRes, firstPair] = await Promise.all([
    opts.ignoreSnapshot ? null : sb.from("monthly_snapshots").select("summary")
      .eq("house_id", house.id).eq("month", month).maybeSingle(),
    sb.from("attendance").select("*").eq("house_id", house.id).is("deleted_at", null)
      .gte("date", first).lte("date", last),
    sb.from("holidays").select("id,date,slot,paid,note").eq("house_id", house.id)
      .is("deleted_at", null).gte("date", first).lte("date", last).order("date"),
    sb.from("leave_requests").select("id,date,slot,status,reason,created_at,decided_at")
      .eq("house_id", house.id).is("deleted_at", null).gte("date", first).lte("date", last)
      .order("date"),
    sb.from("payments").select("paid_on,total_amount").eq("house_id", house.id)
      .eq("month", month).maybeSingle(),
    // Settled, so a menu error cannot hide a frozen snapshot (it is rethrown below).
    menuFor(sb, house.id, first, last).then(
      (m) => ({ m, err: null as unknown }),
      (err) => ({ m: null, err: err as unknown }),
    ),
    sb.from("cook_device").select("paired_at").eq("house_id", house.id)
      .order("paired_at", { ascending: true }).limit(1).maybeSingle(),
  ]);
  if (snapRes) {
    const snap = must(snapRes) as { summary: MonthSummary } | null;
    if (snap) return { ...snap.summary, frozen: true };
  }
  if (menuRes.err) throw menuRes.err;
  const menus = menuRes.m!;
  const attendance = must(att) as Record<string, unknown>[];
  // Missed visits only count once the maid phone was first paired, so the
  // setup day (or days before pairing) never show up as "missed".
  const pairedAt = (must(firstPair) as { paired_at: string } | null)?.paired_at;
  const trackFromMs = pairedAt ? Date.parse(pairedAt) : Infinity;
  const slotEndMs = (date: string, slot: Slot) =>
    Date.parse(date + "T00:00:00Z") + (slotWindow(settings, slot)[1] - 330) * 60000;
  const holidays = must(hol) as MonthSummary["holidays"];
  // A day off the owner pays for (holiday or approved paid leave): a fixed
  // amount per meal, not the visit rate.
  const paidOff = settings.paid_off_rate ?? 35;
  const leaves = must(lv) as MonthSummary["leaves"];
  const payment = must(pay) as MonthSummary["payment"];

  const counts = {
    visits_done: 0,
    missed: 0,
    full_days: 0,
    half_days: 0,
    holidays: 0,
    leaves: 0,
    weekday_visits: 0,
    weekend_visits: 0,
    paid_off_slots: 0,
  };
  const totals = {
    earned: 0,
    weekday_amount: 0,
    weekend_amount: 0,
    paid_off_amount: 0,
    remaining_expected: 0,
    expected_total: 0,
    lost: 0,
  };

  const dayInfos: DayInfo[] = days.map((date) => {
    const dayHolidays = holidays.filter((h) => h.date === date);
    const dayLeaves = leaves.filter((l) => l.date === date);
    const approvedLeaves = dayLeaves.filter((l) => l.status.startsWith("approved"));
    if (dayHolidays.length) counts.holidays++;
    if (approvedLeaves.length) counts.leaves++;

    const slotInfo = (slot: Slot): SlotInfo => {
      const rate = slotRate(settings, date, slot);
      const a = attendance.find((r) => r.date === date && r.slot === slot);
      const h = dayHolidays.find((x) => covers(x.slot, slot));
      const l = approvedLeaves.find((x) => covers(x.slot, slot)) ??
        dayLeaves.find((x) => covers(x.slot, slot));
      const info: SlotInfo = {
        state: "none",
        rate,
        amount: 0,
        attendance: a
          ? {
            id: a.id as string,
            scanned_at: a.scanned_at as string,
            uploaded_at: a.uploaded_at as string,
            distance_m: a.distance_m as number | null,
            is_offline: a.is_offline as boolean,
            is_manual: a.is_manual as boolean,
            note: a.note as string | null,
            amount: a.amount as number,
          }
          : null,
        holiday: h ? { id: h.id, paid: h.paid, note: h.note, slot: h.slot } : null,
        leave: l ? { id: l.id, status: l.status, reason: l.reason, slot: l.slot } : null,
      };
      const approved = l && l.status.startsWith("approved") ? l : null;

      if (a) {
        info.state = "done";
        info.amount = a.amount as number;
      } else if (date < startDate) {
        info.state = "none";
      } else if (!slotExpected(date, slot)) {
        info.state = "not_needed";
      } else if (h) {
        info.state = h.paid ? "holiday_paid" : "holiday_unpaid";
        info.amount = h.paid ? paidOff : 0;
      } else if (approved) {
        const paid = approved.status === "approved_paid";
        info.state = paid ? "leave_paid" : "leave_unpaid";
        info.amount = paid ? paidOff : 0;
      } else if (date < now.date || (date === now.date && now.minutes >= slotWindow(settings, slot)[1])) {
        info.state = slotEndMs(date, slot) <= trackFromMs ? "none" : "missed";
      } else if (date === now.date) {
        info.state = "pending";
      } else {
        info.state = "upcoming";
      }
      return info;
    };

    const slots = { morning: slotInfo("morning"), evening: slotInfo("evening") };
    const isPast = date <= now.date;
    let dayAmount = 0;

    for (const s of SLOTS) {
      const i = slots[s];
      switch (i.state) {
        case "done":
          counts.visits_done++;
          totals.earned += i.amount;
          dayAmount += i.amount;
          if (isWeekend(date)) {
            counts.weekend_visits++;
            totals.weekend_amount += i.amount;
          } else {
            counts.weekday_visits++;
            totals.weekday_amount += i.amount;
          }
          break;
        case "holiday_paid":
        case "leave_paid":
          dayAmount += i.amount;
          if (isPast) {
            counts.paid_off_slots++;
            totals.earned += i.amount;
            totals.paid_off_amount += i.amount;
          } else {
            totals.remaining_expected += i.amount;
          }
          break;
        case "missed":
          counts.missed++;
          totals.lost += i.rate;
          break;
        case "pending":
        case "upcoming":
          totals.remaining_expected += i.rate;
          break;
      }
    }

    // Day colour
    const relevant = SLOTS.map((s) => slots[s]).filter((i) => i.state !== "not_needed" && i.state !== "none");
    const hasHoliday = relevant.some((i) => i.state.startsWith("holiday"));
    const hasLeave = relevant.some((i) => i.state.startsWith("leave"));
    const work = relevant.filter((i) => !i.state.startsWith("holiday") && !i.state.startsWith("leave"));
    const done = work.filter((i) => i.state === "done").length;
    const missed = work.filter((i) => i.state === "missed").length;
    let status: DayStatus;
    if (relevant.length === 0) status = "none";
    else if (work.length === 0) status = hasHoliday ? "blue" : hasLeave ? "purple" : "grey";
    else if (date > now.date) status = hasHoliday ? "blue" : hasLeave ? "purple" : "grey";
    else if (done === work.length) status = "green";
    else if (done > 0) status = "yellow";
    else if (missed === 0) status = "grey"; // today, nothing due yet
    else status = "red";

    if (status === "green" && done > 0) counts.full_days++;
    if (status === "yellow" && missed > 0) counts.half_days++;

    const menu = menus.get(date) ?? { morning: [], evening: [] };
    return {
      date,
      dow: dowOf(date),
      status,
      amount: dayAmount,
      has_menu: menu.morning.length + menu.evening.length > 0,
      menu,
      slots,
    };
  });

  totals.expected_total = totals.earned + totals.remaining_expected;

  return {
    month,
    house_name: house.name,
    maid_name: ctx.cook?.name ?? null,
    generated_at: new Date().toISOString(),
    frozen: false,
    rates: {
      weekday_rate: settings.weekday_rate,
      weekend_rate: settings.weekend_rate,
      paid_off_rate: paidOff,
      morning_start: settings.morning_start,
      morning_end: settings.morning_end,
      evening_start: settings.evening_start,
      evening_end: settings.evening_end,
    },
    days: dayInfos,
    counts,
    totals,
    holidays,
    leaves,
    payment,
  };
}

/** The live salary card for the current cycle. */
export async function liveSalary(ctx: Ctx) {
  const now = nowIst();
  const month = now.date.slice(0, 7);
  const [s, lastRes] = await Promise.all([
    computeMonth(ctx, month, { now, ignoreSnapshot: true }),
    ctx.sb.from("payments").select("month,total_amount,paid_on")
      .eq("house_id", ctx.house.id).order("month", { ascending: false }).limit(1).maybeSingle(),
  ]);
  const payday = `${nextMonth(month)}-01`;
  const lastPayment = must(lastRes);
  return {
    month,
    from: `${month}-01`,
    today: now.date,
    cycle_end: monthBounds(month).last,
    earned: s.totals.earned,
    expected_total: s.totals.expected_total,
    remaining_expected: s.totals.remaining_expected,
    lost: s.totals.lost,
    payday,
    days_to_payday: daysBetween(now.date, payday),
    breakdown: {
      weekday_visits: s.counts.weekday_visits,
      weekday_rate: s.rates.weekday_rate,
      weekday_amount: s.totals.weekday_amount,
      weekend_visits: s.counts.weekend_visits,
      weekend_rate: s.rates.weekend_rate,
      weekend_amount: s.totals.weekend_amount,
      paid_off_slots: s.counts.paid_off_slots,
      paid_off_rate: s.rates.paid_off_rate,
      paid_off_amount: s.totals.paid_off_amount,
      total: s.totals.earned,
    },
    counts: s.counts,
    last_payment: lastPayment,
    today_info: s.days.find((d) => d.date === now.date) ?? null,
  };
}
