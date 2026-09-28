// All business dates/times are Asia/Kolkata (UTC+5:30, no daylight saving).

const IST_OFFSET_MIN = 330;

export interface IstNow {
  date: string; // YYYY-MM-DD
  minutes: number; // minutes since IST midnight
  dow: number; // 0 = Sunday … 6 = Saturday
  iso: string; // UTC ISO string of the instant
}

export function toIst(instant: Date): IstNow {
  const shifted = new Date(instant.getTime() + IST_OFFSET_MIN * 60000);
  const date = shifted.toISOString().slice(0, 10);
  return {
    date,
    minutes: shifted.getUTCHours() * 60 + shifted.getUTCMinutes(),
    dow: shifted.getUTCDay(),
    iso: instant.toISOString(),
  };
}

export const nowIst = () => toIst(new Date());

/** Day of week for a YYYY-MM-DD date (0 = Sunday). */
export function dowOf(date: string): number {
  return new Date(date + "T00:00:00Z").getUTCDay();
}

export const isWeekend = (date: string) => {
  const d = dowOf(date);
  return d === 0 || d === 6;
};

export function addDays(date: string, n: number): string {
  const d = new Date(date + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

export const monthOf = (date: string) => date.slice(0, 7);

export function monthBounds(month: string): { first: string; last: string; days: string[] } {
  const [y, m] = month.split("-").map(Number);
  const first = `${month}-01`;
  const lastDay = new Date(Date.UTC(y, m, 0)).getUTCDate();
  const days: string[] = [];
  for (let i = 1; i <= lastDay; i++) days.push(`${month}-${String(i).padStart(2, "0")}`);
  return { first, last: days[days.length - 1], days };
}

export function prevMonth(month: string): string {
  const [y, m] = month.split("-").map(Number);
  const d = new Date(Date.UTC(y, m - 2, 1));
  return d.toISOString().slice(0, 7);
}

export function nextMonth(month: string): string {
  const [y, m] = month.split("-").map(Number);
  const d = new Date(Date.UTC(y, m, 1));
  return d.toISOString().slice(0, 7);
}

export function isValidDate(s: unknown): s is string {
  return typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s) &&
    !isNaN(Date.parse(s + "T00:00:00Z"));
}

export function isValidMonth(s: unknown): s is string {
  return typeof s === "string" && /^\d{4}-(0[1-9]|1[0-2])$/.test(s);
}

/** "06:00:00" → 360 */
export function timeToMin(t: string): number {
  const [h, m] = t.split(":").map(Number);
  return h * 60 + (m || 0);
}

/** 360 → "6 AM", 750 → "12:30 PM" */
export function minToLabel(min: number): string {
  const h = Math.floor(min / 60) % 24;
  const m = min % 60;
  const ap = h < 12 ? "AM" : "PM";
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return m ? `${h12}:${String(m).padStart(2, "0")} ${ap}` : `${h12} ${ap}`;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const MONTHS_LONG = ["January", "February", "March", "April", "May", "June", "July", "August",
  "September", "October", "November", "December"];

/** "2026-09-30" → "30 Sep" */
export function shortDate(date: string): string {
  const [, m, d] = date.split("-").map(Number);
  return `${d} ${MONTHS[m - 1]}`;
}

/** "2026-09" → "September 2026" */
export function monthLabel(month: string): string {
  const [y, m] = month.split("-").map(Number);
  return `${MONTHS_LONG[m - 1]} ${y}`;
}

export function monthName(month: string): string {
  return MONTHS_LONG[Number(month.split("-")[1]) - 1];
}

/** Whole days from a to b (both YYYY-MM-DD). */
export function daysBetween(a: string, b: string): number {
  return Math.round((Date.parse(b + "T00:00:00Z") - Date.parse(a + "T00:00:00Z")) / 86400000);
}
